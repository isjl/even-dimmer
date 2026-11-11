import Foundation
import SystemControls

/// What we know about this particular Mac's keyboard backlight.
struct Calibration: Codable, Equatable {
    /// Bump to force every Mac to recalibrate after a change to the routine.
    static let currentVersion = 1

    var version = Calibration.currentVersion
    /// Hardware model (e.g. "MacBookAir10,1") and macOS build this was measured on.
    var model: String
    var osBuild: String
    /// Lowest brightness macOS keeps on. Anything lower gets switched off.
    var dimmest: Float
    /// Light output ≈ `intercept + slope * brightness`, from CoreBrightness's own estimate.
    var intercept: Double
    var slope: Double

    /// Values measured on an M1 MacBook Air (macOS 26), used until calibration finishes
    /// or if this Mac can't report a light level.
    static func fallback(model: String = Mac.model, osBuild: String = Mac.osBuild) -> Calibration {
        Calibration(model: model, osBuild: osBuild, dimmest: 0.0002, intercept: 0.1, slope: 14.56)
    }

    var isCurrent: Bool {
        version == Self.currentVersion && model == Mac.model && osBuild == Mac.osBuild
    }

    // MARK: Slider mapping
    // Eyes perceive light roughly logarithmically, so the slider moves evenly in log(light).

    func light(_ b: Float) -> Double { intercept + slope * Double(b) }
    private var logLo: Double { log(light(dimmest)) }
    private var logHi: Double { log(light(1)) }

    func brightness(forPosition p: Double) -> Float {
        let target = exp(logLo + (logHi - logLo) * min(max(p, 0), 1))
        return min(max(Float((target - intercept) / slope), dimmest), 1)
    }

    func position(forBrightness b: Float) -> Double {
        let b = min(max(b, dimmest), 1)
        return (log(light(b)) - logLo) / (logHi - logLo)
    }
}

enum Mac {
    static let model: String = sysctlString("hw.model") ?? "unknown"
    static let osBuild: String = sysctlString("kern.osversion") ?? "unknown"

    /// Apple's lowest brightness-key step on models we've measured. Other Macs learn it
    /// the first time the user presses the brightness-down key to its lowest step.
    static let knownLowestKeyStep: [String: Float] = [
        "MacBookAir10,1": 0.0105, // M1 MacBook Air
    ]

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }
}

/// Measures this Mac's keyboard backlight. Everything it tries is at or below Apple's
/// lowest step, so the keyboard only flickers very faintly for a second or two.
@MainActor
enum Calibrator {
    /// Returns nil if macOS idle-dimmed the keyboard mid-way, which makes the readings
    /// meaningless; the caller should use the fallback and try again later.
    static func run(_ backlight: KeyboardBacklight) async -> Calibration? {
        var result = Calibration.fallback()
        let original = backlight.brightness()

        // 1. Light curve: two low points are enough, since the reported output is linear.
        backlight.setBrightnessTemporarily(0.01)
        await pause(0.05)
        let l1 = Double(backlight.lightLevel())
        backlight.setBrightnessTemporarily(0.02)
        await pause(0.05)
        let l2 = Double(backlight.lightLevel())
        if l1 > 0, l2 > l1 {
            let slope = (l2 - l1) / 0.01
            result.slope = slope
            // Keep a small positive floor so the log scale never breaks.
            result.intercept = max(l1 - slope * 0.01, slope * 0.0001)
        }

        // 2. Dimmest level: macOS switches very small values off about a second after
        //    they're saved. Try from the lowest up and keep the first one that stays on.
        let candidates: [Float] = [0.00015, 0.0002, 0.0003, 0.0005, 0.001, 0.002, 0.005]
        result.dimmest = candidates.last!
        var interrupted = false
        for value in candidates {
            backlight.setBrightness(value)
            await pause(1.2)
            if backlight.isIdleDimmed() {
                interrupted = true
                break
            }
            if backlight.brightness() > value / 2 {
                result.dimmest = value
                break
            }
        }

        backlight.setBrightness(original)
        return interrupted ? nil : result
    }

    private static func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

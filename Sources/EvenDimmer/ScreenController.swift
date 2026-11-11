import AppKit
import Combine
import CoreGraphics

/// Built-in screen brightness over the full hardware range, plus "extra dim"
/// below Apple's lowest setting.
///
/// The slider has three parts, left to right:
/// 1. **Software dim**: backlight at its hardware floor, and the display's gamma table
///    scaled down so the picture gets darker. The scaled table starts from whatever
///    macOS is using (Night Shift / True Tone tints are kept), and macOS restores the
///    original automatically when the app quits or crashes.
/// 2. **Hardware extra dim**: backlight between its floor and Apple's lowest key step.
///    DisplayServices accepts any value above 0; only exactly 0 switches it off.
/// 3. **Normal range**: Apple's lowest key step up to full brightness.
@MainActor
final class ScreenController: ObservableObject {
    /// Apple's lowest brightness-key step: the keys move in 16 steps of 1/16.
    static let appleLowest: Float = 1.0 / 16
    /// Lowest backlight value we use. 0 would switch the backlight off.
    static let hardwareFloor: Float = 0.001
    /// Darkest software dim, as a fraction of the light at the hardware floor.
    static let dimmestScale: Double = 0.1

    /// Slider shares for the three parts.
    static let softwareShare = 0.25
    static let hardwareExtraShare = 0.10
    static var appleLowestPosition: Double { softwareShare + hardwareExtraShare }

    private let defaults = UserDefaults.standard
    private let display = DisplayBrightness()
    private var baseTable: GammaTable?
    private var appliedScale: Double = 1
    private var pendingExternal: Float?
    private var pollTimer: Timer?
    private var isSyncing = false

    @Published private(set) var isAvailable: Bool
    @Published private(set) var levelDescription = ""
    /// Slider position: 0 = dimmest possible, appleLowestPosition = Apple's lowest, 1 = full.
    @Published var position: Double {
        didSet {
            guard !isSyncing else { return }
            defaults.set(position, forKey: "screenPosition")
            apply()
        }
    }

    init() {
        isAvailable = display.isAvailable
        let hardware = display.brightness() ?? 0.5
        let saved = UserDefaults.standard.object(forKey: "screenPosition") as? Double
        // Only bring back an extra-dim level if the screen is still at Apple's lowest or
        // below; otherwise the user changed brightness since, so start from what's on screen.
        if let saved, saved < Self.appleLowestPosition, hardware > 0, hardware <= Self.appleLowest + 0.001 {
            position = saved
        } else {
            position = Self.position(hardware: hardware)
        }

        guard isAvailable else { return }
        apply()

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reapplyAfterDelay() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reapplyAfterDelay() }
        }
        // Fast enough that the slider keeps up with the brightness keys.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    // MARK: - Mapping

    /// Backlight value (0...1) and software scale (dimmestScale...1) for a slider position.
    static func target(for p: Double) -> (hardware: Float, scale: Double) {
        let p = min(max(p, 0), 1)
        let apple = appleLowestPosition
        if p >= apple {
            let t = Float((p - apple) / (1 - apple))
            return (appleLowest + (1 - appleLowest) * t, 1)
        }
        if p >= softwareShare {
            let t = Float((p - softwareShare) / hardwareExtraShare)
            return (hardwareFloor + (appleLowest - hardwareFloor) * t, 1)
        }
        // Log scale, so each step looks about the same.
        let t = p / softwareShare
        return (hardwareFloor, dimmestScale * pow(1 / dimmestScale, t))
    }

    static func position(hardware h: Float) -> Double {
        let apple = appleLowestPosition
        if h >= appleLowest {
            return apple + (1 - apple) * Double((h - appleLowest) / (1 - appleLowest))
        }
        let t = Double((max(h, hardwareFloor) - hardwareFloor) / (appleLowest - hardwareFloor))
        return softwareShare + hardwareExtraShare * t
    }

    private func updateDescription() {
        guard let hardware = display.brightness() else { return }
        if hardware == 0 {
            levelDescription = "Screen backlight is off"
            return
        }
        // Compare actual light output against Apple's lowest, using the backlight's own
        // linear (light-proportional) reading where available.
        if let linear = display.linearBrightness(), let minimum = display.linearMinimum, minimum > 0 {
            let relative = Double(linear / minimum) * appliedScale
            if relative < 0.995 {
                levelDescription = "Extra dim: about \(Int((relative * 100).rounded()))% of Apple's lowest setting"
                return
            }
        } else if hardware < Self.appleLowest - 0.001 || appliedScale < 0.995 {
            levelDescription = "Extra dim: below Apple's lowest setting"
            return
        }
        let pct = Int((Double(hardware) * 100).rounded())
        levelDescription = hardware <= Self.appleLowest + 0.001 ? "Apple's lowest setting" : "Brightness: \(pct)%"
    }

    // MARK: - Brightness keys

    /// Each press below Apple's lowest moves the slider by this much (7 steps in all).
    static let keyStep = 0.05

    /// Called for the screen brightness keys. At or below Apple's lowest step it moves
    /// through extra dim and returns true (the press is swallowed); otherwise it returns
    /// false and macOS handles the key as usual.
    func handleKey(up: Bool) -> Bool {
        guard isAvailable, let hardware = display.brightness(), hardware > 0 else { return false }
        let apple = Self.appleLowestPosition
        let inExtraDim = position < apple - 0.001
        let step = position / Self.keyStep
        if up {
            guard inExtraDim else { return false }
            position = min(apple, ((step + 0.01).rounded(.down) + 1) * Self.keyStep)
        } else {
            guard inExtraDim || abs(hardware - Self.appleLowest) < 0.001 else { return false }
            position = max(0, ((step - 0.01).rounded(.up) - 1) * Self.keyStep)
        }
        LevelHUD.shared.show(symbol: "sun.min",
                             title: position < apple - 0.001 ? "Extra dim" : "Apple's lowest",
                             level: position / apple)
        return true
    }

    // MARK: - Applying

    func apply() {
        guard isAvailable else { return }
        let t = Self.target(for: position)
        if let current = display.brightness(), abs(current - t.hardware) > 0.0005 {
            display.setBrightness(t.hardware)
        }
        pendingExternal = nil
        setGammaScale(t.scale)
        updateDescription()
    }

    /// Puts the screen colours back exactly as macOS had them (used on quit).
    func restoreGamma() {
        guard baseTable != nil else { return }
        CGDisplayRestoreColorSyncSettings()
        baseTable = nil
        appliedScale = 1
    }

    private func setGammaScale(_ scale: Double) {
        guard let id = display.displayID else { return }
        if scale >= 0.995 {
            restoreGamma()
            return
        }
        if baseTable == nil { baseTable = GammaTable.read(id) }
        guard let base = baseTable else { return }
        base.scaled(by: scale).write(id)
        appliedScale = scale
    }

    private func reapplyAfterDelay() {
        // After wake or a display change macOS reloads its own gamma; start again from it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            self.baseTable = nil
            self.apply()
        }
    }

    private func poll() {
        guard isAvailable, let now = display.brightness() else { return }

        // Brightness keys / Control Center moved the backlight: follow it. Some Macs fade
        // brightness, so wait until the value holds for two polls (0.2 s apart).
        let target = Self.target(for: position).hardware
        if abs(now - target) > 0.002 {
            if let pending = pendingExternal, abs(pending - now) < 0.0005 {
                pendingExternal = nil
                isSyncing = true
                position = Self.position(hardware: now)
                isSyncing = false
                defaults.set(position, forKey: "screenPosition")
                restoreGamma()
                updateDescription()
            } else {
                pendingExternal = now
            }
            return
        }
        pendingExternal = nil

        // macOS replaced the gamma table (Night Shift changing, display reset): rebuild ours.
        if baseTable != nil, let id = display.displayID, let current = GammaTable.read(id),
           let expected = baseTable?.scaled(by: appliedScale), !current.isClose(to: expected) {
            baseTable = current
            setGammaScale(appliedScale)
        }
    }
}

// MARK: - Hardware access

/// Built-in display backlight via the private DisplayServices framework.
struct DisplayBrightness {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias RangeFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>, UnsafeMutablePointer<Float>) -> Int32
    private let getFn: GetFn?
    private let setFn: SetFn?
    private let linearFn: GetFn?
    private let rangeFn: RangeFn?

    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
        getFn = dlsym(handle, "DisplayServicesGetBrightness").map { unsafeBitCast($0, to: GetFn.self) }
        setFn = dlsym(handle, "DisplayServicesSetBrightness").map { unsafeBitCast($0, to: SetFn.self) }
        linearFn = dlsym(handle, "DisplayServicesGetLinearBrightness").map { unsafeBitCast($0, to: GetFn.self) }
        rangeFn = dlsym(handle, "DisplayServicesGetLinearBrightnessUsableRange").map { unsafeBitCast($0, to: RangeFn.self) }
    }

    /// The built-in screen, if it's on (not when the lid is closed).
    var displayID: CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success else { return nil }
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    var isAvailable: Bool { getFn != nil && setFn != nil && brightness() != nil }

    func brightness() -> Float? {
        guard let getFn, let id = displayID else { return nil }
        var value: Float = 0
        return getFn(id, &value) == 0 ? value : nil
    }

    func setBrightness(_ value: Float) {
        guard let setFn, let id = displayID else { return }
        _ = setFn(id, min(max(value, 0), 1))
    }

    /// Current backlight output on a scale proportional to light (1 = maximum).
    func linearBrightness() -> Float? {
        guard let linearFn, let id = displayID else { return nil }
        var value: Float = 0
        return linearFn(id, &value) == 0 && value > 0 ? value : nil
    }

    /// Linear output at Apple's lowest key step (the bottom of macOS's "usable range").
    var linearMinimum: Float? {
        guard let rangeFn, let id = displayID else { return nil }
        var lo: Float = 0, hi: Float = 0
        return rangeFn(id, &lo, &hi) == 0 && lo > 0 ? lo : nil
    }
}

/// A display's red/green/blue transfer tables.
struct GammaTable {
    var red: [CGGammaValue], green: [CGGammaValue], blue: [CGGammaValue]

    static func read(_ id: CGDirectDisplayID) -> GammaTable? {
        let capacity = max(CGDisplayGammaTableCapacity(id), 2)
        var r = [CGGammaValue](repeating: 0, count: Int(capacity))
        var g = r, b = r
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(id, capacity, &r, &g, &b, &count) == .success, count > 1 else { return nil }
        let n = Int(count)
        return GammaTable(red: Array(r.prefix(n)), green: Array(g.prefix(n)), blue: Array(b.prefix(n)))
    }

    func write(_ id: CGDirectDisplayID) {
        _ = CGSetDisplayTransferByTable(id, UInt32(red.count), red, green, blue)
    }

    func scaled(by s: Double) -> GammaTable {
        let f = CGGammaValue(s)
        return GammaTable(red: red.map { $0 * f }, green: green.map { $0 * f }, blue: blue.map { $0 * f })
    }

    func isClose(to other: GammaTable) -> Bool {
        guard red.count == other.red.count, let a = red.last, let b = other.red.last,
              let c = blue.last, let d = other.blue.last else { return false }
        return abs(a - b) < 0.01 && abs(c - d) < 0.01
    }
}

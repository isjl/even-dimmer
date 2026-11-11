import AppKit
import Combine
import SystemControls
import ServiceManagement

/// Owns the keyboard backlight, remembers the user's chosen level, follows the
/// brightness keys, and re-applies the level after sleep / unlock.
@MainActor
final class BacklightController: ObservableObject {
    private let backlight: KeyboardBacklight
    private let defaults = UserDefaults.standard
    private var lastApplied: Float?
    /// Last level set by macOS itself (keys / Control Center), not by us.
    private var lastExternal: Float?
    private var pendingExternal: Float?
    private var pollTimer: Timer?
    private var isSyncing = false

    @Published private(set) var isAvailable: Bool
    /// True while the one-time per-Mac measurement is running.
    @Published private(set) var isCalibrating = false
    @Published private(set) var calibration: Calibration
    /// Apple's lowest brightness-key step on this Mac, once known.
    @Published private(set) var appleLowest: Float?
    /// True when the backlight is fully off (switch or keys).
    @Published private(set) var isOff = false
    /// Slider position: 0 = dimmest possible, 1 = full brightness.
    @Published var position: Double {
        didSet {
            guard !isSyncing else { return }
            defaults.set(position, forKey: "position")
            apply()
        }
    }
    @Published var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled {
        didSet { setLaunchAtLogin(launchAtLogin) }
    }

    private static let calibrationKey = "calibration"
    private static var appleLowestKey: String { "appleLowest.\(Mac.model)" }

    init() {
        let backlight = KeyboardBacklight()
        self.backlight = backlight
        isAvailable = backlight.isAvailable

        let saved = (UserDefaults.standard.data(forKey: Self.calibrationKey))
            .flatMap { try? JSONDecoder().decode(Calibration.self, from: $0) }
        let calibration = saved?.isCurrent == true ? saved! : Calibration.fallback()
        self.calibration = calibration
        appleLowest = (UserDefaults.standard.object(forKey: Self.appleLowestKey) as? Float)
            ?? Mac.knownLowestKeyStep[Mac.model]

        let current = backlight.isAvailable ? backlight.brightness() : 0
        position = UserDefaults.standard.object(forKey: "position") as? Double
            ?? calibration.position(forBrightness: current)
        // While idle-dimmed the level reads 0, which says nothing about the user's
        // setting; leave it unknown until the next key press (see followExternalChange).
        let idle = backlight.isAvailable && backlight.isIdleDimmed()
        lastApplied = idle ? nil : current
        isOff = backlight.isAvailable && !idle && current == 0

        guard isAvailable else { return }

        if saved?.isCurrent == true {
            start()
        } else {
            Task { await recalibrate(thenStart: true) }
        }
    }

    private func start() {
        if !isOff, lastApplied != nil { apply() }

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reapplyAfterDelay() }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reapplyAfterDelay() }
        }

        // Follow the keyboard-brightness keys / Control Center so the slider stays in sync.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.followExternalChange() }
        }
    }

    /// Measures this Mac's backlight (a second or two) and saves the result.
    func recalibrate(thenStart: Bool = false) async {
        guard isAvailable, !isCalibrating else { return }
        isCalibrating = true
        let hadSavedPosition = defaults.object(forKey: "position") != nil
        let measured = await Calibrator.run(backlight)
        let result = measured ?? .fallback()
        calibration = result
        // Only save a complete measurement; otherwise measure again on the next launch.
        if let measured, let data = try? JSONEncoder().encode(measured) {
            defaults.set(data, forKey: Self.calibrationKey)
        }

        let current = backlight.brightness()
        let idle = backlight.isIdleDimmed()
        lastApplied = idle ? nil : current
        isOff = !idle && current == 0
        if !hadSavedPosition {
            isSyncing = true
            position = result.position(forBrightness: current)
            isSyncing = false
        }
        isCalibrating = false
        if thenStart { start() } else if !isOff { apply() }
    }

    // MARK: - Display helpers

    var currentBrightness: Float { calibration.brightness(forPosition: position) }

    /// Where Apple's lowest key step sits on the slider, if known.
    var appleLowestPosition: Double? { appleLowest.map { calibration.position(forBrightness: $0) } }

    /// Text shown under the slider.
    var levelDescription: String {
        if isCalibrating { return "Measuring this Mac's keyboard light…" }
        if isOff { return "Keyboard light is off" }
        let b = currentBrightness
        if let low = appleLowest, b < low * 0.98 {
            let pct = Int((calibration.light(b) / calibration.light(low) * 100).rounded())
            return "Extra dim: about \(pct)% of Apple's lowest setting"
        }
        let pct = Double(b) * 100
        return pct < 1 ? "Brightness: under 1%" : "Brightness: \(Int(pct.rounded()))%"
    }

    // MARK: - Brightness keys

    /// Called for the keyboard-light keys (on Macs that have them). Between Apple's
    /// lowest step and the dimmest level it moves through extra dim and returns true;
    /// otherwise macOS handles the key. At the dimmest level "down" goes to macOS,
    /// which switches the light off.
    func handleKey(up: Bool) -> Bool {
        guard isAvailable, !isCalibrating, !isOff, let mark = appleLowestPosition, mark > 0 else { return false }
        let step = mark / 4
        let inExtraDim = position < mark - 0.001
        let index = position / step
        if up {
            guard inExtraDim else { return false }
            position = min(mark, ((index + 0.01).rounded(.down) + 1) * step)
        } else {
            let atLowest = abs(position - mark) < 0.01
            guard (inExtraDim || atLowest), position > 0.001 else { return false }
            position = max(0, ((index - 0.01).rounded(.up) - 1) * step)
        }
        LevelHUD.shared.show(symbol: "light.min",
                             title: position < mark - 0.001 ? "Extra dim" : "Apple's lowest",
                             level: position / mark)
        return true
    }

    // MARK: - Applying

    func apply() {
        guard isAvailable, !isCalibrating else { return }
        if backlight.isAutoBrightnessEnabled() { backlight.setAutoBrightnessEnabled(false) }
        backlight.setBrightness(currentBrightness)
        lastApplied = backlight.brightness()
        lastExternal = nil
        isOff = false
    }

    /// Turns the backlight fully off, or back on at the slider's level.
    func setLightOn(_ on: Bool) {
        guard isAvailable, !isCalibrating else { return }
        if on {
            apply()
        } else {
            backlight.setBrightness(0)
            lastApplied = backlight.brightness()
            lastExternal = nil
            isOff = true
        }
    }

    private func reapplyAfterDelay() {
        // macOS restores its own value shortly after wake; wait for that, then re-apply ours.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, !self.isOff else { return }
            self.apply()
        }
    }

    private func followExternalChange() {
        guard isAvailable, !isCalibrating else { return }
        let now = backlight.brightness()
        guard let last = lastApplied else {
            // We started while idle-dimmed. Once the light is back, pick up from there:
            // restore the saved level, or follow whatever the keyboard is at.
            guard !backlight.isIdleDimmed() else { return }
            isOff = now == 0
            if !isOff { apply() } else { lastApplied = now }
            return
        }
        guard abs(now - last) > 0.00005 else { pendingExternal = nil; return }
        // Idle dimming (no typing for a while) makes the level read 0 until the next
        // key press; that isn't the user's choice, so ignore it.
        if backlight.isIdleDimmed() { pendingExternal = nil; return }
        // macOS also reports "suppressed" whenever the level is 0, so only skip
        // suppression (lid closed, bright room) while the light is meant to be on.
        if now != 0, backlight.isSuppressed() { return }
        // Key presses can fade the level; only act once it holds for two polls, so a
        // value caught mid-fade is never mistaken for a key step.
        guard let pending = pendingExternal, abs(pending - now) < 0.00001 else {
            pendingExternal = now
            return
        }
        pendingExternal = nil

        // The user pressed the brightness keys (or used Control Center): mirror it on the slider.
        // Pressing brightness-down at Apple's lowest step turns the light off, so the
        // level macOS set just before going to 0 is that lowest step.
        if now == 0, let previous = lastExternal { learnAppleLowest(previous) }
        lastExternal = now == 0 ? nil : now
        lastApplied = now
        isOff = now == 0
        if !isOff {
            isSyncing = true
            position = calibration.position(forBrightness: now)
            isSyncing = false
            defaults.set(position, forKey: "position")
        }
    }

    private func learnAppleLowest(_ value: Float) {
        guard Mac.knownLowestKeyStep[Mac.model] == nil,   // built-in value wins
              value > calibration.dimmest * 1.5, value < 0.1,
              value < (appleLowest ?? .infinity) * 1.01 else { return }
        appleLowest = value
        defaults.set(value, forKey: Self.appleLowestKey)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("EvenDimmer: launch-at-login change failed: \(error)")
        }
    }
}

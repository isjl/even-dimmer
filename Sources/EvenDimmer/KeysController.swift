import Combine
import Foundation

/// The "brightness keys go below Apple's lowest" setting and its Accessibility permission.
@MainActor
final class KeysController: ObservableObject {
    private let keys = BrightnessKeys()
    private var permissionTimer: Timer?

    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "keys.enabled")
            if enabled && !BrightnessKeys.hasPermission { BrightnessKeys.requestPermission() }
            update()
        }
    }
    @Published private(set) var hasPermission = BrightnessKeys.hasPermission
    @Published private(set) var isActive = false

    init(screen: ScreenController, keyboard: BacklightController) {
        enabled = UserDefaults.standard.bool(forKey: "keys.enabled")
        keys.handler = { key in
            switch key {
            case .screenDown: return screen.handleKey(up: false)
            case .screenUp: return screen.handleKey(up: true)
            case .keyboardDown: return keyboard.handleKey(up: false)
            case .keyboardUp: return keyboard.handleKey(up: true)
            }
        }
        // The permission can be granted (or revoked) in System Settings at any time.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.update() }
        }
        update()
    }

    func openSettings() {
        BrightnessKeys.requestPermission()
        BrightnessKeys.openAccessibilitySettings()
    }

    /// macOS ties the permission to the app's exact code signature. After an update (or a
    /// rebuild) the old entry stays switched on in System Settings but no longer applies.
    /// This removes Even Dimmer's stale entry and asks again, so the user only has to
    /// switch it on once more.
    func resetPermission() {
        let tccutil = Process()
        tccutil.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        tccutil.arguments = ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "io.github.evendimmer"]
        try? tccutil.run()
        tccutil.waitUntilExit()
        openSettings()
    }

    private func update() {
        let permitted = BrightnessKeys.hasPermission
        if permitted != hasPermission { hasPermission = permitted }
        if enabled && permitted {
            if !keys.isRunning { keys.start() }
        } else if keys.isRunning {
            keys.stop()
        }
        if isActive != keys.isRunning { isActive = keys.isRunning }
    }
}

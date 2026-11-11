import AppKit
import ApplicationServices

/// Watches the brightness keys (screen and keyboard light) so that, at Apple's lowest
/// step, pressing "down" continues into extra dim instead of switching the light off.
///
/// Uses a CGEvent tap on system-defined (media key) events, which needs the
/// Accessibility permission. Events the handler doesn't want pass through untouched.
@MainActor
final class BrightnessKeys {
    enum Key { case screenUp, screenDown, keyboardUp, keyboardDown }

    /// Return true to swallow the key press (macOS won't act on it).
    var handler: ((Key) -> Bool)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    /// Keys whose "down" we swallowed, so we also swallow the matching "up".
    private var swallowed = Set<Int>()

    static var hasPermission: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that sends the user to System Settings → Accessibility.
    static func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    var isRunning: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        guard tap == nil, Self.hasPermission else { return tap != nil }
        let mask = CGEventMask(1) << CGEventMask(NSEvent.EventType.systemDefined.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: brightnessKeyCallback, userInfo: refcon
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        swallowed.removeAll()
    }

    // Media key codes from IOKit's ev_keymap.h.
    private static let codes: [Int: Key] = [
        2: .screenUp, 3: .screenDown,        // NX_KEYTYPE_BRIGHTNESS_UP / DOWN
        21: .keyboardUp, 22: .keyboardDown,  // NX_KEYTYPE_ILLUMINATION_UP / DOWN
    ]

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS switches a tap off if it's too slow or the user is typing a password.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard let ns = NSEvent(cgEvent: event), ns.type == .systemDefined, ns.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }
        let code = (ns.data1 & 0xFFFF_0000) >> 16
        let isDown = (ns.data1 & 0xFF00) >> 8 == 0xA
        guard let key = Self.codes[code] else { return Unmanaged.passUnretained(event) }

        if isDown {
            if handler?(key) == true {
                swallowed.insert(code)
                return nil
            }
            swallowed.remove(code)
            return Unmanaged.passUnretained(event)
        }
        // Key up: swallow it only if we swallowed the press.
        return swallowed.remove(code) != nil ? nil : Unmanaged.passUnretained(event)
    }
}

private func brightnessKeyCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let keys = Unmanaged<BrightnessKeys>.fromOpaque(refcon).takeUnretainedValue()
    // The tap's run loop source is on the main run loop, so this is the main thread.
    return MainActor.assumeIsolated { keys.handle(type, event) }
}

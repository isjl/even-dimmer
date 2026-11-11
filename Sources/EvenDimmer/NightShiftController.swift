import Combine
import Foundation
import SystemControls

/// Night Shift on/off and warmth, kept in sync with System Settings / Control Center.
@MainActor
final class NightShiftController: ObservableObject {
    private let nightShift = NightShift()
    private var pollTimer: Timer?
    private var isSyncing = false

    @Published private(set) var isAvailable: Bool
    @Published var isOn: Bool {
        didSet { if !isSyncing { nightShift.setEnabled(isOn) } }
    }
    /// 0 = least warm, 1 = most warm.
    @Published var strength: Double {
        didSet { if !isSyncing { nightShift.setStrength(Float(strength)) } }
    }

    init() {
        isAvailable = nightShift.isAvailable
        isOn = nightShift.isEnabled()
        strength = Double(nightShift.strength())
        guard isAvailable else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sync() }
        }
    }

    /// Picks up changes made elsewhere (System Settings, Control Center, the schedule).
    private func sync() {
        let on = nightShift.isEnabled()
        let s = Double(nightShift.strength())
        isSyncing = true
        if on != isOn { isOn = on }
        if abs(s - strength) > 0.005 { strength = s }
        isSyncing = false
    }
}

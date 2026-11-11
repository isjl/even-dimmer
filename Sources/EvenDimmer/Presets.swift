import AppKit
import Combine

/// A saved combination of screen, keyboard and Night Shift settings.
struct Preset: Codable, Equatable {
    var screen: Double
    var keyboardOn: Bool
    var keyboard: Double
    var nightShiftOn: Bool
    var nightShiftStrength: Double

    /// Screen at the backlight's floor, keyboard at its dimmest, Night Shift warm.
    static let defaultNight = Preset(screen: 0.25 /* backlight floor, see ScreenController.softwareShare */, keyboardOn: true, keyboard: 0,
                                     nightShiftOn: true, nightShiftStrength: 0.8)
    /// Comfortable indoor brightness, keyboard light off, Night Shift off.
    static let defaultDay = Preset(screen: 0.75, keyboardOn: false, keyboard: 0.5,
                                   nightShiftOn: false, nightShiftStrength: 0.5)
}

/// Night and Day presets, and the optional schedule that switches between them.
@MainActor
final class PresetController: ObservableObject {
    enum Kind: String { case night, day }

    private let keyboard: BacklightController
    private let screen: ScreenController
    private let nightShift: NightShiftController
    private let defaults = UserDefaults.standard
    private var timer: Timer?

    @Published var night: Preset { didSet { save(night, .night) } }
    @Published var day: Preset { didSet { save(day, .day) } }

    /// Switch automatically at the times below.
    @Published var scheduleEnabled: Bool {
        didSet {
            defaults.set(scheduleEnabled, forKey: "schedule.enabled")
            if scheduleEnabled { lastAutoPeriod = nil; checkSchedule() }
        }
    }
    /// Minutes after midnight.
    @Published var nightStart: Int { didSet { defaults.set(nightStart, forKey: "schedule.night"); rescheduleNow() } }
    @Published var dayStart: Int { didSet { defaults.set(dayStart, forKey: "schedule.day"); rescheduleNow() } }

    private var lastAutoPeriod: Kind? {
        get { defaults.string(forKey: "schedule.lastPeriod").flatMap(Kind.init) }
        set { defaults.set(newValue?.rawValue, forKey: "schedule.lastPeriod") }
    }

    init(keyboard: BacklightController, screen: ScreenController, nightShift: NightShiftController) {
        self.keyboard = keyboard
        self.screen = screen
        self.nightShift = nightShift
        night = Self.load(.night) ?? .defaultNight
        day = Self.load(.day) ?? .defaultDay
        scheduleEnabled = defaults.bool(forKey: "schedule.enabled")
        nightStart = defaults.object(forKey: "schedule.night") as? Int ?? 22 * 60
        dayStart = defaults.object(forKey: "schedule.day") as? Int ?? 7 * 60

        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkSchedule() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // Give the screen and keyboard controllers time to restore themselves first.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self?.checkSchedule() }
        }
        // Let the other controllers finish starting (and the keyboard calibrate).
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.checkSchedule() }
    }

    // MARK: - Presets

    func apply(_ kind: Kind) {
        let p = kind == .night ? night : day
        screen.position = p.screen
        if keyboard.isAvailable {
            if p.keyboardOn {
                keyboard.position = p.keyboard
                keyboard.setLightOn(true)
            } else {
                keyboard.setLightOn(false)
            }
        }
        if nightShift.isAvailable {
            nightShift.isOn = p.nightShiftOn
            if p.nightShiftOn { nightShift.strength = p.nightShiftStrength }
        }
    }

    /// Stores what's on screen right now as the Night or Day preset.
    func saveCurrent(as kind: Kind) {
        let current = Preset(screen: screen.position, keyboardOn: !keyboard.isOff, keyboard: keyboard.position,
                             nightShiftOn: nightShift.isOn, nightShiftStrength: nightShift.strength)
        if kind == .night { night = current } else { day = current }
    }

    func resetToDefaults() {
        night = .defaultNight
        day = .defaultDay
    }

    private func save(_ p: Preset, _ kind: Kind) {
        if let data = try? JSONEncoder().encode(p) { defaults.set(data, forKey: "preset.\(kind.rawValue)") }
    }

    private static func load(_ kind: Kind) -> Preset? {
        UserDefaults.standard.data(forKey: "preset.\(kind.rawValue)")
            .flatMap { try? JSONDecoder().decode(Preset.self, from: $0) }
    }

    // MARK: - Schedule

    /// Which preset the schedule says should be active at `date`.
    func period(at date: Date = Date()) -> Kind {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let now = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        if nightStart == dayStart { return .day }
        if nightStart < dayStart {
            return (now >= nightStart && now < dayStart) ? .night : .day
        }
        // Night wraps past midnight (e.g. 22:00 → 07:00).
        return (now >= nightStart || now < dayStart) ? .night : .day
    }

    /// Applies a preset only when the period changes, so manual adjustments in between
    /// are left alone.
    func checkSchedule() {
        guard scheduleEnabled else { return }
        let current = period()
        guard current != lastAutoPeriod else { return }
        lastAutoPeriod = current
        apply(current)
    }

    private func rescheduleNow() {
        // New times: switch only if they put us in the other period, so fiddling with
        // the time pickers doesn't keep re-applying a preset.
        checkSchedule()
    }
}

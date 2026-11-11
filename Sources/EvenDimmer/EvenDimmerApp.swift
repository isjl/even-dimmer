import SwiftUI

/// Owns every controller for the app's lifetime.
@MainActor
final class AppModel {
    let keyboard = BacklightController()
    let screen = ScreenController()
    let nightShift = NightShiftController()
    let updater = Updater()
    lazy var presets = PresetController(keyboard: keyboard, screen: screen, nightShift: nightShift)
    lazy var keys = KeysController(screen: screen, keyboard: keyboard)

    init() {
        _ = presets
        _ = keys
    }
}

@main
struct EvenDimmerApp: App {
    private let model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(keyboard: model.keyboard, screen: model.screen, nightShift: model.nightShift,
                        presets: model.presets, keys: model.keys, updater: model.updater)
        } label: {
            Image(systemName: "light.min")
        }
        .menuBarExtraStyle(.window)
    }
}

private enum Tab: String, CaseIterable {
    case screen = "Screen", keyboard = "Keyboard", settings = "Settings"
}

struct MenuContent: View {
    @ObservedObject var keyboard: BacklightController
    @ObservedObject var screen: ScreenController
    @ObservedObject var nightShift: NightShiftController
    @ObservedObject var presets: PresetController
    @ObservedObject var keys: KeysController
    @ObservedObject var updater: Updater
    @AppStorage("selectedTab") private var tab: Tab = .screen

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button { presets.apply(.night) } label: {
                    Label("Night", systemImage: "moon.fill").frame(maxWidth: .infinity)
                }
                .help("Switch to your Night settings")
                Button { presets.apply(.day) } label: {
                    Label("Day", systemImage: "sun.max.fill").frame(maxWidth: .infinity)
                }
                .help("Switch to your Day settings")
            }
            .controlSize(.large)
            // Not keyboard-focusable: otherwise "Night" gets the focus ring when the popup
            // opens and a stray Space press would switch presets.
            .focusable(false)

            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            // All tabs are laid out on top of each other so the popup keeps the height of
            // the tallest one; otherwise it jumps around when switching tabs.
            ZStack(alignment: .topLeading) {
                page(.screen) { ScreenTab(screen: screen, nightShift: nightShift) }
                page(.keyboard) { KeyboardTab(keyboard: keyboard) }
                page(.settings) {
                    SettingsTab(keyboard: keyboard, presets: presets, keys: keys, updater: updater)
                }
            }

            Divider()

            HStack {
                if tab == .keyboard, keyboard.isAvailable {
                    Button("Recalibrate keyboard") { Task { await keyboard.recalibrate() } }
                        .disabled(keyboard.isCalibrating)
                        .help("Measure this Mac's keyboard light again")
                }
                Spacer()
                Button("Quit") {
                    screen.restoreGamma()
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    private func page<Content: View>(_ t: Tab, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .opacity(tab == t ? 1 : 0)
            .allowsHitTesting(tab == t)
            .accessibilityHidden(tab != t)
    }
}

// MARK: - Settings tab

private struct SettingsTab: View {
    @ObservedObject var keyboard: BacklightController
    @ObservedObject var presets: PresetController
    @ObservedObject var keys: KeysController
    @ObservedObject var updater: Updater

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Brightness keys go below Apple's lowest", isOn: $keys.enabled)
            Text("At the lowest step, pressing brightness-down keeps dimming instead of turning the light off.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            if keys.enabled && !keys.hasPermission {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Needs Accessibility permission", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                    Text("Switch on Even Dimmer in System Settings → Privacy & Security → Accessibility. If it's already switched on there (for example after an update), click Reset permission and switch it on again.")
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Open System Settings…") { keys.openSettings() }
                        Button("Reset permission") { keys.resetPermission() }
                            .help("Removes Even Dimmer's old Accessibility entry and asks again")
                    }
                    .controlSize(.small)
                }
                .padding(.top, 2)
            }
        }

        Divider()

        VStack(alignment: .leading, spacing: 6) {
            Toggle("Switch to Night and Day automatically", isOn: $presets.scheduleEnabled)
            HStack {
                Text("Night from")
                DatePicker("", selection: time($presets.nightStart), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                Spacer()
                Text("Day from")
                DatePicker("", selection: time($presets.dayStart), displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
            .font(.caption)
            .disabled(!presets.scheduleEnabled)

            HStack(spacing: 6) {
                Text("Save current settings as").font(.caption)
                Button("Night") { presets.saveCurrent(as: .night) }
                Button("Day") { presets.saveCurrent(as: .day) }
            }
            .controlSize(.small)
            .padding(.top, 2)
        }

        Divider()

        VStack(alignment: .leading, spacing: 6) {
            Toggle("Open at login", isOn: $keyboard.launchAtLogin)
            HStack {
                Toggle("Check for updates automatically", isOn: $updater.automaticallyChecks)
                Spacer()
            }
            .disabled(!updater.isEnabled)
            HStack(spacing: 8) {
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.isEnabled || !updater.canCheck)
                    .controlSize(.small)
                if !updater.isEnabled {
                    Text("Not available in this build")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .toggleStyle(.checkbox)
    }

    /// Bridges "minutes after midnight" to a Date for the time pickers.
    private func time(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: minutes.wrappedValue / 60,
                                      minute: minutes.wrappedValue % 60, second: 0, of: Date()) ?? Date()
            },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }
}

// MARK: - Screen tab

private struct ScreenTab: View {
    @ObservedObject var screen: ScreenController
    @ObservedObject var nightShift: NightShiftController

    var body: some View {
        if !screen.isAvailable {
            Unavailable(text: "The built-in screen's brightness can't be changed on this Mac, or the lid is closed.")
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Brightness").font(.headline).padding(.bottom, 6)

                Slider(value: $screen.position, in: 0...1) {
                    EmptyView()
                } minimumValueLabel: {
                    Image(systemName: "sun.min").help("Dimmest possible")
                } maximumValueLabel: {
                    Image(systemName: "sun.max").help("Full brightness")
                }

                SystemMinimumMarker(position: ScreenController.appleLowestPosition)

                Text(screen.levelDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                HStack(spacing: 8) {
                    Button("Dimmest") { screen.position = 0 }
                    Button("Apple's lowest") { screen.position = ScreenController.appleLowestPosition }
                }
                .controlSize(.small)
                .padding(.top, 6)

                Text("Press the brightness-up key at any time to go back to normal.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }

        if nightShift.isAvailable {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $nightShift.isOn) {
                    Text("Night Shift").font(.headline)
                }
                .toggleStyle(.switch)

                Slider(value: $nightShift.strength, in: 0...1) {
                    EmptyView()
                } minimumValueLabel: {
                    Text("Less warm").font(.caption2)
                } maximumValueLabel: {
                    Text("More warm").font(.caption2)
                }
                .disabled(!nightShift.isOn)
            }
        }
    }
}

// MARK: - Keyboard tab

private struct KeyboardTab: View {
    @ObservedObject var keyboard: BacklightController

    var body: some View {
        if !keyboard.isAvailable {
            Unavailable(text: "No built-in keyboard backlight was found on this Mac.")
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Keyboard Light").font(.headline)
                    Spacer()
                    Toggle("Keyboard light", isOn: Binding(
                        get: { !keyboard.isOff },
                        set: { keyboard.setLightOn($0) }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(keyboard.isCalibrating)
                    .help("Turn the keyboard light completely off or back on")
                }
                .padding(.bottom, 6)

                Slider(value: $keyboard.position, in: 0...1) {
                    EmptyView()
                } minimumValueLabel: {
                    Image(systemName: "light.min").help("Dimmest possible")
                } maximumValueLabel: {
                    Image(systemName: "light.max").help("Full brightness")
                }
                .opacity(keyboard.isOff ? 0.5 : 1)
                .disabled(keyboard.isCalibrating)

                if let mark = keyboard.appleLowestPosition {
                    SystemMinimumMarker(position: mark)
                }

                HStack(spacing: 6) {
                    if keyboard.isCalibrating { ProgressView().controlSize(.mini) }
                    Text(keyboard.levelDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                HStack(spacing: 8) {
                    Button("Dimmest") { keyboard.position = 0 }
                    if let mark = keyboard.appleLowestPosition {
                        Button("Apple's lowest") { keyboard.position = mark }
                    }
                    Button("Full") { keyboard.position = 1 }
                }
                .controlSize(.small)
                .disabled(keyboard.isCalibrating)
                .padding(.top, 6)

                if keyboard.appleLowest == nil {
                    Text("Tip: press the brightness-down key until the light turns off. Even Dimmer will then mark Apple's lowest setting on the slider.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Shared pieces

private struct Unavailable: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A small tick under a slider showing where Apple's lowest step is;
/// everything left of it is "extra dim".
private struct SystemMinimumMarker: View {
    let position: Double
    // Approximate inset of the slider track caused by the two end icons.
    private let iconInset: CGFloat = 22

    var body: some View {
        GeometryReader { geo in
            let track = geo.size.width - iconInset * 2
            let x = iconInset + track * position
            VStack(alignment: .leading, spacing: 1) {
                Rectangle().frame(width: 1, height: 5)
                Text("Apple's lowest").font(.caption2)
                    .fixedSize()
                    .offset(x: -8)
            }
            .foregroundStyle(.tertiary)
            .offset(x: x)
        }
        .frame(height: 20)
    }
}

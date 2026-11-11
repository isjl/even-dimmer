import Combine
import Foundation
import Sparkle

/// Auto-updates via Sparkle. Updates are checked against the appcast on GitHub
/// Releases and verified with the EdDSA public key baked into Info.plist.
///
/// Automatic checks are off by default (SUEnableAutomaticChecks = false in Info.plist,
/// which also stops Sparkle from asking on second launch); the user can turn them on
/// in Settings. "Check for Updates…" always works on demand.
///
/// Builds without a public key (local development builds) have updates switched off,
/// so they never show confusing "update failed" errors.
@MainActor
final class Updater: ObservableObject {
    private let controller: SPUStandardUpdaterController?
    private var observation: NSKeyValueObservation?

    @Published private(set) var canCheck = false
    @Published var automaticallyChecks: Bool {
        didSet { controller?.updater.automaticallyChecksForUpdates = automaticallyChecks }
    }

    var isEnabled: Bool { controller != nil }

    init() {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        if !key.isEmpty, !feed.isEmpty {
            controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        } else {
            controller = nil
        }
        automaticallyChecks = controller?.updater.automaticallyChecksForUpdates ?? false
        observation = controller?.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let value = updater.canCheckForUpdates
            Task { @MainActor in self?.canCheck = value }
        }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}

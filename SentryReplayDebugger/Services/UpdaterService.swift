import Combine
import Foundation
import Sparkle

/// Wraps Sparkle's standard updater for use from SwiftUI.
///
/// The updater starts automatically and reads its feed URL and public key from
/// the app's Info.plist (`SUFeedURL`, `SUPublicEDKey`). It checks for updates in
/// the background and installs them on the next launch.
@MainActor
final class UpdaterService: ObservableObject {
    static let shared = UpdaterService()

    private let controller: SPUStandardUpdaterController

    /// Whether a manual update check can be started right now. Drives the
    /// enabled state of the "Check for Updates…" menu item.
    @Published private(set) var canCheckForUpdates = false

    /// Mirrors the updater's automatic-check preference for binding to a toggle.
    @Published var automaticallyChecksForUpdates: Bool {
        didSet {
            updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    private var updater: SPUUpdater { controller.updater }

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)
    }

    /// Presents Sparkle's update UI in response to a user action.
    func checkForUpdates() {
        updater.checkForUpdates()
    }
}

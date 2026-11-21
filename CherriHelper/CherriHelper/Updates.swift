// ===================================
// Updates
// v0.0.1 BUILD 2026-11-21@12:24
// Automatic update checks and the Check for Updates button, using Sparkle.
// dev by @dastefster 🍒🔨
// ===================================

import SwiftUI
import Combine
import Sparkle


// ===================================
// UPDATE CONTROLLER
// ===================================

@MainActor
final class UpdateController: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = UpdateController()

    @Published private(set) var canCheck = false
    private var controller: SPUStandardUpdaterController!

    var updater: SPUUpdater { controller.updater }

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)

        #if CHERRI_TEST_FEED
        // Test builds only: look for an update right away, and install it without asking.
        updater.checkForUpdatesInBackground()
        #endif
    }

    func checkNow() {
        controller.checkForUpdates(nil)
    }

    var automaticChecks: Bool {
        get { updater.automaticallyChecksForUpdates }
        set {
            updater.automaticallyChecksForUpdates = newValue
            objectWillChange.send()
        }
    }

    #if CHERRI_TEST_FEED
    // Test builds read their feed from here so an update can be tried against a local file without publishing anything.
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        UserDefaults.standard.string(forKey: "CherriTestFeedURL")
    }
    #endif
}


// ===================================
// Cherri App Entry Point
// v0.0.2 BUILD 2026-10-21 16:10
// Launches the main screen and starts the Premium store so purchases and refunds are picked up from the first frame.
// dev by @dastefster 🍒🔨
// ===================================

import SwiftUI

@main
struct CherriAppApp: App {
    @StateObject private var premium = PremiumStore.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(premium)
                .task { premium.start() }
        }
    }
}

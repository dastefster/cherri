// ===================================
// Cherri Helper
// v0.0.11 BUILD 2026-11-21@15:45
// Menu-bar app that signs Shortcuts for Cherri Shortcuts on this Mac, over an encrypted local connection.
// dev by @dastefster 🍒🔨
// ===================================

import SwiftUI
import ServiceManagement


// ===================================
// APP ENTRY
// ===================================

@main
struct CherriHelperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var model = HelperModel.shared

    var body: some Scene {
        MenuBarExtra {
            HelperMenuView(model: model)
        } label: {
            // SF Symbols has no cherry, so this is drawn in code as a template shape that macOS tints like the other menu-bar icons.
            Image(nsImage: CherryIcon.menuBar)
        }
        .menuBarExtraStyle(.window)
    }
}

// The server has to run from launch, not from the first time the menu opens.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only readable while the launch event is being handled, so it is checked before the Task below.
        let atLogin = Self.launchedAsLoginItem
        Task { @MainActor in _ = UpdateController.shared }
        Task { @MainActor in
            let model = HelperModel.shared
            model.start()
            // The welcome pages show until setup is done. After that, launching is silent: the pairing stays saved, so there is nothing to ask.
            if model.shouldShowWelcome && !atLogin { WelcomeWindow.show() }
        }
    }

    // Opening the app again from Applications while it is already running lands here.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Opening the app again while it runs is how someone asks "where did it go?", so it always answers with a window.
        Task { @MainActor in
            if HelperModel.shared.shouldShowWelcome { WelcomeWindow.show() } else { SettingsWindow.show() }
        }
        return true
    }

    private static var launchedAsLoginItem: Bool {
        NSAppleEventManager.shared().currentAppleEvent?
            .paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?
            .enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }
}


// ===================================
// MENU VIEW
// ===================================

struct HelperMenuView: View {
    @ObservedObject var model: HelperModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cherri Helper").font(.headline)
            Text(model.status).font(.caption).foregroundStyle(.secondary)
            Divider()

            Button("Pair an iPhone…") { PairingWindow.show() }
            Button("Settings…") { SettingsWindow.show() }
                .keyboardShortcut(",")
            Button("Help…") { HelpLinks.open() }

            Divider()
            Button("Quit Cherri Helper") { NSApplication.shared.terminate(nil) }
        }
        .padding(14)
        .frame(width: 260)
    }
}

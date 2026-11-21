// ===================================
// Cherri Helper
// v0.0.9 BUILD 2026-11-21@12:21
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
        Task { @MainActor in
            HelperModel.shared.start()
            // A menu-bar-only app shows nothing on launch, so open the pairing window unless the Mac just started it at login.
            if !atLogin { PairingWindow.show() }
        }
    }

    // Opening the app again from Applications while it is already running lands here.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in PairingWindow.show() }
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

            Divider()
            Button("Quit Cherri Helper") { NSApplication.shared.terminate(nil) }
        }
        .padding(14)
        .frame(width: 260)
    }
}

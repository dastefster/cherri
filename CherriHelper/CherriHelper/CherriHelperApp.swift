// ===================================
// Cherri Helper
// v0.0.12 BUILD 2026-11-21@16:30
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

    // Runs before any window or menu-bar icon exists, so a duplicate leaves without ever flashing a second cherry.
    init() {
        // A copy that is still shutting down (a quick quit and reopen, or an update relaunch) gets a moment to finish before this one gives up.
        for _ in 0..<6 {
            if !Self.anotherCopyIsAlreadyRunning { return }
            Thread.sleep(forTimeInterval: 0.25)
        }
        exit(0)
    }

    // Two copies can run when one is launched from the DMG window or a build folder while the installed one is up.
    // The newer one steps aside, so two copies that start at the same moment can't both quit.
    private static var anotherCopyIsAlreadyRunning: Bool {
        guard let id = Bundle.main.bundleIdentifier else { return false }
        let me = NSRunningApplication.current
        let myStart = me.launchDate ?? Date()
        return NSRunningApplication.runningApplications(withBundleIdentifier: id).contains { other in
            guard other.processIdentifier != me.processIdentifier else { return false }
            let theirStart = other.launchDate ?? .distantPast
            return theirStart < myStart || (theirStart == myStart && other.processIdentifier < me.processIdentifier)
        }
    }

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

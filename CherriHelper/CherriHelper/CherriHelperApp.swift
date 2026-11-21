// ===================================
// Cherri Helper
// v0.0.8 BUILD 2026-11-21@12:02
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
// MODEL
// ===================================

@MainActor
final class HelperModel: ObservableObject {
    static let shared = HelperModel()

    @Published private(set) var status = "Starting up…"
    @Published private(set) var pairingURL = ""
    @Published var showQR = false
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled

    let serviceName: String
    private let store = PairingStore()
    private let server = HelperServer()

    private init() {
        serviceName = "Cherri Helper (\(Host.current().localizedName ?? "Mac"))"
        server.onStatus = { [weak self] text in
            Task { @MainActor in self?.status = text }
        }
        server.onReady = { [weak self] port in
            Task { @MainActor in self?.portReady(port) }
        }
    }

    func start() {
        server.start(secret: store.secret, serviceName: serviceName)
    }

    // The pairing link needs the port the server actually got, so it is built once the server is listening.
    private func portReady(_ port: Int) {
        let host = ProcessInfo.processInfo.hostName
        pairingURL = store.pairingURL(serviceName: serviceName, host: host.hasSuffix(".local") ? host : nil, port: port)
    }

    func resetPairing() {
        store.regenerate()
        showQR = false
        start()
    }

    func confirmAndResetPairing() {
        let alert = NSAlert()
        alert.messageText = "Reset pairing?"
        alert.informativeText = "Every paired iPhone will stop working until it scans the new code."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { resetPairing() }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            Log.write("login item change failed: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
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

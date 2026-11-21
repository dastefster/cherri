// ===================================
// Helper Model
// v0.0.1 BUILD 2026-11-21@12:21
// The helper's shared state: server status, pairing link, and start-at-login.
// dev by @dastefster 🍒🔨
// ===================================

import SwiftUI
import ServiceManagement


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

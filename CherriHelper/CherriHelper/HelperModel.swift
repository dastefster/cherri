// ===================================
// Helper Model
// v0.0.2 BUILD 2026-11-21@15:45
// The helper's shared state: server status, pairing link, first-run and paired flags, and start-at-login.
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

    private enum Key {
        static let welcomeDone = "hasCompletedWelcome"
        static let everPaired = "hasEverPaired"
    }

    @Published private(set) var status = "Starting up…"
    @Published private(set) var pairingURL = ""
    @Published var showQR = false
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var lastPhoneContact: Date?
    @Published private(set) var hasEverPaired: Bool

    let serviceName: String
    private let store = PairingStore()
    private let server = HelperServer()
    private let defaults = UserDefaults.standard

    private init() {
        serviceName = "Cherri Helper (\(Host.current().localizedName ?? "Mac"))"
        hasEverPaired = UserDefaults.standard.bool(forKey: Key.everPaired)

        // A Mac that already had a pairing key before the welcome screen existed has been through setup, so an update never greets it like a stranger.
        if !store.isNew, defaults.object(forKey: Key.welcomeDone) == nil {
            defaults.set(true, forKey: Key.welcomeDone)
        }

        server.onStatus = { [weak self] text in
            Task { @MainActor in self?.status = text }
        }
        server.onReady = { [weak self] port in
            Task { @MainActor in self?.portReady(port) }
        }
        server.onPhoneConnected = { [weak self] in
            Task { @MainActor in self?.phoneConnected() }
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


    // ===================================
    // WELCOME AND PAIRING STATE
    // ===================================

    var welcomeCompleted: Bool { defaults.bool(forKey: Key.welcomeDone) }

    // Shown until setup is finished, but never once an iPhone has connected: after that the job is done and the app can stay quiet.
    var shouldShowWelcome: Bool { !welcomeCompleted && !hasEverPaired }

    func completeWelcome() {
        defaults.set(true, forKey: Key.welcomeDone)
    }

    // Called when an iPhone completes the encrypted handshake, which only a phone holding the pairing key can do.
    private func phoneConnected() {
        lastPhoneContact = Date()
        if !hasEverPaired {
            hasEverPaired = true
            defaults.set(true, forKey: Key.everPaired)
            Log.write("first iPhone connected")
        }
    }

    func resetPairing() {
        store.regenerate()
        showQR = false
        hasEverPaired = false
        lastPhoneContact = nil
        defaults.set(false, forKey: Key.everPaired)
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

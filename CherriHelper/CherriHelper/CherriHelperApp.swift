// ===================================
// Cherri Helper
// v0.0.1 BUILD 2026-11-21@10:00
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
        MenuBarExtra("Cherri Helper", systemImage: "signature") {
            HelperMenuView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

// The server has to run from launch, not from the first time the menu opens.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in HelperModel.shared.start() }
    }
}


// ===================================
// MODEL
// ===================================

@MainActor
final class HelperModel: ObservableObject {
    static let shared = HelperModel()

    @Published private(set) var status = "Starting…"
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
    }

    func start() {
        pairingURL = store.pairingURL(serviceName: serviceName)
        server.start(secret: store.secret, serviceName: serviceName)
    }

    func resetPairing() {
        store.regenerate()
        showQR = false
        start()
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

            Button(model.showQR ? "Hide pairing QR" : "Pair an iPhone…") { model.showQR.toggle() }

            if model.showQR {
                if let image = QRCode.image(for: model.pairingURL) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: 220, height: 220)
                }
                Text("In Cherri Shortcuts, open Settings → Signing → My Mac, then scan this code.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Reset pairing…") { confirmReset() }

            Toggle("Start at login", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))

            Divider()
            Button("Quit Cherri Helper") { NSApplication.shared.terminate(nil) }
        }
        .padding(14)
        .frame(width: 260)
    }

    private func confirmReset() {
        let alert = NSAlert()
        alert.messageText = "Reset pairing?"
        alert.informativeText = "Every paired iPhone will stop working until it scans the new code."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { model.resetPairing() }
    }
}

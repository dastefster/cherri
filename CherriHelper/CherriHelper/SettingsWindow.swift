// ===================================
// Settings Window
// v0.0.2 BUILD 2026-11-21@12:01
// The Settings window for Cherri Helper: start at login, pairing, and support tools.
// dev by @dastefster 🍒🔨
// ===================================

import SwiftUI


// ===================================
// WINDOW
// ===================================

@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let created = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: HelperModel.shared)))
            created.title = "Cherri Helper Settings"
            created.styleMask = [.titled, .closable]
            created.isReleasedWhenClosed = false
            created.center()
            window = created
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}


// ===================================
// CONTENT
// ===================================

struct SettingsView: View {
    @ObservedObject var model: HelperModel

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    var body: some View {
        Form {
            Section("General") {
                Toggle("Start Cherri Helper when I log in", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
            }

            Section("Pairing") {
                Button("Show Pairing QR Code…") { PairingWindow.show() }
                Button("Copy Pairing Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.pairingURL, forType: .string)
                }
                Button("Reset Pairing…") { model.confirmAndResetPairing() }
                Text("Resetting makes every paired iPhone scan a new code before it can sign again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Support") {
                Button("Report a Problem…") {
                    ReportProblem.open(status: model.status, launchAtLogin: model.launchAtLogin)
                }
                Text("Opens an email to support with your Mac's basic info and the helper's log. You can read and edit it before sending. The log only records sizes, times and results, never your shortcuts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Version", value: version)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 460)
    }
}

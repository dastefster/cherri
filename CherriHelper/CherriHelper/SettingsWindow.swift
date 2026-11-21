// ===================================
// Settings Window
// v0.0.4 BUILD 2026-11-21@12:21
// The Settings window for Cherri Helper: icon tabs across the top, each one sized to fit so nothing ever needs scrolling.
// dev by @dastefster 🍒🔨
// ===================================

import SwiftUI


// ===================================
// WINDOW
// ===================================

@MainActor
enum SettingsWindow {
    private(set) static var window: NSWindow?

    static func show() {
        if window == nil {
            let tabs = NSTabViewController()
            tabs.tabStyle = .toolbar
            tabs.addTabViewItem(pane("General", symbol: "gearshape", GeneralPane(model: HelperModel.shared)))
            tabs.addTabViewItem(pane("Pairing", symbol: "qrcode", PairingPane(model: HelperModel.shared)))
            tabs.addTabViewItem(pane("Support", symbol: "lifepreserver", SupportPane(model: HelperModel.shared)))

            let created = NSWindow(contentViewController: tabs)
            created.styleMask = [.titled, .closable]
            created.isReleasedWhenClosed = false
            created.center()
            window = created
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // Each pane reports its own size to the window, so the window grows or shrinks to fit the tab you pick.
    private static func pane<V: View>(_ title: String, symbol: String, _ view: V) -> NSTabViewItem {
        let host = NSHostingController(rootView: view)
        host.sizingOptions = [.preferredContentSize]
        let item = NSTabViewItem(viewController: host)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }
}


// ===================================
// LAYOUT PIECES
// ===================================

// Label on the left, controls on the right, like the settings in Amphetamine and Onyx.
private struct Row<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(label)
                .frame(width: 110, alignment: .trailing)
            VStack(alignment: .leading, spacing: 8) { content }
            Spacer(minLength: 0)
        }
    }
}

private struct Note: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct PaneFrame<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 20) { content }
            .padding(24)
            .frame(width: 520)
            .fixedSize(horizontal: false, vertical: true)
    }
}


// ===================================
// PANES
// ===================================

struct GeneralPane: View {
    @ObservedObject var model: HelperModel

    var body: some View {
        PaneFrame {
            Row(label: "Startup") {
                Toggle("Start Cherri Helper when I log in", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                Note(text: "Cherri Helper has to be running for your iPhone to sign shortcuts. It lives in the menu bar and uses very little.")
            }
        }
    }
}

struct PairingPane: View {
    @ObservedObject var model: HelperModel

    var body: some View {
        PaneFrame {
            Row(label: "Pair an iPhone") {
                Button("Show Pairing QR Code…") { PairingWindow.show() }
                Note(text: "In Cherri Shortcuts, open Settings → Signing → My Mac and tap Scan QR Code.")
            }
            Row(label: "Pairing link") {
                Button("Copy Pairing Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.pairingURL, forType: .string)
                }
                Note(text: "For when scanning isn't possible. Paste it into Cherri Shortcuts instead.")
            }
            Row(label: "Reset") {
                Button("Reset Pairing…") { model.confirmAndResetPairing() }
                Note(text: "Every paired iPhone has to scan a new code before it can sign again.")
            }
        }
    }
}

struct SupportPane: View {
    @ObservedObject var model: HelperModel
    @State private var copied = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (build \(build))"
    }

    var body: some View {
        PaneFrame {
            Row(label: "Get help") {
                HStack {
                    Button("Report a Problem…") {
                        ReportProblem.open(status: model.status, launchAtLogin: model.launchAtLogin)
                    }
                    Button(copied ? "Copied ✓" : "Copy Report Instead") {
                        ReportProblem.copyReport(status: model.status, launchAtLogin: model.launchAtLogin)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                    }
                }
                Note(text: "Report a Problem opens an email to support with your Mac's basic info and the helper's log. You can read and edit it before sending.")
                Note(text: "No mail account set up? Use Copy Report Instead, paste it into an email to \(ReportProblem.supportEmail), and attach the log file that opens in Finder.")
                Note(text: "The log only records sizes, times and results, never your shortcuts.")
            }
            Row(label: "Version") {
                Text(version)
            }
        }
    }
}

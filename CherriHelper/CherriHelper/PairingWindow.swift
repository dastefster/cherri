// ===================================
// Pairing Window
// v0.0.2 BUILD 2026-11-21@15:45
// The compact QR window behind Pair an iPhone, for pairing another phone or re-pairing later. First-run setup lives in the welcome screen.
// dev by @dastefster 🍒🔨
// ===================================

import SwiftUI


// ===================================
// WINDOW
// ===================================

@MainActor
enum PairingWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let created = NSWindow(contentViewController: NSHostingController(rootView: PairingWindowView(model: HelperModel.shared)))
            created.title = "Cherri Helper"
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

struct PairingWindowView: View {
    @ObservedObject var model: HelperModel

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)

            Text("Pair your iPhone")
                .font(.title2.bold())

            Text("In Cherri Shortcuts, open Settings → Signing → My Mac, tap Scan QR Code, and point your iPhone at this.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let image = QRCode.image(for: model.pairingURL) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 220, height: 220)
            } else {
                ProgressView().frame(width: 220, height: 220)
            }

            Text(model.status)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Toggle("Start Cherri Helper when I log in", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))

            Text("Cherri Helper lives in your menu bar (🍒). Click it any time. Open Cherri Helper from your Applications folder again to see Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 340)
    }
}

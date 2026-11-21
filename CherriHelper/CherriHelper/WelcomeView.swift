// ===================================
// Welcome View
// v0.0.2 BUILD 2026-11-21@15:50
// The four welcome pages: what the helper does, what it needs, pairing with a live "connected" check, and the start-at-login choice.
// dev by @dastefster 🍒🔨
// ===================================

import SwiftUI


// ===================================
// CONSTANTS
// ===================================

let welcomeLastPage = 3


// ===================================
// VIEW
// ===================================

// Pure view: everything it shows comes in as plain values, so it can be rendered on its own for previews.
struct WelcomeView: View {
    @Binding var page: Int
    @Binding var startAtLogin: Bool
    let pairingURL: String
    let status: String
    let paired: Bool
    var icon: NSImage = NSApp.applicationIconImage
    let onOpenHelp: () -> Void
    let onDone: () -> Void

    private let cherry = Color(red: 0.80, green: 0.10, blue: 0.25)

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                Group {
                    switch page {
                    case 0: intro
                    case 1: needs
                    case 2: pair
                    default: finished
                    }
                }
                .id(page)
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                footer
            }
        }
        .frame(width: 600, height: 560)
        .withoutFocusRing()
        .animation(.easeInOut(duration: 0.25), value: page)
    }


    // ===================================
    // BACKGROUND
    // ===================================

    private var background: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(colors: [cherry.opacity(0.20), cherry.opacity(0)], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.55))
        }
        .ignoresSafeArea()
    }


    // ===================================
    // PAGES
    // ===================================

    private var intro: some View {
        VStack(spacing: 16) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 120, height: 120)
                .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
            Text("Welcome to Cherri Helper")
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text("Sign your Cherri Shortcuts exports right here on your Mac.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 18) {
                feature("lock.shield.fill", "Private by design", "Your shortcut goes from your iPhone to this Mac. It never passes through anyone else's server.")
                feature("menubar.rectangle", "Quiet in your menu bar", "No Dock icon and no windows in your way.")
                feature("bolt.fill", "Quick", "Signing takes a few seconds.")
            }
            .padding(.top, 10)
        }
        .padding(.horizontal, 60)
        .padding(.top, 36)
    }

    private var needs: some View {
        VStack(spacing: 14) {
            header("Before you start", "Three quick things to check.")

            VStack(alignment: .leading, spacing: 22) {
                feature("icloud.fill", "This Mac is signed in to iCloud", "Apple's signing tool needs it, and it only works while this Mac is online.")
                feature("wifi", "Your iPhone and this Mac are on the same Wi-Fi", "Guest networks and some VPNs stop devices from finding each other.")
                feature("power", "Cherri Helper stays running", "It lives in the menu bar. If it isn't running, exports to this Mac can't go through. At the end we'll offer to start it at login.")
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 60)
        .padding(.top, 44)
    }

    private var pair: some View {
        VStack(spacing: 22) {
            header("Pair your iPhone", "This takes about ten seconds.")

            HStack(alignment: .center, spacing: 34) {
                qrCard
                VStack(alignment: .leading, spacing: 18) {
                    step(1, "Open Cherri Shortcuts on your iPhone.")
                    step(2, "Go to Settings → Signing and choose My Mac.")
                    step(3, "Tap Scan QR Code and point your camera at this code.")
                }
                .frame(width: 230, alignment: .leading)
            }

            HStack(spacing: 9) {
                if paired {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Connected! Your iPhone is paired.").fontWeight(.semibold)
                } else {
                    ProgressView().controlSize(.small)
                    Text(status.hasPrefix("Ready") ? "Waiting for your iPhone…" : status)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.thinMaterial, in: Capsule())
        }
        .padding(.top, 40)
    }

    private var finished: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 62))
                .foregroundStyle(.green)
            Text(paired ? "You're all set" : "Ready when you are")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text(paired
                 ? "Cherri Helper will sign your exports from now on."
                 : "You can pair your iPhone any time from the cherry in your menu bar.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Text("Look for")
                Image(nsImage: CherryIcon.menuBar)
                    .renderingMode(.template)
                    .foregroundStyle(.primary)
                Text("in your menu bar.")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .padding(.top, 4)

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Start Cherri Helper when I log in", isOn: $startAtLogin)
                    .toggleStyle(.switch)
                    .font(.headline)
                Text("Recommended. Your iPhone can only sign shortcuts while Cherri Helper is running, and this way it always is.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(width: 440, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(.top, 8)

            Button("Open Help…", action: onOpenHelp)
                .buttonStyle(.link)
                .withoutFocusRing()
                .padding(.top, 2)
        }
        .padding(.top, 40)
    }


    // ===================================
    // PIECES
    // ===================================

    private func header(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.system(size: 28, weight: .bold, design: .rounded))
            Text(subtitle).font(.title3).foregroundStyle(.secondary)
        }
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(cherry)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(cherry, in: Circle())
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var qrCard: some View {
        Group {
            if let image = QRCode.image(for: pairingURL) {
                Image(nsImage: image).resizable().interpolation(.none)
            } else {
                ProgressView()
            }
        }
        .frame(width: 190, height: 190)
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }

    private var footer: some View {
        HStack {
            Button("Back") { page -= 1 }
                .withoutFocusRing()
                .opacity(page == 0 ? 0 : 1)
                .disabled(page == 0)

            Spacer()
            HStack(spacing: 8) {
                ForEach(0...welcomeLastPage, id: \.self) { index in
                    Circle()
                        .fill(index == page ? cherry : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            Spacer()

            Button(primaryTitle) {
                if page < welcomeLastPage { page += 1 } else { onDone() }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .tint(cherry)
            .controlSize(.large)
            .withoutFocusRing()
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }

    private var primaryTitle: String {
        switch page {
        case 0: return "Get Started"
        case 1: return "Continue"
        case 2: return paired ? "Continue" : "Skip for Now"
        default: return "Done"
        }
    }
}


// ===================================
// FOCUS RING
// ===================================

private extension View {
    // With keyboard navigation on, macOS drew a blue ring around the default button that sat in the wrong place. A setup screen has no use for it.
    @ViewBuilder func withoutFocusRing() -> some View {
        if #available(macOS 14.0, *) {
            focusEffectDisabled()
        } else {
            focusable(false)
        }
    }
}

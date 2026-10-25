// ===================================
// Welcome Screen
// v0.0.3 BUILD 2026-10-25 08:00
// Shown on first launch (and from the ? button): what Cherri Shortcuts is, the Write, Compile, Export and Import flow, and the privacy facts testers should know before exporting or importing.
// dev by @dastefster 🍒🔨
// ===================================

import SwiftUI

// ===================================
// WELCOME VIEW
// ===================================

struct WelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                steps
                betaNotice
            }
            .padding(.horizontal, 24)
            .padding(.top, 48)
            .padding(.bottom, 24)
        }
        // Pinned so the button is always reachable without scrolling on small phones.
        .safeAreaInset(edge: .bottom) {
            Button(action: onContinue) {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }

    // ===================================
    // HEADER
    // ===================================

    private var header: some View {
        VStack(spacing: 10) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 132, height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            Text("Welcome to Cherri Shortcuts")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .padding(.top, 8)
            Text("Write Apple Shortcuts as code.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // ===================================
    // STEPS
    // ===================================

    private var steps: some View {
        VStack(alignment: .leading, spacing: 20) {
            step("chevron.left.forwardslash.chevron.right", "Write",
                 "Type Cherri code, or tap Actions to pick from the same actions you know from Shortcuts.")
            step("hammer", "Compile",
                 "Check your code. Errors show up right under the editor, with a button to copy the full message.")
            step("square.and.arrow.up", "Export",
                 "Sign your shortcut and choose the Shortcuts icon in the share sheet to add it to your library.")
            step("square.and.arrow.down", "Import",
                 "Turn a shortcut you already have into code. Copy its iCloud link and tap Import, or share it to Cherri Shortcuts from the Shortcuts app.")
        }
    }

    private func step(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // ===================================
    // BETA NOTICE
    // ===================================

    private var betaNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Beta notice", systemImage: "info.circle")
                .font(.headline)
            Text("This is an early beta, so expect rough edges. When you tap Export, your shortcut is sent to RoutineHub's HubSign service to be signed, because iOS only imports signed shortcuts. When you import, the iCloud link is looked up on iCloud to fetch that shortcut. Nothing is sent until you tap Export or start an import.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

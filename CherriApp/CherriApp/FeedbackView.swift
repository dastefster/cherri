// ===================================
// Feedback Menu
// v0.0.1 BUILD 2026-10-25 07:45
// The screen behind Settings → Send Feedback: one row for the Google Form and one for email, each with a colored icon tile like the rest of Settings.
// dev by @dastefster 🍒🔨
// ===================================

import SwiftUI

// ===================================
// FEEDBACK VIEW
// ===================================

struct FeedbackView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                // Buttons rather than Links, so the title keeps the normal text color instead of turning link blue.
                Button(action: { openURL(Feedback.url()) }) {
                    SettingsLabel(title: "Feedback Form", symbol: "list.bullet.clipboard.fill", color: .green)
                }
                Button(action: { openURL(Feedback.mailURL) }) {
                    SettingsLabel(title: "Email", symbol: "envelope.fill", color: .blue)
                }
            } footer: {
                Text("The form fills in your app version and iOS version for you. Email opens a new message in Mail.")
            }
        }
        .foregroundStyle(.primary)
        .navigationTitle("Send Feedback")
        .navigationBarTitleDisplayMode(.inline)
    }
}

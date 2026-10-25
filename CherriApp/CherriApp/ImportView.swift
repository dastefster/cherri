// ===================================
// Import View
// v0.0.1 BUILD 2026-10-25 04:55
// The Import sheet: paste a Shortcuts iCloud link (with Apple's no-prompt Paste button), import it into the editor, and reach support if the shortcut can't be read.
// dev by @dastefster 🍒🔨
// ===================================

import SwiftUI
import UIKit

// ===================================
// IMPORT SHEET
// ===================================

struct ImportView: View {
    let onImported: (ShortcutImporter.Imported) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var clipboardMayHaveLink = false
    @State private var working = false
    @State private var failure: ShortcutImporter.Failure?

    // ===================================
    // BODY
    // ===================================

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("In the Shortcuts app, open a shortcut's share menu and tap Copy iCloud Link. Then come back here and tap Paste.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("iCloud link") {
                    TextField("https://www.icloud.com/shortcuts/…", text: $link)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .submitLabel(.go)
                        .onSubmit { startImport() }

                    // Apple's own Paste button reads the clipboard without the "Allow Paste" prompt a plain read would trigger.
                    PasteButton(payloadType: String.self) { strings in
                        guard let pasted = strings.first else { return }
                        link = pasted
                        if ShortcutImporter.extractLink(from: pasted) != nil { startImport() }
                    }
                    .buttonBorderShape(.capsule)
                    .tint(clipboardMayHaveLink ? .accentColor : .gray)

                    if clipboardMayHaveLink {
                        Label("There's a link on your clipboard. Tap Paste to use it.", systemImage: "doc.on.clipboard")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button(action: startImport) {
                        HStack {
                            Text(working ? "Importing…" : "Import")
                            if working { ProgressView() }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(working || link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let failure {
                    failureSection(failure)
                }
            }
            .navigationTitle("Import Shortcut")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear(perform: checkClipboard)
        }
    }

    // ===================================
    // FAILURE
    // ===================================

    @ViewBuilder
    private func failureSection(_ failure: ShortcutImporter.Failure) -> some View {
        Section {
            Text(failure.headline)
                .font(.footnote)
                .foregroundStyle(.red)

            if failure.offersSupport {
                // The form is pre-filled with the error and the link so the shortcut can be reproduced; the person sees it all before sending.
                Link(destination: Feedback.url(error: failure.details)) {
                    Label("Contact support about this shortcut", systemImage: "text.bubble")
                }
                Text("This opens the feedback form with the error and your shortcut's link filled in, so you can review it before sending.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link(destination: Feedback.mailURL) {
                    Label("Email instead", systemImage: "envelope")
                }
                .font(.footnote)
            }
        }
    }

    // ===================================
    // ACTIONS
    // ===================================

    // Asks iOS what kind of text is on the clipboard without reading it, so there is no paste prompt. It can only say "looks like a web link", not which one.
    private func checkClipboard() {
        UIPasteboard.general.detectPatterns(for: [.probableWebURL]) { result in
            if case .success(let patterns) = result {
                DispatchQueue.main.async { clipboardMayHaveLink = patterns.contains(.probableWebURL) }
            }
        }
    }

    private func startImport() {
        guard !working else { return }
        working = true
        failure = nil

        Task {
            do {
                let imported = try await ShortcutImporter.importShortcut(from: link)
                working = false
                onImported(imported)
            } catch let error as ShortcutImporter.Failure {
                failure = error
                working = false
            } catch {
                failure = ShortcutImporter.Failure(headline: error.localizedDescription, details: error.localizedDescription, offersSupport: true)
                working = false
            }
        }
    }
}

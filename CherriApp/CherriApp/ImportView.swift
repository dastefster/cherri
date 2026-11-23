// ===================================
// Import View
// v0.0.8 BUILD 2026-11-23 08:20
// The Import sheet, and the one home for the whole import: paste a Shortcuts iCloud link (with Apple's no-prompt Paste button) or arrive here from the Share extension with the link already filled in, download the shortcut (or pick one of the last 10 from Recent, which opens without downloading), then choose what to do with it (import it as code, or copy actions). Errors, with the contact-support button, stay in this sheet. It only closes once a choice is made.
// dev by @dastefster 🍒🔨
// ===================================

import SwiftUI
import UIKit

// ===================================
// IMPORT SHEET
// ===================================

struct ImportView: View {
    // A link the Share extension handed over. When set, the sheet fills it in and downloads it as soon as it opens.
    var initialLink: String? = nil
    // The person chose to import as code; the screen behind this sheet loads it into the editor.
    let onImported: (ShortcutImporter.Imported) -> Void
    // The person chose to copy actions; the screen behind this sheet opens the action list.
    let onCopyActions: (ShortcutImporter.Fetched) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var link = ""
    @State private var clipboardMayHaveLink = false
    @State private var working = false
    // Shown while a freshly shared shortcut isn't published by iCloud yet and the download is being retried.
    @State private var waitNote: String?
    // Set once the download succeeds; the sheet then asks what to do with it.
    @State private var fetched: ShortcutImporter.Fetched?
    @State private var decompiling = false
    @State private var failure: ShortcutImporter.Failure?
    @StateObject private var recent = RecentShortcutsStore()
    // Set when the shortcut on screen is a saved copy, so the sheet can say so and offer a fresh download.
    @State private var savedCopyDate: Date?

    // ===================================
    // BODY
    // ===================================

    var body: some View {
        NavigationStack {
            Form {
                if let fetched {
                    choiceSections(fetched)
                } else {
                    linkSections
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
            // Coming back from the Shortcuts app after copying a link is the normal path, so look again then.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { checkClipboard() }
            }
            // A shared shortcut starts downloading the moment the sheet opens.
            .task {
                guard let initialLink, fetched == nil, link.isEmpty else { return }
                link = initialLink
                await fetch(retryMissing: true)
            }
        }
    }

    // ===================================
    // LINK
    // ===================================

    @ViewBuilder
    private var linkSections: some View {
        Section {
            Text("In the Shortcuts app, open a shortcut's share menu and tap Copy iCloud Link. Then come back here and tap Paste.")
                .font(.footnote)
                .foregroundStyle(Color.helperText)
        }

        Section {
            TextField("", text: $link, prompt: Text("https://www.icloud.com/shortcuts/…").foregroundStyle(Color.primary.opacity(0.45)))
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
            // Never gray: the clipboard check can fail (iOS sometimes says the pasteboard is unavailable) while the button itself still works.
            .tint(.accentColor)

            if clipboardMayHaveLink {
                Label("There's a link on your clipboard. Tap Paste to use it.", systemImage: "doc.on.clipboard")
                    .font(.footnote)
                    .foregroundStyle(Color.helperText)
            }

            if let waitNote {
                Label(waitNote, systemImage: "hourglass")
                    .font(.footnote)
                    .foregroundStyle(Color.helperText)
            }
        } header: {
            Text("iCloud link")
                .foregroundStyle(Color.helperText)
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

        recentSection
    }

    // ===================================
    // RECENT
    // ===================================

    // The last few downloads, kept on this device. Tapping one skips the download.
    @ViewBuilder
    private var recentSection: some View {
        if !recent.entries.isEmpty {
            Section {
                ForEach(recent.entries) { entry in
                    Button { openRecent(entry) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name)
                                .foregroundStyle(.primary)
                            Text(entry.savedAt.formatted(.relative(presentation: .named, unitsStyle: .wide)))
                                .font(.caption)
                                .foregroundStyle(Color.helperText)
                        }
                    }
                }
                .onDelete { recent.remove(at: $0) }

                Button("Clear Recent", role: .destructive) { recent.clearAll() }
            } header: {
                Text("Recent")
                    .foregroundStyle(Color.helperText)
            } footer: {
                Text("Saved on this device only. Swipe to remove one, or turn this off in Settings.")
                    .foregroundStyle(Color.helperText)
            }
        }
    }

    // Opens a saved copy without touching the network. A copy that can't be read is dropped from the list.
    private func openRecent(_ entry: RecentShortcut) {
        guard let saved = recent.fetched(for: entry) else {
            failure = ShortcutImporter.Failure(
                headline: "That saved copy couldn't be read, so it was removed. Paste its link again to download it.",
                details: "Saved copy unreadable",
                offersSupport: false
            )
            return
        }
        failure = nil
        link = saved.link
        fetched = saved
        savedCopyDate = entry.savedAt
    }

    // ===================================
    // CHOICE
    // ===================================

    // The fork in the road. Nothing leaves this sheet until one of the two is picked.
    @ViewBuilder
    private func choiceSections(_ fetched: ShortcutImporter.Fetched) -> some View {
        Section {
            Text(fetched.name)
                .font(.headline)
            Text(savedCopyDate.map { "Saved copy from \($0.formatted(date: .abbreviated, time: .shortened)). What do you want to do with it?" } ?? "Downloaded. What do you want to do with it?")
                .font(.footnote)
                .foregroundStyle(Color.helperText)
        }

        Section {
            Button { chooseCode(fetched) } label: {
                choiceLabel(
                    title: decompiling ? "Importing…" : "Import into Editor",
                    detail: "Turn it into Cherri code in the editor.",
                    symbol: "curlybraces",
                    busy: decompiling
                )
            }
            .disabled(decompiling)

            Button { onCopyActions(fetched) } label: {
                choiceLabel(
                    title: "Copy Actions",
                    detail: "Pick actions to copy and paste into another shortcut.",
                    symbol: "doc.on.doc",
                    busy: false
                )
            }
            .disabled(decompiling)
        }

        Section {
            // A saved copy is a snapshot. If the author has changed the shortcut since, this gets the current one.
            if savedCopyDate != nil {
                Button { Task { await fetch(retryMissing: false) } } label: {
                    choiceLabel(
                        title: working ? "Downloading…" : "Download a Fresh Copy",
                        detail: "Get the shortcut's current version from iCloud.",
                        symbol: "arrow.clockwise",
                        busy: working
                    )
                }
                .disabled(working || decompiling)
            }

            Button {
                self.fetched = nil
                savedCopyDate = nil
                failure = nil
                link = ""
            } label: {
                choiceLabel(
                    title: "Use a Different Link",
                    detail: "Start over with another shortcut.",
                    symbol: "link.badge.plus",
                    busy: false
                )
            }
            .disabled(decompiling)
        }
    }

    private func choiceLabel(title: String, detail: String, symbol: String, busy: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.helperText)
            }
            Spacer()
            if busy { ProgressView() }
        }
        .padding(.vertical, 4)
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
                    .foregroundStyle(Color.helperText)
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
        Task { await fetch(retryMissing: false) }
    }

    // Downloads the shortcut. A link shared a moment ago may not be published by iCloud yet, so for a shared link "not found" is retried for a few seconds before it is reported.
    private func fetch(retryMissing: Bool) async {
        guard !working else { return }
        working = true
        failure = nil
        waitNote = nil

        let attempts = retryMissing ? 6 : 1
        for attempt in 1...attempts {
            do {
                let downloaded = try await ShortcutImporter.fetchShortcut(from: link)
                fetched = downloaded
                savedCopyDate = nil
                recent.remember(downloaded)
                break
            } catch let error as ShortcutImporter.Failure {
                if error.isMissing && attempt < attempts {
                    waitNote = "Waiting for iCloud to publish the shared shortcut… (\(attempt)/\(attempts - 1))"
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    continue
                }
                failure = error
                break
            } catch {
                failure = ShortcutImporter.Failure(headline: error.localizedDescription, details: error.localizedDescription, offersSupport: true)
                break
            }
        }

        waitNote = nil
        working = false
    }

    // Decompiling happens here, after the choice, so a shortcut the decompiler can't read can still have its actions copied. If it fails, the error and the support button show in this sheet and the other choice stays available.
    private func chooseCode(_ fetched: ShortcutImporter.Fetched) {
        guard !decompiling else { return }
        decompiling = true
        failure = nil

        Task {
            do {
                let imported = try await ShortcutImporter.decompile(fetched)
                decompiling = false
                onImported(imported)
            } catch let error as ShortcutImporter.Failure {
                failure = error
                decompiling = false
            } catch {
                failure = ShortcutImporter.Failure(headline: error.localizedDescription, details: error.localizedDescription, offersSupport: true)
                decompiling = false
            }
        }
    }
}

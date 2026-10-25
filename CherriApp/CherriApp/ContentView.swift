// ===================================
// Cherri App Main Screen
// v0.0.25 BUILD 2026-10-25 05:05
// Type Cherri code (saved between launches), insert actions and values at the cursor from the picker, compile it with the embedded compiler, or export it: sign via HubSign and open the share sheet to import into Shortcuts. Import pulls an existing shortcut in from an iCloud link and turns it back into Cherri code.
// dev by @dastefster 🍒🔨
// ===================================

import SwiftUI
import UIKit
import Cherri

// ===================================
// MAIN VIEW
// ===================================

struct ContentView: View {
    // Kept in UserDefaults so closing the app never loses work. A file will replace this if scripts get large.
    @AppStorage("cherriSource") private var source = StarterCode.text
    @State private var status = "Cherri \(CherriCompilerVersion())"
    @State private var failed = false
    @State private var showDetails = false
    @State private var copied = false
    @State private var working = false
    @State private var exportFile: ExportFile?
    @State private var showingActions = false
    @State private var editor = EditorController()
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var showingWelcome = false
    @State private var showingGuide = false
    @State private var showingSettings = false
    @State private var showingClearConfirm = false
    @State private var showingImport = false
    // An import waits here while the replace-your-code question is on screen.
    @State private var pendingImport: ShortcutImporter.Imported?
    @State private var showingImportReplaceConfirm = false
    @AppStorage(ExportSettings.confirmKey) private var confirmBeforeExport = true
    @State private var confirmingExport = false
    @AppStorage(ExportSettings.tipKey) private var showShareTip = true
    // The signed file waits here while the tip is on screen, then moves to exportFile to open the share sheet.
    @State private var pendingExport: ExportFile?
    @State private var showingShareTip = false
    @AppStorage(EditorSettings.fontKey) private var fontID = EditorSettings.systemFontID
    @AppStorage(EditorSettings.sizeKey) private var fontSize = EditorSettings.defaultSize
    @AppStorage(EditorSettings.lightKey) private var lightThemeID = EditorSettings.defaultLightThemeID
    @AppStorage(EditorSettings.darkKey) private var darkThemeID = EditorSettings.defaultDarkThemeID
    @AppStorage(PremiumStore.unlockedKey) private var isPremium = false
    @Environment(\.colorScheme) private var colorScheme

    // ===================================
    // BODY
    // ===================================

    // The welcome screen replaces the whole view on first launch. Presenting it as a cover from onAppear flashed the editor for a frame first.
    var body: some View {
        Group {
            if hasSeenWelcome {
                mainView
            } else {
                WelcomeView { hasSeenWelcome = true }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: hasSeenWelcome)
    }

    // ===================================
    // MAIN VIEW
    // ===================================

    private var mainView: some View {
        NavigationStack {
            mainContent
                .navigationTitle("Cherri Shortcuts")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: {
                            editor.textView?.resignFirstResponder()
                            showingSettings = true
                        }) {
                            Image(systemName: "gearshape")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 16) {
                            Button(action: {
                                editor.textView?.resignFirstResponder()
                                showingClearConfirm = true
                            }) {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            
                            Button(action: {
                                editor.textView?.resignFirstResponder()
                                showingGuide = true
                            }) {
                                Image(systemName: "questionmark.circle")
                            }
                        }
                    }
                }
                // Pushed, not a sheet: a sheet and a fullScreenCover on the same view conflict and the sheet never opened.
                .navigationDestination(isPresented: $showingGuide) {
                    GuideView(onShowWelcome: { showingWelcome = true })
                }
                .navigationDestination(isPresented: $showingSettings) {
                    SettingsView(onShowWelcome: { showingWelcome = true })
                }
        }
        .fullScreenCover(isPresented: $showingWelcome) {
            WelcomeView { showingWelcome = false }
        }
    }

    // ===================================
    // MAIN CONTENT
    // ===================================

    private var editorStyle: EditorStyle {
        EditorSettings.style(fontID: fontID, size: fontSize, lightID: lightThemeID, darkID: darkThemeID, dark: colorScheme == .dark, premium: isPremium)
    }

    private var mainContent: some View {
        VStack(spacing: 12) {
            CodeEditor(text: $source, controller: editor, style: editorStyle)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 12) {
                Button(action: {
                    // Drop the keyboard first so the first tap opens the picker instead of fighting the text view for focus.
                    editor.textView?.resignFirstResponder()
                    showingActions = true
                }) {
                    Text("Actions")
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: compile) {
                    Text("Compile")
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(action: {
                    if confirmBeforeExport { confirmingExport = true } else { exportToShortcuts() }
                }) {
                    Text("Export")
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: {
                    editor.textView?.resignFirstResponder()
                    showingImport = true
                }) {
                    Text("Import")
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .disabled(working)
            .sheet(isPresented: $showingImport) {
                ImportView(onImported: handleImported)
            }
            .sheet(isPresented: $showingActions) {
                ActionPickerView(
                    source: source,
                    onInsert: { editor.insertStatement($0) },
                    onInsertValue: { editor.insertInline($0) }
                )
            }

            Text("Export sends your shortcut to RoutineHub's HubSign service to be signed.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            statusArea
        }
        .padding()
        .sheet(item: $exportFile) { file in
            ShareSheet(url: file.url)
        }
        .alert("Export Shortcut?", isPresented: $confirmingExport) {
            Button("Export") { exportToShortcuts() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your shortcut will be sent to RoutineHub's HubSign service to be signed. You can turn this prompt off in Settings.")
        }
        .alert("Add It to Shortcuts", isPresented: $showingShareTip) {
            Button("Continue") {
                let file = pendingExport
                pendingExport = nil
                // Presenting a sheet in the same moment an alert is dismissing can be dropped, so give the alert a beat to leave.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { exportFile = file }
            }
        } message: {
            Text("Your shortcut is signed. On the next screen, tap Shortcuts in the row of apps (swipe the row if you don't see it), then tap Add Shortcut.")
        }
        .alert("Replace Your Code?", isPresented: $showingImportReplaceConfirm) {
            Button("Replace", role: .destructive) {
                if let imported = pendingImport { applyImport(imported) }
                pendingImport = nil
            }
            Button("Cancel", role: .cancel) { pendingImport = nil }
        } message: {
            Text("Importing \"\(pendingImport?.name ?? "this shortcut")\" will replace everything in the editor.")
        }
        .alert("Clear Editor?", isPresented: $showingClearConfirm) {
            Button("Clear", role: .destructive) {
                source = ""
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all current Cherri code in the editor.")
        }
    }

    // ===================================
    // STATUS AREA
    // ===================================

    // The compiler prints warnings (with long doc blocks) before the real error, so the useful line is the last "Error:" line.
    private var headline: String {
        let lines = status.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        return lines.last(where: { $0.hasPrefix("Error:") }) ?? lines.last ?? status
    }

    private var hasDetails: Bool {
        status.contains("\n")
    }

    @ViewBuilder
    private var statusArea: some View {
        if failed {
            VStack(alignment: .leading, spacing: 8) {
                Text(headline)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Color.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                HStack(spacing: 20) {
                    Button(copied ? "Copied" : "Copy full message") {
                        UIPasteboard.general.string = status
                        copied = true
                    }

                    if hasDetails {
                        Button(showDetails ? "Hide details" : "Show details") {
                            showDetails.toggle()
                        }
                    }
                }
                .font(.footnote)

                Link("Send Feedback about this error", destination: Feedback.url(error: headline))
                    .font(.footnote)

                if showDetails {
                    ScrollView {
                        Text(status)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(Color.red.opacity(0.7))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 140)
                }
            }
        } else {
            ScrollView {
                Text(status)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 140)
        }
    }

    // ===================================
    // COMPILE
    // ===================================

    // The compiler is a Go library that can take a moment on big files, so it runs off the main thread.
    private func compile() {
        let code = source.trimmingCharacters(in: .whitespacesAndNewlines)
        working = true
        failed = false
        showDetails = false
        copied = false
        status = "Compiling…"

        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> (text: String, failed: Bool) in
                var error: NSError?
                if let data = CherriCompile(code, "Shortcut", &error) {
                    return ("Compiled OK: \(data.count) bytes of Shortcut plist.", false)
                }
                return (error?.localizedDescription ?? "Unknown error", true)
            }.value

            status = outcome.text
            failed = outcome.failed
            working = false
        }
    }

    // ===================================
    // IMPORT
    // ===================================

    // Empty or untouched starter code is safe to overwrite; anything else gets a question first, since the editor has no undo for a swap.
    private func handleImported(_ imported: ShortcutImporter.Imported) {
        showingImport = false

        let current = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if current.isEmpty || current == StarterCode.text.trimmingCharacters(in: .whitespacesAndNewlines) {
            applyImport(imported)
            return
        }

        pendingImport = imported
        // Presenting an alert while the sheet is still leaving can drop it, so give the sheet a beat to go.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showingImportReplaceConfirm = true }
    }

    private func applyImport(_ imported: ShortcutImporter.Imported) {
        source = imported.code
        failed = false
        showDetails = false
        copied = false
        let lines = imported.code.split(separator: "\n", omittingEmptySubsequences: false).count
        status = "Imported \"\(imported.name)\" (\(lines) lines). Tap Compile to check it."
    }

    // ===================================
    // EXPORT TO SHORTCUTS
    // ===================================

    // Reads "#define name My Shortcut" from the source so the exported shortcut and its signing request carry the user's chosen name; falls back to "Shortcut".
    private static func shortcutName(from code: String) -> String {
        let fallback = "Shortcut"
        guard let regex = try? NSRegularExpression(pattern: #"^[ \t]*#define[ \t]+name[ \t]+(.+?)[ \t]*$"#, options: [.anchorsMatchLines]),
              let match = regex.firstMatch(in: code, range: NSRange(code.startIndex..., in: code)),
              let range = Range(match.range(at: 1), in: code) else { return fallback }
        // File-name-hostile characters would break the temp file path.
        let cleaned = String(code[range])
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? fallback : String(cleaned.prefix(80))
    }

    // Compile, sign with HubSign, write a .shortcut file, then show the share sheet where "Shortcuts" imports it.
    private func exportToShortcuts() {
        let code = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = Self.shortcutName(from: code)
        working = true
        failed = false
        showDetails = false
        copied = false
        status = "Compiling…"

        Task {
            do {
                let plist = try await Task.detached(priority: .userInitiated) { () throws -> Data in
                    var error: NSError?
                    guard let data = CherriCompile(code, "Shortcut", &error) else {
                        throw error ?? NSError(domain: "CherriApp", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown error"])
                    }
                    return data
                }.value

                status = "Signing with HubSign…"
                let signed = try await HubSign.sign(plist: plist, name: name, compilerVersion: CherriCompilerVersion())

                let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).shortcut")
                try signed.write(to: url, options: .atomic)

                status = "Signed OK: \(signed.count) bytes. Tap Shortcuts in the share sheet to import."
                let file = ExportFile(url: url)
                if showShareTip {
                    pendingExport = file
                    showingShareTip = true
                } else {
                    exportFile = file
                }
            } catch {
                status = error.localizedDescription
                failed = true
            }
            working = false
        }
    }
}

// ===================================
// PREVIEW
// ===================================

#Preview {
    ContentView()
}



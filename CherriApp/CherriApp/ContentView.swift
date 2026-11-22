// ===================================
// Cherri App Main Screen
// v0.0.41 BUILD 2026-11-22 09:20
// Type Cherri code (saved between launches), insert actions and values at the cursor from the picker, compile it with the embedded compiler, or export it: sign via the custom signing server and open the share sheet to import into Shortcuts. Import pulls an existing shortcut in from an iCloud link (pasted, or shared to the app from the Shortcuts app) in the Import sheet, which also asks whether to turn it back into Cherri code or copy some of its actions. The title bar shows the shortcut's icon, color and name (read from the code's '#define' lines); tapping it opens the editor for all three. Clearing the editor first saves the code to disk, so a Restore button can bring it back, even after the app is closed.
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
    // The code from the last Clear, kept on disk so Restore still works after the app closes. It is dropped as soon as new code is typed, so it can never be offered against work that came after it.
    @AppStorage("clearedBackup") private var clearedBackup = ""
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
    @State private var showingStyle = false
    // An import waits here while the replace-your-code question is on screen.
    @State private var pendingImport: ShortcutImporter.Imported?
    @State private var showingImportReplaceConfirm = false
    // A link the Share extension handed over; the Import sheet downloads it as soon as it opens.
    @State private var sharedLink: String?
    @State private var unsupportedImport: ShortcutImporter.Imported?
    @State private var showingUnsupportedNotice = false
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
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
                    // A link shared from the Shortcuts app is waiting in the shared App Group. Each of these can be the first to see it, and takePendingLink clears it, so it only imports once.
                    .onOpenURL { url in
                        if url.scheme == SharedImport.scheme { importSharedLink() }
                    }
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .active { importSharedLink() }
                    }
                    .onAppear(perform: importSharedLink)
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
                    // Replaces the plain title with the shortcut's own icon and name, like the Shortcuts editor. The navigationTitle above stays so pushed screens keep a sensible back label.
                    ToolbarItem(placement: .principal) {
                        Button {
                            editor.textView?.resignFirstResponder()
                            showingStyle = true
                        } label: {
                            ShortcutHeaderLabel(style: ShortcutStyleEditor.parse(source))
                        }
                        .buttonStyle(.plain)
                    }
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
                .overlay {
                    // Only while the editor is empty, so it sits in the blank space and never covers code.
                    if source.isEmpty && !clearedBackup.isEmpty {
                        Button {
                            source = clearedBackup
                            clearedBackup = ""
                        } label: {
                            Label("Restore cleared code", systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .onChange(of: source) { _, newValue in
                    // New code means the old backup is stale, and keeping it would let an empty editor offer to bring back something unrelated.
                    if !newValue.isEmpty && !clearedBackup.isEmpty { clearedBackup = "" }
                }

            HStack(spacing: 12) {
                // Only Compile takes the accent color. The other three are neutral so nothing but the primary action competes for attention.
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
                .tint(.primary)

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
                .tint(.primary)

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
                .tint(.primary)
            }
            .disabled(working)
            .sheet(isPresented: $showingImport, onDismiss: { sharedLink = nil }) {
                // The id restarts the sheet if a different link is shared while it is open.
                ImportView(initialLink: sharedLink, onImported: handleImported, onCopyActions: handleCopyActions)
                    .id(sharedLink ?? "")
            }
            .sheet(isPresented: $showingStyle) {
                ShortcutStyleSheet(style: ShortcutStyleEditor.parse(source), onApply: applyStyle)
            }
            .sheet(isPresented: $showingActions) {
                ActionPickerView(
                    source: source,
                    codeAbove: editor.codeAboveInsertion,
                    onInsert: { editor.insertStatement($0) },
                    onInsertValue: { editor.insertInline($0) },
                    onStyle: applyStyle
                )
            }

            Text("Export sends your shortcut to \(LocalSigner.destination) to be signed.")
                .font(.caption)
                .foregroundStyle(Color.helperText)
                .frame(maxWidth: .infinity, alignment: .leading)

            statusArea
        }
        .padding()
        // The buttons and the empty space around the editor are not a scroll view, so a swipe down there needs its own handler. Drags that start inside the editor are skipped: the editor has its own swipe, and dragging a selection handle straight down looks the same as a swipe, which dropped the keyboard and wiped the selection.
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 24, coordinateSpace: .global)
                .onEnded { value in
                    if let textView = editor.textView, textView.window != nil {
                        let editorFrame = textView.convert(textView.bounds, to: nil)
                        if editorFrame.contains(value.startLocation) { return }
                    }

                    if value.translation.height > 60 && abs(value.translation.width) < value.translation.height {
                        editor.textView?.resignFirstResponder()
                    }
                }
        )
        .sheet(item: $exportFile) { file in
            ShareSheet(url: file.url)
        }
        .alert("Export Shortcut?", isPresented: $confirmingExport) {
            Button("Export") { exportToShortcuts() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your shortcut will be sent to \(LocalSigner.destination) to be signed. You can turn this prompt off in Settings.")
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
        .alert("Some Actions Aren't Supported Yet", isPresented: $showingUnsupportedNotice) {
            Button("Tell Support") {
                if let imported = unsupportedImport {
                    let details = "Unsupported actions on import: \(imported.unsupportedActions.joined(separator: ", ")) | Link: \(imported.link)"
                    openURL(Feedback.url(error: details))
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            let actions = unsupportedImport?.unsupportedActions ?? []
            Text("\"\(unsupportedImport?.name ?? "This shortcut")\" uses \(actions.count == 1 ? "an action" : "\(actions.count) actions") Cherri Shortcuts doesn't support yet:\n\n\(actions.joined(separator: "\n"))\n\nThey're kept in your code as rawAction lines, so they may lose their settings or not work once compiled.")
        }
        .alert("Clear Editor?", isPresented: $showingClearConfirm) {
            Button("Clear", role: .destructive) {
                // Saved before the editor is emptied, and only when there is something to save, so clearing an already empty editor never wipes the backup.
                if !source.isEmpty { clearedBackup = source }
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
                    // System red is too pale on white for small text (about 3.6:1), so errors use the darker Cherri red, which also keeps red meaning one thing in the app.
                    .font(.system(.footnote, design: .monospaced).weight(.medium))
                    .foregroundStyle(Color("CherriRed"))
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
                // Neutral so the red error line stays the only red thing here and these still read as buttons.
                .tint(.primary)

                Link("Send Feedback about this error", destination: Feedback.url(error: headline))
                    .font(.footnote)
                    .tint(.primary)

                if showDetails {
                    FittingScrollView(maxHeight: 140) {
                        Text(status)
                            .font(.system(.footnote, design: .monospaced).weight(.medium))
                            .foregroundStyle(Color("CherriRed").opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
        } else {
            // The spinner shows for the whole compile, sign or import, so a quick failure still reads as "it tried" and a 4 to 5 second sign doesn't look frozen.
            HStack(alignment: .top, spacing: 8) {
                if working {
                    ProgressView()
                        .controlSize(.small)
                }
                FittingScrollView(maxHeight: 140) {
                    Text(status)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Color.helperText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
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

    // The person chose Copy Actions in the Import sheet. Placeholder until the action list screen exists (next step on this branch).
    private func handleCopyActions(_ fetched: ShortcutImporter.Fetched) {
        showingImport = false
        failed = false
        status = "Copy Actions: downloaded \"\(fetched.name)\" (\(fetched.plist.count) bytes). The action list is the next piece."
    }

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

    // A shortcut shared from the Shortcuts app opens the same Import sheet as a pasted link, with the link filled in and the download already running. The sheet owns everything from there: retries while iCloud publishes the link, errors, and the choice of code or copy actions.
    private func importSharedLink() {
        guard let link = SharedImport.takePendingLink() else { return }
        sharedLink = link
        showingImport = true
    }

    private func applyImport(_ imported: ShortcutImporter.Imported) {
        source = imported.code
        failed = false
        showDetails = false
        copied = false
        let lines = imported.code.split(separator: "\n", omittingEmptySubsequences: false).count
        status = "Imported \"\(imported.name)\" (\(lines) lines). Tap Compile to check it."

        guard !imported.unsupportedActions.isEmpty else { return }
        let count = imported.unsupportedActions.count
        status += " \(count) unsupported action\(count == 1 ? "" : "s") kept as rawAction."
        unsupportedImport = imported
        // The import sheet or the replace alert may still be leaving, and an alert presented over them can be dropped.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { showingUnsupportedNotice = true }
    }

    // ===================================
    // STYLE
    // ===================================

    // Writes the chosen name, color and icon back into the code's '#define' lines. The editor picks up the changed source on its own.
    private func applyStyle(_ style: ShortcutStyle) {
        source = ShortcutStyleEditor.apply(style, to: source)
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

    // Compile, sign with the custom signing server, write a .shortcut file, then show the share sheet where "Shortcuts" imports it.
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

                status = "Signing your shortcut…"
                let signed = try await ShortcutSigner.sign(plist: plist, name: name, compilerVersion: CherriCompilerVersion(), onRetry: { status = $0 })

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
// FITTING SCROLL VIEW
// ===================================

// A plain ScrollView takes all the height it is offered, so a one-line status still held back a 140pt blank band that the editor could have used. This one is only as tall as its content, up to maxHeight, and scrolls past that.
private struct FittingScrollView<Content: View>: View {
    let maxHeight: CGFloat
    let content: Content
    @State private var contentHeight: CGFloat = 0

    init(maxHeight: CGFloat, @ViewBuilder content: () -> Content) {
        self.maxHeight = maxHeight
        self.content = content()
    }

    var body: some View {
        ScrollView {
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .frame(height: min(contentHeight, maxHeight))
    }
}

// ===================================
// PREVIEW
// ===================================

#Preview {
    ContentView()
}



// ===================================
// Cherri App Main Screen
// v0.0.15 BUILD 2026-10-16 03:52
// Type Cherri code (saved between launches), insert actions and values at the cursor from the picker, compile it with the embedded compiler, or export it: sign via HubSign and open the share sheet to import into Shortcuts.
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
    @AppStorage("cherriSource") private var source = "alert(\"Hello from Cherri\")\n"
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
    @AppStorage(EditorSettings.fontKey) private var fontID = EditorFont.system.rawValue
    @AppStorage(EditorSettings.sizeKey) private var fontSize = EditorSettings.defaultSize
    @AppStorage(EditorSettings.lightKey) private var lightThemeID = EditorSettings.defaultLightThemeID
    @AppStorage(EditorSettings.darkKey) private var darkThemeID = EditorSettings.defaultDarkThemeID
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
                .navigationTitle("CherriCuts")
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
                        Button(action: {
                            editor.textView?.resignFirstResponder()
                            showingGuide = true
                        }) {
                            Image(systemName: "questionmark.circle")
                        }
                    }
                }
                // Pushed, not a sheet: a sheet and a fullScreenCover on the same view conflict and the sheet never opened.
                .navigationDestination(isPresented: $showingGuide) {
                    GuideView(onShowWelcome: { showingWelcome = true })
                }
                .navigationDestination(isPresented: $showingSettings) {
                    SettingsView()
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
        EditorSettings.style(fontID: fontID, size: fontSize, lightID: lightThemeID, darkID: darkThemeID, dark: colorScheme == .dark)
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
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: compile) {
                    Text("Compile")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(action: exportToShortcuts) {
                    Text("Export")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .disabled(working)
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
        let code = source
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
    // EXPORT TO SHORTCUTS
    // ===================================

    // Compile, sign with HubSign, write a .shortcut file, then show the share sheet where "Shortcuts" imports it.
    private func exportToShortcuts() {
        let code = source
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
                let signed = try await HubSign.sign(plist: plist, name: "Shortcut", compilerVersion: CherriCompilerVersion())

                let url = FileManager.default.temporaryDirectory.appendingPathComponent("Shortcut.shortcut")
                try signed.write(to: url, options: .atomic)

                status = "Signed OK: \(signed.count) bytes. Choose Shortcuts in the share sheet to import."
                exportFile = ExportFile(url: url)
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



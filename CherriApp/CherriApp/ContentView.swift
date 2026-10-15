// ===================================
// Cherri App Main Screen
// v0.0.3 BUILD 2026-10-15 13:58
// Type Cherri code, insert actions from the picker, compile it with the embedded compiler, or export it: sign via HubSign and open the share sheet to import into Shortcuts.
// dev by @dastefster 🍒🔨
// ===================================

import SwiftUI
import Cherri

// ===================================
// MAIN VIEW
// ===================================

struct ContentView: View {
    @State private var source = "alert(\"Hello from Cherri\")\n"
    @State private var status = "Cherri \(CherriCompilerVersion())"
    @State private var failed = false
    @State private var working = false
    @State private var exportFile: ExportFile?
    @State private var showingActions = false

    var body: some View {
        VStack(spacing: 12) {
            TextEditor(text: $source)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 12) {
                Button(action: { showingActions = true }) {
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
                ActionPickerView { text in insert(text) }
            }

            Text("Export sends your shortcut to RoutineHub's HubSign service to be signed.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                Text(status)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(failed ? Color.red : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 140)
        }
        .padding()
        .sheet(item: $exportFile) { file in
            ShareSheet(url: file.url)
        }
    }

    // ===================================
    // INSERT ACTION
    // ===================================

    // Appends on its own line for now. Inserting at the cursor needs a UIKit text view, which comes later.
    private func insert(_ text: String) {
        if !source.isEmpty && !source.hasSuffix("\n") {
            source += "\n"
        }
        source += text + "\n"
    }

    // ===================================
    // COMPILE
    // ===================================

    // The compiler is a Go library that can take a moment on big files, so it runs off the main thread.
    private func compile() {
        let code = source
        working = true
        failed = false
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

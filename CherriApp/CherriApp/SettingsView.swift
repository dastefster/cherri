// ===================================
// Settings
// v0.0.13 BUILD 2026-10-25 07:45
// Grouped settings list with colored icon tiles: Editor (Appearance), App Icon, Export (ask before exporting), Your code (reset), Help (Guide, Documentation, Welcome), About (versions, credits, licenses, one Send Feedback row that opens a small menu: form or email) and a debug-only Developer section. App Icon opens a grid picker (see AppIconView).
// dev by @dastefster 🍒🔨
// ===================================

import SwiftUI
import Cherri

// ===================================
// SHARED SETTINGS VALUES
// ===================================

// The code the editor starts with, and what "Reset Editor" goes back to.
enum StarterCode {
    static let text = "alert(\"Hello from Cherri\")\n"
}

enum ExportSettings {
    static let confirmKey = "confirmBeforeExport"
    static let tipKey = "showShareTip"
}

// ===================================
// ICON TILE
// ===================================

// The small colored rounded square used beside each settings row.
struct SettingsIcon: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 29, height: 29)
            .background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

// A row label with its icon tile.
struct SettingsLabel: View {
    let title: String
    let symbol: String
    let color: Color

    var body: some View {
        Label {
            Text(title)
        } icon: {
            SettingsIcon(symbol: symbol, color: color)
        }
    }
}

// ===================================
// SETTINGS VIEW
// ===================================

struct SettingsView: View {
    let onShowWelcome: () -> Void

    @AppStorage(ExportSettings.confirmKey) private var confirmBeforeExport = true
    @AppStorage(ExportSettings.tipKey) private var showShareTip = true
    @AppStorage("cherriSource") private var source = StarterCode.text
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = true
    @AppStorage(PremiumStore.unlockedKey) private var isPremium = false
    @State private var confirmingReset = false
    
    // Only used to show the current icon name on the row; the picker screen does the switching.
    @State private var activeIcon: String = UIApplication.shared.alternateIconName ?? "AppIcon"

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    PremiumView()
                } label: {
                    LabeledContent {
                        Text(isPremium ? "Unlocked" : "")
                    } label: {
                        SettingsLabel(title: "Cherri Premium", symbol: "crown.fill", color: PremiumStore.gold)
                    }
                }
            }

            Section("Editor") {
                NavigationLink {
                    AppearanceView()
                } label: {
                    SettingsLabel(title: "Appearance", symbol: "textformat.size", color: .indigo)
                }
            }
            
            Section {
                NavigationLink {
                    AppIconView()
                } label: {
                    LabeledContent {
                        Text(AppIconOption.title(for: activeIcon))
                    } label: {
                        SettingsLabel(title: "App Icon", symbol: "app.dashed", color: .purple)
                    }
                }
            }

            Section {
                Toggle(isOn: $confirmBeforeExport) {
                    SettingsLabel(title: "Ask Before Exporting", symbol: "paperplane.fill", color: .blue)
                }

                Toggle(isOn: $showShareTip) {
                    SettingsLabel(title: "Show Import Tip", symbol: "lightbulb.fill", color: .orange)
                }
            } header: {
                Text("Export")
            } footer: {
                Text("Export sends your shortcut to RoutineHub's HubSign service to be signed. Compile stays on your device. The import tip reminds you to tap Shortcuts in the share sheet.")
            }

            Section("Your Code") {
                Button(role: .destructive, action: { confirmingReset = true }) {
                    SettingsLabel(title: "Reset Editor to Starter Code", symbol: "arrow.counterclockwise", color: .red)
                }
            }

            Section("Help") {
                NavigationLink {
                    GuideView(onShowWelcome: onShowWelcome)
                } label: {
                    SettingsLabel(title: "Guide", symbol: "book.fill", color: .teal)
                }
                NavigationLink {
                    DocumentationView()
                } label: {
                    SettingsLabel(title: "Documentation", symbol: "text.book.closed.fill", color: .gray)
                }
                Button(action: onShowWelcome) {
                    SettingsLabel(title: "Show Welcome Screen", symbol: "hand.wave.fill", color: .orange)
                }
            }

            Section("About") {
                LabeledContent {
                    Text(appVersion)
                } label: {
                    SettingsLabel(title: "Cherri Shortcuts", symbol: "info.circle.fill", color: .gray)
                }
                LabeledContent {
                    Text(CherriCompilerVersion())
                } label: {
                    SettingsLabel(title: "Cherri Compiler", symbol: "hammer.fill", color: .pink)
                }
                Link(destination: URL(string: "https://cherrilang.org")!) {
                    SettingsLabel(title: "Cherri Language", symbol: "globe", color: .blue)
                }
                NavigationLink {
                    LicensesView()
                } label: {
                    SettingsLabel(title: "Licenses", symbol: "doc.text.fill", color: .gray)
                }
                Link(destination: URL(string: "https://dastefster.github.io/cherricuts/privacy.html")!) {
                    SettingsLabel(title: "Privacy Policy", symbol: "hand.raised.fill", color: .blue)
                }
                // One row; the form-or-email choice lives on its own screen so the list stays short.
                NavigationLink {
                    FeedbackView()
                } label: {
                    SettingsLabel(title: "Send Feedback", symbol: "text.bubble.fill", color: .green)
                }
            }

            #if DEBUG
            Section("Developer") {
                Button(role: .destructive, action: { hasSeenWelcome = false }) {
                    SettingsLabel(title: "Reset First Run", symbol: "wrench.and.screwdriver.fill", color: .gray)
                }
            }
            #endif
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { activeIcon = UIApplication.shared.alternateIconName ?? "AppIcon" }
        .confirmationDialog("Reset the editor?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset Editor", role: .destructive) { source = StarterCode.text }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This replaces everything in the editor with the starter code. It can't be undone.")
        }
    }
}

// ===================================
// LICENSES VIEW
// ===================================

struct LicensesView: View {
    var body: some View {
        List {
            Section {
                Text("Cherri Shortcuts includes the Cherri compiler, created by the Cherri developers (electrikmilk and contributors) and licensed under the GNU General Public License, version 2. Cherri Shortcuts uses a modified build that adds extra actions, and the source for it is available below.")
                Link("Cherri (original)", destination: URL(string: "https://github.com/electrikmilk/cherri")!)
                Link("Cherri build used by Cherri Shortcuts", destination: URL(string: "https://github.com/dastefster/cherri")!)
                Link("GNU GPL version 2", destination: URL(string: "https://www.gnu.org/licenses/old-licenses/gpl-2.0.html")!)
            } header: {
                Text("Cherri")
            } footer: {
                Text("This program comes with ABSOLUTELY NO WARRANTY, to the extent permitted by law.")
            }

            Section("Signing") {
                Text("Shortcut signing is provided by RoutineHub's HubSign service.")
            }

            Section {
                Text("Shortcuts is a trademark of Apple Inc. Cherri Shortcuts is an independent app and is not affiliated with or endorsed by Apple.")
            }
        }
        .navigationTitle("Licenses")
        .navigationBarTitleDisplayMode(.inline)
    }
}

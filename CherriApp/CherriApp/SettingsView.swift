// ===================================
// Settings
// v0.0.1 BUILD 2026-10-16 03:34
// Grouped settings list with colored icon tiles. This first version has the Editor section (Appearance); Help, Export, Your code and About come next.
// dev by @dastefster 🍒🔨
// ===================================

import SwiftUI

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
    var body: some View {
        List {
            Section("Editor") {
                NavigationLink {
                    AppearanceView()
                } label: {
                    SettingsLabel(title: "Appearance", symbol: "textformat.size", color: .indigo)
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

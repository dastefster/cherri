// ===================================
// Share Sheet
// v0.0.1 BUILD 2026-10-15 13:40
// Wraps the iOS share sheet so a signed .shortcut file can be handed to Shortcuts.
// dev by @dastefster 🍒🔨
// ===================================

import SwiftUI
import UIKit

// ===================================
// EXPORT FILE
// ===================================

// URL is not Identifiable, and .sheet(item:) needs an identity to know when to present.
struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

// ===================================
// SHARE SHEET
// ===================================

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

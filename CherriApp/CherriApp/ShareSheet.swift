// ===================================
// Share Sheet
// v0.0.3 BUILD 2026-10-16 16:58
// Hands a signed .shortcut file to Shortcuts through the iOS share sheet. Rows that only distract (Save to Files, AirDrop, Copy, Messages, Mail and similar) are hidden so Shortcuts is easy to find.
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
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)

        // Save to Files has no public constant, and it hung once on a real device, so it is excluded by identifier.
        controller.excludedActivityTypes = [
            UIActivity.ActivityType("com.apple.DocumentManagerUICore.SaveToFiles"),
            .airDrop,
            .copyToPasteboard,
            .message,
            .mail,
            .print,
            .assignToContact,
            .addToReadingList,
            .markupAsPDF,
            .saveToCameraRoll,
            .openInIBooks
        ]
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

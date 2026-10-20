// ===================================
// Feedback
// v0.0.1 BUILD 2026-10-20 00:15
// Builds the link to the CherriCuts Google Form. Version, device and (optionally) the error text are pre-filled so testers only have to describe what happened. Email stays available as a fallback.
// dev by @dastefster 🍒🔨
// ===================================

import Foundation
import UIKit

// ===================================
// FEEDBACK FORM
// ===================================

enum Feedback {
    private static let formURL = "https://docs.google.com/forms/d/e/1FAIpQLSeFj3Ycz8AEskpgEdXyVgQKt0UX1boHChPYYj0pUwL_gJ0hrQ/viewform"

    // Field IDs come from the form's "Pre-fill form" page; they only change if a question is deleted and re-added.
    private static let versionField = "entry.1677084819"
    private static let deviceField = "entry.1545904154"
    private static let errorField = "entry.414612068"

    static let mailURL = URL(string: "mailto:dastefster@gmail.com?subject=CherriCuts%20feedback")!

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private static var device: String {
        "\(UIDevice.current.model), iOS \(UIDevice.current.systemVersion)"
    }

    // Long URLs can be rejected, so the error text is capped; the full message is still one tap away via Copy full message.
    static func url(error: String? = nil) -> URL {
        var items = [
            URLQueryItem(name: "usp", value: "pp_url"),
            URLQueryItem(name: versionField, value: appVersion),
            URLQueryItem(name: deviceField, value: device)
        ]
        if let error, !error.isEmpty {
            items.append(URLQueryItem(name: errorField, value: String(error.prefix(1200))))
        }
        var components = URLComponents(string: formURL)!
        components.queryItems = items
        return components.url ?? URL(string: formURL)!
    }
}

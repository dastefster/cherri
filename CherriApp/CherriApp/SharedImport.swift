// ===================================
// Shared Import Handoff
// v0.0.1 BUILD 2026-10-25 06:55
// Picks up an iCloud link that the Share extension saved in the shared App Group, so a shortcut shared from the Shortcuts app imports when Cherri Shortcuts opens.
// dev by @dastefster 🍒🔨
// ===================================

import Foundation

// ===================================
// HANDOFF
// ===================================

// Keep groupID, linkKey and dateKey identical to the Handoff enum in the Share extension.
enum SharedImport {
    static let groupID = "group.com.dastefster.CherriApp"
    static let linkKey = "pendingImportLink"
    static let dateKey = "pendingImportDate"
    static let scheme = "cherrishortcuts"

    // A link older than this was probably forgotten, and importing it later with no warning would be a surprise.
    private static let maxAge: TimeInterval = 15 * 60

    // Returns the saved link once and clears it, so a second call (the URL arrives and the app becomes active) imports nothing twice.
    static func takePendingLink() -> String? {
        guard let defaults = UserDefaults(suiteName: groupID) else { return nil }
        defer {
            defaults.removeObject(forKey: linkKey)
            defaults.removeObject(forKey: dateKey)
        }

        guard let link = defaults.string(forKey: linkKey) else { return nil }
        let saved = defaults.double(forKey: dateKey)
        guard saved > 0, Date().timeIntervalSince1970 - saved <= maxAge else { return nil }

        return link
    }
}

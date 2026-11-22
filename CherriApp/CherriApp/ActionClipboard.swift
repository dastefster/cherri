// ===================================
// Action Clipboard
// v0.0.1 BUILD 2026-11-22 10:20
// Puts Shortcuts actions on the clipboard the way the Shortcuts app does, so they can be pasted into any shortcut. One pasteboard item per action, in order, each holding a binary plist of that single action under com.apple.shortcuts.action. Verified: the Mac's Shortcuts app writes exactly this, and the iPhone's Shortcuts app pastes what this app writes.
// dev by @dastefster 🍒🔨
// ===================================

import UIKit

// ===================================
// CLIPBOARD
// ===================================

enum ActionClipboard {
    static let type = "com.apple.shortcuts.action"

    // Returns how many actions were copied, or nil if one couldn't be turned into plist data (nothing is copied in that case).
    @discardableResult
    static func copy(_ actions: [[String: Any]]) -> Int? {
        guard !actions.isEmpty else { return nil }

        var items: [[String: Any]] = []
        for action in actions {
            guard let data = try? PropertyListSerialization.data(fromPropertyList: action, format: .binary, options: 0) else {
                return nil
            }
            items.append([type: data])
        }

        UIPasteboard.general.setItems(items, options: [:])
        return items.count
    }
}

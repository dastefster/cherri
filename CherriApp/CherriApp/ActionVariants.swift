// ===================================
// Action Variants
// v0.0.1 BUILD 2026-10-15 18:35
// Pairs of Cherri actions that Shortcuts shows as one action with a switch, so the picker can show one entry and the form picks the right function name.
// dev by @dastefster 🍒🔨
// ===================================

import Foundation

// ===================================
// VARIANT TABLE
// ===================================

nonisolated struct ActionVariant: Sendable {
    let primary: String
    let alternate: String
    let switchTitle: String
    let switchNote: String
}

nonisolated enum ActionVariants {
    // Hand-kept on purpose: only pairs worth merging go here, not every action.
    static let all: [ActionVariant] = [
        ActionVariant(
            primary: "alert",
            alternate: "confirm",
            switchTitle: "Show cancel button",
            switchNote: "Adds a Cancel button that stops the shortcut when tapped. Written as confirm instead of alert."
        )
    ]

    static func variant(for name: String) -> ActionVariant? {
        all.first { $0.primary == name }
    }

    static func isAlternate(_ name: String) -> Bool {
        all.contains { $0.alternate == name }
    }
}

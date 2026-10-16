// ===================================
// Editor Variables
// v0.0.2 BUILD 2026-10-15 22:35
// Finds the variables the code in the editor declares, written the way Cherri needs them referenced, so the action form can offer them in a menu instead of making people type them.
// dev by @dastefster 🍒🔨
// ===================================

import Foundation

// ===================================
// VARIABLE NAMES
// ===================================

enum EditorVariables {
    // Cherri's built-in globals are case-sensitive and referenced bare.
    static let builtIns = ["ShortcutInput", "Clipboard", "CurrentDate", "Device"]

    // Mutable variables need the @ prefix when referenced, constants are referenced by their bare name.
    // Newest first, because the variable just made is usually the one wanted and big scripts declare hundreds.
    static func names(in source: String) -> [String] {
        let patterns: [(pattern: String, prefix: String)] = [
            (#"^\s*@(\w+)\s*(?:[:=]|[+\-*/]=)"#, "@"),
            (#"^\s*const\s+(\w+)\s*="#, "")
        ]

        var found: [(position: Int, name: String)] = []
        let whole = NSRange(source.startIndex..., in: source)

        for (pattern, prefix) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { continue }

            for match in regex.matches(in: source, range: whole) {
                guard let range = Range(match.range(at: 1), in: source) else { continue }
                found.append((match.range.location, prefix + String(source[range])))
            }
        }

        var names: [String] = []
        for entry in found.sorted(by: { $0.position > $1.position }) where !names.contains(entry.name) {
            names.append(entry.name)
        }

        return names
    }
}

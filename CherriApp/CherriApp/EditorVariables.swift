// ===================================
// Editor Variables
// v0.0.3 BUILD 2026-11-18 17:20
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

    // What a variable was last given, read from the line that set it: quotes mean text, a bracket a list, a digit a number. Nil when the line is something this cannot judge (an action call, say), so callers stay quiet instead of guessing.
    static func kind(of name: String, in source: String) -> VariableKind? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let pattern = #"^[ \t]*@"# + escaped + #"[ \t]*(?::[ \t]*(\w+)|=(?!=)[ \t]*(.*?))[ \t]*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return nil }

        let whole = NSRange(source.startIndex..., in: source)
        guard let match = regex.matches(in: source, range: whole).last else { return nil }

        // "@x: type" declares the kind without a value.
        if let range = Range(match.range(at: 1), in: source) {
            switch String(source[range]) {
            case "text":
                return .text
            case "number", "float":
                return .number
            case "array":
                return .list
            default:
                return nil
            }
        }

        guard let range = Range(match.range(at: 2), in: source) else { return nil }
        let value = String(source[range])

        if value.hasPrefix("\"") || value.hasPrefix("'") { return .text }
        if value.hasPrefix("[") { return .list }
        if let first = value.first, first.isNumber || first == "-" || first == "(" { return .number }

        return nil
    }
}

enum VariableKind {
    case text
    case number
    case list
}

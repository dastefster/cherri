// ===================================
// Shortcut Style
// v0.0.1 BUILD 2026-11-07 14:05
// Reads a shortcut's name, color and icon from the '#define name/color/glyph' lines in the source, and writes changes back to those same lines without touching anything else. The editor header, the style sheet and the action picker all go through this, so the code stays the one source of truth.
// dev by @dastefster 🍒🔨
// ===================================

import Foundation

// ===================================
// STYLE
// ===================================

struct ShortcutStyle: Equatable {
    // nil means the source has no such line, so the compiler default applies.
    var name: String?
    var color: String?
    var glyph: String?

    var displayName: String {
        guard let name, !name.isEmpty else { return "Shortcut" }
        return name
    }
}

// ===================================
// READ AND REWRITE
// ===================================

enum ShortcutStyleEditor {
    private static let keys = ["name", "color", "glyph"]

    // A plain line scan instead of regex: the header calls this on every keystroke, so it has to stay cheap on long scripts.
    private static func define(in line: Substring) -> (key: String, value: String)? {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        guard trimmed.hasPrefix("#define") else { return nil }

        let afterWord = trimmed.dropFirst("#define".count)
        // "#defineX" is not a define, so a space or tab must follow.
        guard let first = afterWord.first, first == " " || first == "\t" else { return nil }

        let rest = afterWord.drop(while: { $0 == " " || $0 == "\t" })
        guard let end = rest.firstIndex(where: { $0 == " " || $0 == "\t" }) else { return nil }

        let key = String(rest[rest.startIndex..<end])
        guard keys.contains(key) else { return nil }

        let value = rest[end...].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : (key, value)
    }

    static func parse(_ source: String) -> ShortcutStyle {
        var style = ShortcutStyle()

        // The first of each define wins, matching what a reader sees at the top of the file.
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let found = define(in: line) else { continue }
            switch found.key {
            case "name": if style.name == nil { style.name = found.value }
            case "color": if style.color == nil { style.color = found.value }
            case "glyph": if style.glyph == nil { style.glyph = found.value }
            default: break
            }
        }

        return style
    }

    // Names go on one line and into a file name later, so strip line breaks and keep it a sane length.
    static func cleanName(_ name: String) -> String? {
        let flattened = name
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        let limited = String(flattened.prefix(80)).trimmingCharacters(in: .whitespaces)
        return limited.isEmpty ? nil : limited
    }

    // Updates existing lines in place, removes a line whose value is nil, and adds missing lines to the top define block. Everything else in the source is returned untouched.
    static func apply(_ style: ShortcutStyle, to source: String) -> String {
        var lines = source.components(separatedBy: "\n")

        for (key, value) in [("name", style.name), ("color", style.color), ("glyph", style.glyph)] {
            lines = set(key, to: value, in: lines)
        }

        return lines.joined(separator: "\n")
    }

    private static func set(_ key: String, to value: String?, in lines: [String]) -> [String] {
        var result = lines
        let matches = result.indices.filter { define(in: Substring(result[$0]))?.key == key }

        guard let value else {
            // Remove from the bottom up so earlier indexes stay valid.
            for index in matches.reversed() { result.remove(at: index) }
            return result
        }

        let line = "#define \(key) \(value)"

        if let first = matches.first {
            result[first] = line
            // Duplicates would fight each other, so keep just the one we updated.
            for index in matches.dropFirst().reversed() { result.remove(at: index) }
            return result
        }

        // New lines join the run of '#define' lines already at the top; with none, they start the file.
        var insertAt = 0
        while insertAt < result.count, result[insertAt].trimmingCharacters(in: .whitespaces).hasPrefix("#define") {
            insertAt += 1
        }

        result.insert(line, at: insertAt)

        // Keep the defines visually apart from the code that follows.
        if insertAt == 0, result.count > 1, !result[1].trimmingCharacters(in: .whitespaces).isEmpty {
            result.insert("", at: 1)
        }

        return result
    }
}

// ===================================
// Cherri Syntax Highlighter
// v0.0.3 BUILD 2026-10-16 03:52
// Colors comments, strings, numbers, operators, type names, keywords, #directives, @variables, declared names (const, loop and function parameters) and action calls in a text view using the current theme. Regex passes only, so it stays instant on normal-sized shortcuts.
// dev by @dastefster 🍒🔨
// ===================================

import UIKit

// ===================================
// HIGHLIGHTER
// ===================================

@MainActor
enum CherriHighlighter {
    private static let typeNames: Set<String> = ["text", "number", "float", "bool", "dictionary", "array", "variable", "rawtext"]

    // One alternation, tried left to right at each position. Group order matters: a comment or string that starts earlier
    // swallows anything inside it, keywords are checked before action calls so `if (` stays a keyword, and a type name
    // followed by `(` is an action call like `text("hi")`, not a type.
    private static let tokenRegex: NSRegularExpression = {
        let pattern = [
            #"(//[^\n]*|/\*[\s\S]*?(?:\*/|\z))"#,                                                                 // 1 comment
            #"("(?:\\.|[^"\\\n])*"?|'[^'\n]*'?)"#,                                                                 // 2 string
            #"(#[A-Za-z]+)"#,                                                                                       // 3 directive
            #"(@[A-Za-z_][A-Za-z0-9_]*)"#,                                                                          // 4 variable
            #"(\b\d+(?:\.\d+)?\b)"#,                                                                                // 5 number
            #"(\b(?:if|else|repeat|for|in|function|const|enum|action|true|false|nil|contains|beginsWith|endsWith)\b)"#, // 6 keyword
            #"(\b(?:ShortcutInput|Clipboard|CurrentDate|Device|Ask)\b)"#,                                           // 7 global variable
            #"(\b(?:text|number|float|bool|dictionary|array|variable|rawtext)\b(?!\s*\())"#,                        // 8 type name
            #"(\b[A-Za-z_][A-Za-z0-9_]*(?=\s*\())"#,                                                                // 9 action call
            #"(==|!=|>=|<=|&&|\|\||\+=|-=|\*=|/=|[=<>+\-*/])"#,                                                      // 10 operator
        ].joined(separator: "|")

        // The pattern is a constant, so a failure here is a typo caught the first time the app runs.
        return try! NSRegularExpression(pattern: pattern)
    }()

    // Names the script creates itself, so every later use of them can share one color (Dracula's orange parameters).
    private static let declarationRegex: NSRegularExpression = {
        let pattern = [
            #"\bconst\s+([A-Za-z_][A-Za-z0-9_]*)"#,
            #"\b(?:repeat|for)\s+([A-Za-z_][A-Za-z0-9_]*)"#,
            #"\b(?:text|number|float|bool|dictionary|array|variable|rawtext)[?!]?\s+([A-Za-z_][A-Za-z0-9_]*)"#,
        ].joined(separator: "|")

        return try! NSRegularExpression(pattern: pattern)
    }()

    // The `{name}` and `{@name}` pieces inside a string.
    private static let interpolationRegex = try! NSRegularExpression(pattern: #"\{[^{}\n]+\}"#)

    private static func tokenColors(for theme: EditorTheme) -> [UIColor] {
        [theme.comment, theme.string, theme.keyword, theme.variable, theme.number, theme.keyword, theme.variable, theme.type, theme.action, theme.symbol]
    }

    // Keywords are drawn bold (as in Runestone). Falls back to the plain font if a face has no bold.
    private static func boldVariant(of font: UIFont) -> UIFont {
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(.traitBold) else { return font }
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }

    // Sets the whole text view up: background, cursor color, font, and the colored text.
    static func style(_ textView: UITextView, with style: EditorStyle) {
        textView.backgroundColor = style.theme.background
        textView.tintColor = style.theme.caret
        textView.font = style.font
        textView.textColor = style.theme.text

        apply(to: textView.textStorage, style: style)
        textView.typingAttributes = [.font: style.font, .foregroundColor: style.theme.text]
    }

    // Recolors the text only. Safe to call on every keystroke: attribute changes do not move the cursor.
    static func apply(to storage: NSTextStorage, style: EditorStyle) {
        let theme = style.theme
        let text = storage.string
        let nsText = text as NSString
        let full = NSRange(location: 0, length: storage.length)

        storage.beginEditing()
        storage.setAttributes([.font: style.font, .foregroundColor: theme.text], range: full)

        // Pass 1: the script's own names. Painted first so comments, strings and keywords can paint over them below.
        var names = Set<String>()
        declarationRegex.enumerateMatches(in: text, options: [], range: full) { match, _, _ in
            guard let match else { return }

            for group in 1...3 {
                let range = match.range(at: group)
                if range.location != NSNotFound {
                    let name = nsText.substring(with: range)
                    if !typeNames.contains(name) {
                        names.insert(name)
                    }
                    break
                }
            }
        }

        if !names.isEmpty && names.count < 300 {
            let alternation = names.sorted().map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
            if let namesRegex = try? NSRegularExpression(pattern: #"\b(?:"# + alternation + #")\b"#) {
                namesRegex.enumerateMatches(in: text, options: [], range: full) { match, _, _ in
                    if let match {
                        storage.addAttribute(.foregroundColor, value: theme.variable, range: match.range)
                    }
                }
            }
        }

        // Pass 2: comments, strings, numbers, keywords, types, action calls and operators.
        let palette = tokenColors(for: theme)
        let bold = boldVariant(of: style.font)
        tokenRegex.enumerateMatches(in: text, options: [], range: full) { match, _, _ in
            guard let match else { return }

            for (index, color) in palette.enumerated() {
                let range = match.range(at: index + 1)
                if range.location != NSNotFound {
                    storage.addAttribute(.foregroundColor, value: color, range: range)
                    if index == 5 {
                        storage.addAttribute(.font, value: bold, range: range)
                    }
                    break
                }
            }
        }

        // Pass 3: `{name}` pieces that sit inside a string get the variable color against the string color.
        interpolationRegex.enumerateMatches(in: text, options: [], range: full) { match, _, _ in
            guard let match else { return }

            let current = storage.attribute(.foregroundColor, at: match.range.location, effectiveRange: nil) as? UIColor
            if current == theme.string {
                storage.addAttribute(.foregroundColor, value: theme.variable, range: match.range)
            }
        }

        storage.endEditing()
    }
}

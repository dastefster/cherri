// ===================================
// Editor Themes, Fonts and Settings Keys
// v0.0.7 BUILD 2026-10-21 16:10
// Color themes (each with light or dark use), monospaced font choices, and the saved-settings keys shared by the editor and the Settings screens.
// dev by @dastefster 🍒🔨
// ===================================

import SwiftUI
import UIKit

// ===================================
// THEME MODEL
// ===================================

struct EditorTheme: Identifiable, Hashable {
    let id: String
    let name: String
    let background: UIColor
    let text: UIColor
    let comment: UIColor
    let string: UIColor
    let number: UIColor
    let keyword: UIColor
    let variable: UIColor
    let action: UIColor
    let type: UIColor
    let caret: UIColor
    // Operators and punctuation. Most themes color them like keywords; Tomorrow Night Bright keeps them muted.
    var symbolOverride: UIColor? = nil
    // A frame around the editor, for themes whose background would otherwise melt into the screen.
    var border: UIColor? = nil

    var symbol: UIColor {
        symbolOverride ?? keyword
    }

    static func == (lhs: EditorTheme, rhs: EditorTheme) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// What the editor needs to draw itself: a font and a theme.
struct EditorStyle {
    let font: UIFont
    let theme: EditorTheme

    // Changes whenever something visible changes, so the editor only restyles when it has to.
    var key: String {
        "\(theme.id)|\(font.fontName)|\(font.pointSize)"
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// ===================================
// BUILT-IN THEMES
// ===================================

// Computed rather than stored so the colors never become shared mutable state.
extension EditorTheme {
    static var all: [EditorTheme] {
        [standard, dracula, tomorrowNightBright, oneDark, solarizedDark, solarizedLight, githubLight,
         nord, monokai, gruvboxDark, tokyoNight, catppuccinMocha, githubDark, catppuccinLatte]
    }

    static func theme(id: String) -> EditorTheme {
        all.first(where: { $0.id == id }) ?? standard
    }

    // Follows the system light and dark appearance with the system's own colors.
    static var standard: EditorTheme {
        EditorTheme(
            id: EditorSettings.defaultThemeID, name: "Default",
            background: .secondarySystemBackground, text: .label, comment: .systemGray,
            string: .systemRed, number: .systemPurple, keyword: .systemPink,
            variable: .systemTeal, action: .systemBlue, type: .systemCyan, caret: .systemBlue
        )
    }

    static var dracula: EditorTheme {
        EditorTheme(
            id: "dracula", name: "Dracula",
            background: UIColor(hex: 0x282A36), text: UIColor(hex: 0xF8F8F2), comment: UIColor(hex: 0x6272A4),
            string: UIColor(hex: 0xF1FA8C), number: UIColor(hex: 0xBD93F9), keyword: UIColor(hex: 0xFF79C6),
            variable: UIColor(hex: 0xFFB86C), action: UIColor(hex: 0x50FA7B), type: UIColor(hex: 0x8BE9FD), caret: UIColor(hex: 0xF8F8F0)
        )
    }

    static var tomorrowNightBright: EditorTheme {
        EditorTheme(
            id: "tomorrow-night-bright", name: "Tomorrow Night Bright",
            background: UIColor(hex: 0x000000), text: UIColor(hex: 0xEAEAEA), comment: UIColor(hex: 0x969896),
            string: UIColor(hex: 0xB9CA4A), number: UIColor(hex: 0xE78C45), keyword: UIColor(hex: 0xC397D8),
            variable: UIColor(hex: 0xD54E53), action: UIColor(hex: 0x7AA6DA), type: UIColor(hex: 0x70C0B1), caret: UIColor(hex: 0xEAEAEA), symbolOverride: UIColor(hex: 0x969896), border: UIColor(hex: 0x282A36)
        )
    }

    static var oneDark: EditorTheme {
        EditorTheme(
            id: "one-dark", name: "One Dark",
            background: UIColor(hex: 0x282C34), text: UIColor(hex: 0xABB2BF), comment: UIColor(hex: 0x5C6370),
            string: UIColor(hex: 0x98C379), number: UIColor(hex: 0xD19A66), keyword: UIColor(hex: 0xC678DD),
            variable: UIColor(hex: 0xE06C75), action: UIColor(hex: 0x61AFEF), type: UIColor(hex: 0xE5C07B), caret: UIColor(hex: 0x528BFF)
        )
    }

    static var solarizedDark: EditorTheme {
        EditorTheme(
            id: "solarized-dark", name: "Solarized Dark",
            background: UIColor(hex: 0x002B36), text: UIColor(hex: 0x839496), comment: UIColor(hex: 0x586E75),
            string: UIColor(hex: 0x2AA198), number: UIColor(hex: 0xD33682), keyword: UIColor(hex: 0x859900),
            variable: UIColor(hex: 0xCB4B16), action: UIColor(hex: 0x268BD2), type: UIColor(hex: 0xB58900), caret: UIColor(hex: 0x93A1A1)
        )
    }

    static var solarizedLight: EditorTheme {
        EditorTheme(
            id: "solarized-light", name: "Solarized Light",
            background: UIColor(hex: 0xFDF6E3), text: UIColor(hex: 0x657B83), comment: UIColor(hex: 0x93A1A1),
            string: UIColor(hex: 0x2AA198), number: UIColor(hex: 0xD33682), keyword: UIColor(hex: 0x859900),
            variable: UIColor(hex: 0xCB4B16), action: UIColor(hex: 0x268BD2), type: UIColor(hex: 0xB58900), caret: UIColor(hex: 0x586E75)
        )
    }

    static var githubLight: EditorTheme {
        EditorTheme(
            id: "github-light", name: "GitHub Light",
            background: UIColor(hex: 0xFFFFFF), text: UIColor(hex: 0x24292F), comment: UIColor(hex: 0x6E7781),
            string: UIColor(hex: 0x0A3069), number: UIColor(hex: 0x0550AE), keyword: UIColor(hex: 0xCF222E),
            variable: UIColor(hex: 0x953800), action: UIColor(hex: 0x8250DF), type: UIColor(hex: 0x1B7C83), caret: UIColor(hex: 0x24292F)
        )
    }

    static var nord: EditorTheme {
        EditorTheme(
            id: "nord", name: "Nord",
            background: UIColor(hex: 0x2E3440), text: UIColor(hex: 0xD8DEE9), comment: UIColor(hex: 0x616E88),
            string: UIColor(hex: 0xA3BE8C), number: UIColor(hex: 0xB48EAD), keyword: UIColor(hex: 0x81A1C1),
            variable: UIColor(hex: 0xD08770), action: UIColor(hex: 0x88C0D0), type: UIColor(hex: 0x8FBCBB), caret: UIColor(hex: 0xD8DEE9)
        )
    }

    static var monokai: EditorTheme {
        EditorTheme(
            id: "monokai", name: "Monokai",
            background: UIColor(hex: 0x272822), text: UIColor(hex: 0xF8F8F2), comment: UIColor(hex: 0x75715E),
            string: UIColor(hex: 0xE6DB74), number: UIColor(hex: 0xAE81FF), keyword: UIColor(hex: 0xF92672),
            variable: UIColor(hex: 0xFD971F), action: UIColor(hex: 0xA6E22E), type: UIColor(hex: 0x66D9EF), caret: UIColor(hex: 0xF8F8F0)
        )
    }

    static var gruvboxDark: EditorTheme {
        EditorTheme(
            id: "gruvbox-dark", name: "Gruvbox Dark",
            background: UIColor(hex: 0x282828), text: UIColor(hex: 0xEBDBB2), comment: UIColor(hex: 0x928374),
            string: UIColor(hex: 0xB8BB26), number: UIColor(hex: 0xD3869B), keyword: UIColor(hex: 0xFB4934),
            variable: UIColor(hex: 0xFE8019), action: UIColor(hex: 0x83A598), type: UIColor(hex: 0xFABD2F), caret: UIColor(hex: 0xEBDBB2)
        )
    }

    static var tokyoNight: EditorTheme {
        EditorTheme(
            id: "tokyo-night", name: "Tokyo Night",
            background: UIColor(hex: 0x1A1B26), text: UIColor(hex: 0xC0CAF5), comment: UIColor(hex: 0x565F89),
            string: UIColor(hex: 0x9ECE6A), number: UIColor(hex: 0xFF9E64), keyword: UIColor(hex: 0xBB9AF7),
            variable: UIColor(hex: 0xF7768E), action: UIColor(hex: 0x7AA2F7), type: UIColor(hex: 0x2AC3DE), caret: UIColor(hex: 0xC0CAF5)
        )
    }

    static var catppuccinMocha: EditorTheme {
        EditorTheme(
            id: "catppuccin-mocha", name: "Catppuccin Mocha",
            background: UIColor(hex: 0x1E1E2E), text: UIColor(hex: 0xCDD6F4), comment: UIColor(hex: 0x6C7086),
            string: UIColor(hex: 0xA6E3A1), number: UIColor(hex: 0xFAB387), keyword: UIColor(hex: 0xCBA6F7),
            variable: UIColor(hex: 0xF38BA8), action: UIColor(hex: 0x89B4FA), type: UIColor(hex: 0xF9E2AF), caret: UIColor(hex: 0xF5E0DC)
        )
    }

    // GitHub's dark background is close to the black screen behind the editor, so it gets GitHub's own border color as a frame.
    static var githubDark: EditorTheme {
        EditorTheme(
            id: "github-dark", name: "GitHub Dark",
            background: UIColor(hex: 0x0D1117), text: UIColor(hex: 0xE6EDF3), comment: UIColor(hex: 0x8B949E),
            string: UIColor(hex: 0xA5D6FF), number: UIColor(hex: 0x79C0FF), keyword: UIColor(hex: 0xFF7B72),
            variable: UIColor(hex: 0xFFA657), action: UIColor(hex: 0xD2A8FF), type: UIColor(hex: 0x7EE787), caret: UIColor(hex: 0x2F81F7), border: UIColor(hex: 0x30363D)
        )
    }

    // A pale background would melt into a light screen, so Latte gets a soft frame too.
    static var catppuccinLatte: EditorTheme {
        EditorTheme(
            id: "catppuccin-latte", name: "Catppuccin Latte",
            background: UIColor(hex: 0xEFF1F5), text: UIColor(hex: 0x4C4F69), comment: UIColor(hex: 0x9CA0B0),
            string: UIColor(hex: 0x40A02B), number: UIColor(hex: 0xFE640B), keyword: UIColor(hex: 0x8839EF),
            variable: UIColor(hex: 0xD20F39), action: UIColor(hex: 0x1E66F5), type: UIColor(hex: 0xDF8E1D), caret: UIColor(hex: 0xDC8A78), border: UIColor(hex: 0xCCD0DA)
        )
    }
}

// ===================================
// SETTINGS KEYS
// ===================================

enum EditorSettings {
    static let fontKey = "editorFont"
    static let sizeKey = "editorFontSize"
    static let lightKey = "editorLightTheme"
    static let darkKey = "editorDarkTheme"

    // "system" means SF Mono. Anything else is a PostScript font name chosen in Apple's font picker.
    static let systemFontID = "system"

    // Values saved by the first Settings build, before the font picker existed.
    private static func resolved(_ id: String) -> String {
        ["menlo": "Menlo-Regular", "courierNew": "CourierNewPSMT"][id] ?? id
    }

    static func uiFont(id: String, size: CGFloat) -> UIFont {
        let fallback = UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        let name = resolved(id)
        if name == systemFontID { return fallback }

        // A font that was removed from the phone falls back to SF Mono instead of crashing.
        return UIFont(name: name, size: size) ?? fallback
    }

    static func fontDisplayName(id: String) -> String {
        let name = resolved(id)
        if name == systemFontID { return "SF Mono" }

        return UIFont(name: name, size: 12)?.familyName ?? name
    }

    static let defaultSize = 15.0
    static let sizeRange = 10.0...28.0
    static let defaultThemeID = "default"
    // The beta ships these two: Dracula in light mode, Tomorrow Night Bright (pure black) in dark mode.
    static let defaultLightThemeID = "dracula"
    static let defaultDarkThemeID = "tomorrow-night-bright"

    static func style(fontID: String, size: Double, lightID: String, darkID: String, dark: Bool, premium: Bool) -> EditorStyle {
        let font = uiFont(id: fontID, size: CGFloat(size))

        // A premium theme saved before the paywall existed, or before a refund, drops back to the standard theme instead of staying unlocked.
        let wanted = dark ? darkID : lightID
        let id = premium || PremiumFeatures.themeIsFree(wanted) ? wanted : defaultThemeID
        let theme = EditorTheme.theme(id: id)
        return EditorStyle(font: font, theme: theme)
    }
}

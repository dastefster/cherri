// ===================================
// Editor Themes, Fonts and Settings Keys
// v0.0.3 BUILD 2026-10-16 03:52
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
        [standard, dracula, tomorrowNightBright, oneDark, solarizedDark, solarizedLight, githubLight]
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
            variable: UIColor(hex: 0xD54E53), action: UIColor(hex: 0x7AA6DA), type: UIColor(hex: 0x70C0B1), caret: UIColor(hex: 0xEAEAEA), symbolOverride: UIColor(hex: 0x969896)
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
}

// ===================================
// FONTS
// ===================================

// Only fonts that ship with iOS, so nothing has to be bundled yet.
enum EditorFont: String, CaseIterable, Identifiable {
    case system
    case menlo
    case courierNew

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "SF Mono"
        case .menlo: return "Menlo"
        case .courierNew: return "Courier New"
        }
    }

    func font(size: CGFloat) -> UIFont {
        let fallback = UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        switch self {
        case .system: return fallback
        case .menlo: return UIFont(name: "Menlo-Regular", size: size) ?? fallback
        case .courierNew: return UIFont(name: "CourierNewPSMT", size: size) ?? fallback
        }
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

    static let defaultSize = 15.0
    static let sizeRange = 10.0...28.0
    static let defaultThemeID = "default"
    // The beta ships these two: Dracula in light mode, Tomorrow Night Bright (pure black) in dark mode.
    static let defaultLightThemeID = "dracula"
    static let defaultDarkThemeID = "tomorrow-night-bright"

    static func style(fontID: String, size: Double, lightID: String, darkID: String, dark: Bool) -> EditorStyle {
        let font = (EditorFont(rawValue: fontID) ?? .system).font(size: CGFloat(size))
        let theme = EditorTheme.theme(id: dark ? darkID : lightID)
        return EditorStyle(font: font, theme: theme)
    }
}

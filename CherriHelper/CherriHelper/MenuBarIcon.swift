// ===================================
// Menu Bar Icon
// v0.0.1 BUILD 2026-11-21@12:02
// The cherry shown in the menu bar, drawn as a one-color template shape so macOS tints it to match the other icons.
// dev by @dastefster 🍒🔨
// ===================================

import AppKit


// ===================================
// ICON
// ===================================

enum CherryIcon {
    // Drawn as a vector at menu-bar size, so it stays sharp on every display.
    static let menuBar: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            draw()
            return true
        }
        image.isTemplate = true
        return image
    }()

    static func draw() {
        NSColor.black.set()

        // Two cherries. The left one cuts a thin gap into the right one so they still read as two at small sizes.
        let right = NSBezierPath(ovalIn: NSRect(x: 8.7, y: 0.6, width: 7.8, height: 7.8))
        let left = NSBezierPath(ovalIn: NSRect(x: 1.2, y: 0.9, width: 8.0, height: 8.0))

        right.fill()
        NSGraphicsContext.current?.compositingOperation = .clear
        left.lineWidth = 1.3
        left.stroke()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        left.fill()

        // Stems meeting at the top.
        let stems = NSBezierPath()
        stems.lineWidth = 1.2
        stems.lineCapStyle = .round
        stems.move(to: NSPoint(x: 5.6, y: 8.6))
        stems.curve(to: NSPoint(x: 10.3, y: 15.9), controlPoint1: NSPoint(x: 5.6, y: 12.4), controlPoint2: NSPoint(x: 8.2, y: 14.6))
        stems.move(to: NSPoint(x: 12.2, y: 8.2))
        stems.curve(to: NSPoint(x: 10.3, y: 15.9), controlPoint1: NSPoint(x: 11.8, y: 12.0), controlPoint2: NSPoint(x: 10.9, y: 14.4))
        stems.stroke()

        // Leaf.
        let leaf = NSBezierPath()
        leaf.move(to: NSPoint(x: 10.5, y: 15.8))
        leaf.curve(to: NSPoint(x: 16.8, y: 16.4), controlPoint1: NSPoint(x: 12.0, y: 17.6), controlPoint2: NSPoint(x: 15.0, y: 17.8))
        leaf.curve(to: NSPoint(x: 10.5, y: 15.8), controlPoint1: NSPoint(x: 15.4, y: 13.6), controlPoint2: NSPoint(x: 12.4, y: 13.8))
        leaf.fill()
    }
}

// ===================================
// Code Editor
// v0.0.3 BUILD 2026-10-15 16:33
// Cursor-aware text editor (a UIKit text view inside SwiftUI) so actions and values land where the cursor is, not at the end.
// dev by @dastefster 🍒🔨
// ===================================

import SwiftUI
import UIKit

// ===================================
// EDITOR CONTROLLER
// ===================================

// SwiftUI's TextEditor hides the cursor, so ContentView talks to the UIKit text view through this handle.
final class EditorController {
    weak var textView: UITextView?

    // A whole statement (an action call) goes on its own line below the cursor's line, so a tap mid-line never splits existing code.
    func insertStatement(_ text: String) {
        guard let textView else { return }

        let current = textView.text as NSString
        let location = min(textView.selectedRange.location, current.length)
        let lineRange = current.lineRange(for: NSRange(location: location, length: 0))
        let line = current.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)

        if line.isEmpty {
            // A blank line is just filled in.
            replace(NSRange(location: lineRange.location, length: 0), with: text + "\n")
        } else if lineRange.upperBound > 0 && current.character(at: lineRange.upperBound - 1) == 10 {
            replace(NSRange(location: lineRange.upperBound, length: 0), with: text + "\n")
        } else {
            // Last line with no trailing newline yet.
            replace(NSRange(location: lineRange.upperBound, length: 0), with: "\n" + text + "\n")
        }
    }

    // A single value (like "Top Left") goes exactly at the cursor, with a space after a comma to match how arguments are written.
    func insertInline(_ text: String) {
        guard let textView else { return }

        let current = textView.text as NSString
        let location = min(textView.selectedRange.location, current.length)
        let followsComma = location > 0 && current.character(at: location - 1) == 44

        replaceSelection(with: (followsComma ? " " : "") + text)
    }

    private func replaceSelection(with string: String) {
        guard let textView else { return }

        let current = textView.text as NSString
        let location = min(textView.selectedRange.location, current.length)
        let length = min(textView.selectedRange.length, current.length - location)

        replace(NSRange(location: location, length: length), with: string)
    }

    private func replace(_ range: NSRange, with string: String) {
        guard let textView else { return }

        let current = textView.text as NSString

        textView.text = current.replacingCharacters(in: range, with: string)
        textView.selectedRange = NSRange(location: range.location + (string as NSString).length, length: 0)
        textView.scrollRangeToVisible(textView.selectedRange)

        // Setting .text in code does not notify the delegate, so the SwiftUI binding is synced by hand.
        textView.delegate?.textViewDidChange?(textView)

        refocus()
    }

    // The picker sheet is still animating away when an insert happens, so the keyboard returns a beat later.
    private func refocus() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            self?.textView?.becomeFirstResponder()
        }
    }
}

// ===================================
// EDITOR VIEW
// ===================================

struct CodeEditor: UIViewRepresentable {
    @Binding var text: String
    let controller: EditorController

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator

        let base = UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
        textView.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: base)
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = .label
        textView.backgroundColor = .secondarySystemBackground
        textView.layer.cornerRadius = 10
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive

        // Code, not prose: smart quotes would turn "text" into curly quotes the compiler rejects.
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.spellCheckingType = .no
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no

        textView.text = text
        textView.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        controller.textView = textView

        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.text = $text

        // Only touch the text when it really differs, otherwise the cursor jumps while typing.
        if uiView.text != text {
            uiView.text = text
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
        }
    }
}

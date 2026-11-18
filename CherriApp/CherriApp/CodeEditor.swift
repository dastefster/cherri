// ===================================
// Code Editor
// v0.0.11 BUILD 2026-11-17 11:25
// Cursor-aware text editor (a UIKit text view inside SwiftUI) so actions and values land where the cursor is, not at the end. A quick swipe down on the editor dismisses the keyboard. Undo and redo buttons ride above the keyboard and shaking the phone asks to undo, like everywhere else in iOS. The editor keeps its own undo history: a line, a paste or a picker insert is one step.
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
    let history = EditHistory()

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

        // The history applies the edit and records it as one undo step, so a whole picker insert undoes in one tap.
        history.replaceBlock(range, with: string, in: textView)
        textView.scrollRangeToVisible(textView.selectedRange)

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
// EDIT HISTORY
// ===================================

// The system merges typed characters by rules we can't see or change, so the editor keeps its own undo history.
// Each step stores only what changed (where, what was removed, what was added), which stays small even in a very long file.
// Steps: a picker insert or paste is one step. Typing merges within a line and the Return closes it, so a line is one step.
// Typing also breaks after a pause, when the cursor jumps, or when switching between typing and deleting. Backspacing merges the same way but never across a line break.
final class EditHistory {
    private enum Kind {
        case typing, deleting, block
    }

    private struct Step {
        var location: Int
        var removed: String
        var inserted: String
        var selectionBefore: NSRange
        var selectionAfter: NSRange
        var kind: Kind
        var closed: Bool
        var lastEdit: TimeInterval
    }

    private struct Pending {
        let range: NSRange
        let removed: String
        let replacement: String
        let selectionBefore: NSRange
        let time: TimeInterval
    }

    // Typing stops merging after this long without a keystroke.
    private let pause: TimeInterval = 1.0
    private let limit = 1000

    private var undoSteps: [Step] = []
    private var redoSteps: [Step] = []
    private var pending: Pending?

    // True while undo, redo or a picker insert changes the text, so the text view's own delegate calls aren't recorded a second time.
    private var isApplying = false

    var canUndo: Bool { !undoSteps.isEmpty }
    var canRedo: Bool { !redoSteps.isEmpty }

    // New or replaced code (opening a shortcut, importing, restoring) must not be undoable back into the old text.
    func reset() {
        undoSteps.removeAll()
        redoSteps.removeAll()
        pending = nil
    }

    // ===================================
    // RECORDING TYPED EDITS
    // ===================================

    // The text view reports an edit before it happens (what is being replaced) and again after it (where the cursor ended up).
    func willChange(range: NSRange, replacement: String, in textView: UITextView) {
        guard !isApplying else { return }

        let current = textView.text as NSString
        guard range.location >= 0, range.location + range.length <= current.length else {
            pending = nil
            return
        }

        pending = Pending(
            range: range,
            removed: current.substring(with: range),
            replacement: replacement,
            selectionBefore: textView.selectedRange,
            time: ProcessInfo.processInfo.systemUptime
        )
    }

    func didChange(selection: NSRange) {
        guard !isApplying, let edit = pending else { return }
        pending = nil

        record(
            location: edit.range.location,
            removed: edit.removed,
            inserted: edit.replacement,
            selectionBefore: edit.selectionBefore,
            selectionAfter: selection,
            time: edit.time,
            asBlock: false
        )
    }

    // ===================================
    // RECORDING BLOCK EDITS
    // ===================================

    // A picker insert: applied here so it is recorded as exactly one step that never merges with typing.
    func replaceBlock(_ range: NSRange, with text: String, in textView: UITextView) {
        let current = textView.text as NSString
        guard range.location >= 0, range.location + range.length <= current.length else { return }

        let selectionAfter = NSRange(location: range.location + (text as NSString).length, length: 0)
        record(
            location: range.location,
            removed: current.substring(with: range),
            inserted: text,
            selectionBefore: textView.selectedRange,
            selectionAfter: selectionAfter,
            time: ProcessInfo.processInfo.systemUptime,
            asBlock: true
        )
        apply(range, with: text, selection: selectionAfter, in: textView)
    }

    // ===================================
    // SHAKE CONFIRMATION
    // ===================================

    private static func label(for kind: Kind) -> String {
        switch kind {
        case .typing:
            return "Typing"
        case .deleting:
            return "Delete"
        case .block:
            return "Edit"
        }
    }

    // Shaking asks first, like everywhere else in iOS, so a stray shake never silently rewrites the code.
    // With something to undo the title is "Undo ..." and, when something can also be redone, a "Redo ..." button joins it. With nothing to undo it offers just the redo.
    func promptShake(in textView: UITextView) {
        guard let title = undoTitle ?? redoTitle else { return }

        var top = textView.window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        // A second shake while the prompt is up must not stack another one.
        guard let presenter = top, !(presenter is UIAlertController) else { return }

        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)

        if canUndo {
            alert.addAction(UIAlertAction(title: "Undo", style: .default) { [weak self, weak textView] _ in
                guard let self, let textView else { return }

                self.undo(in: textView)
                (textView.inputAccessoryView as? UndoRedoBar)?.refresh()
            })
        }
        if let redoTitle {
            // Alone it reads "Redo"; next to Undo it carries the full "Redo Typing" so the two buttons can't be mixed up.
            alert.addAction(UIAlertAction(title: canUndo ? redoTitle : "Redo", style: .default) { [weak self, weak textView] _ in
                guard let self, let textView else { return }

                self.redo(in: textView)
                (textView.inputAccessoryView as? UndoRedoBar)?.refresh()
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        presenter.present(alert, animated: true)
    }

    private var undoTitle: String? {
        undoSteps.last.map { "Undo " + Self.label(for: $0.kind) }
    }

    private var redoTitle: String? {
        redoSteps.last.map { "Redo " + Self.label(for: $0.kind) }
    }

    // ===================================
    // STEP BOOKKEEPING
    // ===================================

    private func classify(removed: String, inserted: String) -> Kind {
        if removed.isEmpty && inserted.utf16.count == 1 {
            return .typing
        }
        // One or two UTF-16 units covers a backspace, including an emoji. Anything bigger (a cut, a selection) is its own step.
        if inserted.isEmpty && !removed.isEmpty && removed.utf16.count <= 2 {
            return .deleting
        }

        return .block
    }

    private func canMerge(_ step: Step, kind: Kind, location: Int, removed: String, time: TimeInterval) -> Bool {
        guard !step.closed, step.kind == kind, time - step.lastEdit <= pause else { return false }

        switch kind {
        case .typing:
            // Only when this keystroke lands exactly where the last one ended, so a cursor jump starts a new step.
            return location == step.location + (step.inserted as NSString).length
        case .deleting:
            guard !removed.contains("\n") else { return false }

            let backspace = location + (removed as NSString).length == step.location
            let forwardDelete = location == step.location
            return backspace || forwardDelete
        case .block:
            return false
        }
    }

    private func record(location: Int, removed: String, inserted: String, selectionBefore: NSRange, selectionAfter: NSRange, time: TimeInterval, asBlock: Bool) {
        guard !removed.isEmpty || !inserted.isEmpty else { return }

        // A new edit always ends the redo trail.
        redoSteps.removeAll()

        let kind = asBlock ? Kind.block : classify(removed: removed, inserted: inserted)

        if kind != .block,
           let lastIndex = undoSteps.indices.last,
           canMerge(undoSteps[lastIndex], kind: kind, location: location, removed: removed, time: time) {
            var step = undoSteps[lastIndex]

            if kind == .typing {
                step.inserted += inserted
            } else if location == step.location {
                step.removed += removed
            } else {
                step.location = location
                step.removed = removed + step.removed
            }

            step.selectionAfter = selectionAfter
            step.lastEdit = time
            // The Return belongs to the line it ends, and nothing merges into the next one.
            if inserted == "\n" { step.closed = true }
            undoSteps[lastIndex] = step
            return
        }

        undoSteps.append(Step(
            location: location,
            removed: removed,
            inserted: inserted,
            selectionBefore: selectionBefore,
            selectionAfter: selectionAfter,
            kind: kind,
            closed: kind == .block || inserted == "\n" || removed.contains("\n"),
            lastEdit: time
        ))

        if undoSteps.count > limit {
            undoSteps.removeFirst()
        }
    }

    // ===================================
    // UNDO AND REDO
    // ===================================

    @discardableResult
    func undo(in textView: UITextView) -> Bool {
        guard var step = undoSteps.popLast() else { return false }

        let range = NSRange(location: step.location, length: (step.inserted as NSString).length)
        guard matches(range, step.inserted, in: textView) else {
            // The text no longer lines up with the history, so undoing could corrupt the code. Starting over is safer.
            reset()
            return false
        }

        step.closed = true
        redoSteps.append(step)
        closeNewestStep()
        apply(range, with: step.removed, selection: step.selectionBefore, in: textView)
        return true
    }

    @discardableResult
    func redo(in textView: UITextView) -> Bool {
        guard var step = redoSteps.popLast() else { return false }

        let range = NSRange(location: step.location, length: (step.removed as NSString).length)
        guard matches(range, step.removed, in: textView) else {
            reset()
            return false
        }

        step.closed = true
        undoSteps.append(step)
        apply(range, with: step.inserted, selection: step.selectionAfter, in: textView)
        return true
    }

    // After an undo the cursor is somewhere else, so the next keystroke must start a new step.
    private func closeNewestStep() {
        if let lastIndex = undoSteps.indices.last {
            undoSteps[lastIndex].closed = true
        }
    }

    private func matches(_ range: NSRange, _ expected: String, in textView: UITextView) -> Bool {
        let current = textView.text as NSString
        return range.location >= 0
            && range.location + range.length <= current.length
            && current.substring(with: range) == expected
    }

    private func apply(_ range: NSRange, with text: String, selection: NSRange, in textView: UITextView) {
        isApplying = true
        defer { isApplying = false }

        guard let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
              let end = textView.position(from: start, offset: range.length),
              let textRange = textView.textRange(from: start, to: end) else { return }

        textView.replace(textRange, withText: text)

        let length = (textView.text as NSString).length
        let location = min(selection.location, length)
        textView.selectedRange = NSRange(location: location, length: min(selection.length, length - location))
        textView.scrollRangeToVisible(textView.selectedRange)

        // Programmatic edits don't reliably notify the delegate, so the SwiftUI binding is synced by hand.
        textView.delegate?.textViewDidChange?(textView)
    }
}

// ===================================
// UNDO / REDO BAR
// ===================================

// Sits above the keyboard. The buttons dim on their own when there is nothing to undo or redo.
final class UndoRedoBar: UIToolbar {
    private weak var textView: UITextView?
    private let history: EditHistory
    private let undoItem: UIBarButtonItem
    private let redoItem: UIBarButtonItem

    init(textView: UITextView, history: EditHistory) {
        self.textView = textView
        self.history = history
        undoItem = UIBarButtonItem(image: UIImage(systemName: "arrow.uturn.backward"), primaryAction: nil)
        redoItem = UIBarButtonItem(image: UIImage(systemName: "arrow.uturn.forward"), primaryAction: nil)

        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 44))
        autoresizingMask = .flexibleWidth
        undoItem.accessibilityLabel = "Undo"
        redoItem.accessibilityLabel = "Redo"
        items = [undoItem, redoItem, UIBarButtonItem.flexibleSpace()]

        undoItem.primaryAction = UIAction { [weak self] _ in self?.undo() }
        redoItem.primaryAction = UIAction { [weak self] _ in self?.redo() }
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func undo() {
        if let textView { history.undo(in: textView) }
        refresh()
    }

    func redo() {
        if let textView { history.redo(in: textView) }
        refresh()
    }

    func refresh() {
        undoItem.isEnabled = history.canUndo
        redoItem.isEnabled = history.canRedo
    }

    func restyle(_ theme: EditorTheme) {
        let appearance = UIToolbarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = theme.background
        standardAppearance = appearance
        compactAppearance = appearance
        tintColor = theme.text
    }
}

// ===================================
// EDITOR VIEW
// ===================================

struct CodeEditor: UIViewRepresentable {
    @Binding var text: String
    let controller: EditorController
    let style: EditorStyle

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, style: style, history: controller.history)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = FramedTextView()
        textView.delegate = context.coordinator

        // The font size now comes from Settings, so Dynamic Type scaling is off.
        textView.adjustsFontForContentSizeCategory = false
        textView.layer.cornerRadius = 10
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive

        // .interactive only dismisses once the finger reaches the keyboard, which is far below a short editor, so a plain swipe down did nothing.
        let swipeDown = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.dismissKeyboard))
        swipeDown.direction = .down
        swipeDown.delegate = context.coordinator
        textView.addGestureRecognizer(swipeDown)

        // Code, not prose: smart quotes would turn "text" into curly quotes the compiler rejects.
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.spellCheckingType = .no
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no

        let history = controller.history
        history.reset()
        textView.inputAccessoryView = UndoRedoBar(textView: textView, history: history)

        // The system's own shake prompt is off because the system undo manager is, so the history shows the same "Undo Typing" confirmation itself.
        textView.onShake = { [weak textView] in
            guard let textView else { return }

            history.promptShake(in: textView)
        }

        textView.text = text
        textView.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        controller.textView = textView

        context.coordinator.restyle(textView)

        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.style = style

        // Only touch the text when it really differs, otherwise the cursor jumps while typing.
        var needsStyle = context.coordinator.appliedStyleKey != style.key
        if uiView.text != text {
            uiView.text = text
            // Replaced from outside (new shortcut, import, restore), so the old edits no longer apply.
            controller.history.reset()
            (uiView.inputAccessoryView as? UndoRedoBar)?.refresh()
            needsStyle = true
        }

        if needsStyle {
            context.coordinator.restyle(uiView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var text: Binding<String>
        var style: EditorStyle
        var appliedStyleKey = ""
        let history: EditHistory

        init(text: Binding<String>, style: EditorStyle, history: EditHistory) {
            self.text = text
            self.style = style
            self.history = history
        }

        @objc func dismissKeyboard(_ gesture: UISwipeGestureRecognizer) {
            // Checked again here because a swipe only fires when the finger lifts, and by then a fast downward drag of a selection handle has already made a selection. Dropping the keyboard would wipe it.
            if let textView = gesture.view as? UITextView, textView.selectedRange.length > 0 { return }

            gesture.view?.endEditing(true)
        }

        // Only count the swipe when the text is already at the top. Otherwise a quick flick up through long code would also drop the keyboard. It also stays out of the way while text is selected, since dragging a selection handle down looks just like a swipe down.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let textView = gestureRecognizer.view as? UITextView else { return true }
            guard textView.selectedRange.length == 0 else { return false }

            return textView.contentOffset.y <= -textView.adjustedContentInset.top + 1
        }

        // The text view's own scrolling and cursor gestures have to keep working next to the swipe.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        func restyle(_ textView: UITextView) {
            CherriHighlighter.style(textView, with: style)
            (textView.inputAccessoryView as? UndoRedoBar)?.restyle(style.theme)
            appliedStyleKey = style.key
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
            history.willChange(range: range, replacement: replacement, in: textView)
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            history.didChange(selection: textView.selectedRange)
            text.wrappedValue = textView.text

            CherriHighlighter.apply(to: textView.textStorage, style: style)
            textView.typingAttributes = [.font: style.font, .foregroundColor: style.theme.text]

            (textView.inputAccessoryView as? UndoRedoBar)?.refresh()
        }
    }
}

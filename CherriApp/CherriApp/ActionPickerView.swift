// ===================================
// Action Picker
// v0.0.16 BUILD 2026-11-18 16:58
// Searchable list of every Cherri action. Tapping one opens its fill-in form (or inserts it straight away if it has no parameters), swiping left quick-inserts starter code, and the info button opens its help. A highlighted card at the top opens the shortcut's name, color and icon editor.
// dev by @dastefster 🍒🔨
// ===================================

import SwiftUI

// ===================================
// PICKER
// ===================================

struct ActionPickerView: View {
    let source: String
    // Only the code above where an inserted statement will land, for the variable menus. Nil means use all of the source.
    var codeAbove: String? = nil
    let onInsert: (String) -> Void
    let onInsertValue: (String) -> Void
    let onStyle: (ShortcutStyle) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var catalog: ActionCatalog?
    @State private var loadError: String?
    @State private var query = ""
    @State private var sheet: PickerSheet?
    // The picker's copy of the source is a snapshot, so the card shows a change made from here straight away.
    @State private var styleOverride: ShortcutStyle?

    var body: some View {
        NavigationStack {
            Group {
                if let catalog {
                    list(for: catalog)
                } else if let loadError {
                    Text(loadError)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.red)
                        .padding()
                } else {
                    ProgressView("Loading actions…")
                }
            }
            .navigationTitle("Actions")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .searchable(text: $query, prompt: "Search actions")
        }
        .dismissesKeyboard()
        .task { await load() }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .help(let action):
                ActionHelpView(action: action) { value in
                    onInsertValue(value)
                    dismiss()
                }
            case .form(let action):
                ActionFormView(action: action, source: source, codeAbove: codeAbove ?? source) { text in
                    onInsert(text)
                    dismiss()
                }
            case .style:
                ShortcutStyleSheet(style: currentStyle) { newStyle in
                    styleOverride = newStyle
                    onStyle(newStyle)
                }
            }
        }
    }

    // ===================================
    // LIST
    // ===================================

    private func list(for catalog: ActionCatalog) -> some View {
        let search = query.trimmingCharacters(in: .whitespaces).lowercased()
        let sections = catalog.categories.compactMap { category -> (CatalogCategory, [CatalogAction])? in
            let matches = catalog.actions.filter { $0.category == category.id && !ActionVariants.isAlternate($0.name) && (search.isEmpty || $0.matches(search)) }
            return matches.isEmpty ? nil : (category, matches)
        }

        return List {
            if showsStyleCard(for: search) {
                Section { styleCard }
            }

            ForEach(sections, id: \.0.id) { section in
                Section(section.0.title) {
                    ForEach(section.1) { action in
                        HStack(spacing: 12) {
                            Button {
                                choose(action)
                            } label: {
                                row(for: action)
                            }
                            .buttonStyle(.plain)

                            Button {
                                present(.help(action))
                            } label: {
                                Image(systemName: "info.circle")
                                    .font(.title3)
                                    .foregroundStyle(.tint)
                            }
                            .buttonStyle(.plain)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Quick Insert") {
                                onInsert(action.insertionText)
                                dismiss()
                            }
                            .tint(.accentColor)
                        }
                    }
                }
            }
        }
    }

    // ===================================
    // STYLE CARD
    // ===================================

    private var currentStyle: ShortcutStyle {
        styleOverride ?? ShortcutStyleEditor.parse(source)
    }

    // Shown on the plain list, and when the search is heading toward name, color or icon.
    private func showsStyleCard(for search: String) -> Bool {
        guard !search.isEmpty else { return true }
        return ["name", "color", "colour", "icon", "glyph", "style"].contains { $0.hasPrefix(search) }
    }

    // Filled and outlined in the accent color so it reads as different from the action rows in both light and dark mode.
    private var styleCard: some View {
        let style = currentStyle

        return Button {
            present(.style)
        } label: {
            HStack(spacing: 12) {
                ShortcutIconTile(colorName: style.color, glyphName: style.glyph, size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Name, color and icon")
                        .font(.headline)
                    Text(style.displayName)
                        .font(.subheadline)
                        .foregroundStyle(Color.helperText)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.accentColor.opacity(colorScheme == .dark ? 0.12 : 0.18)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
    }

    private func row(for action: CatalogAction) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(action.displayName)
                .font(.body)
            Text(action.listSubtitle)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color.helperText)
            if let description = action.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(Color.helperText)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    // ===================================
    // CHOOSE
    // ===================================

    // The search field keeps focus when a sheet opens over it, and a sheet with no text field of its own has nothing that can dismiss that keyboard, so it is dropped first.
    private func present(_ destination: PickerSheet) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        sheet = destination
    }

    // An action with parameters opens its form; one without is inserted straight away.
    private func choose(_ action: CatalogAction) {
        if action.params.isEmpty {
            onInsert(action.insertionText)
            dismiss()
        } else {
            present(.form(action))
        }
    }

    // ===================================
    // LOAD
    // ===================================

    private func load() async {
        guard catalog == nil else { return }

        do {
            catalog = try await Task.detached(priority: .userInitiated) {
                try ActionCatalog.load().addingVariableActions()
            }.value
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// ===================================
// SHEETS
// ===================================

// One sheet slot for both destinations, because two item sheets on the same view fight each other.
private enum PickerSheet: Identifiable {
    case help(CatalogAction)
    case form(CatalogAction)
    case style

    var id: String {
        switch self {
        case .help(let action):
            return "help-\(action.name)"
        case .form(let action):
            return "form-\(action.name)"
        case .style:
            return "style"
        }
    }
}


// ===================================
// KEYBOARD DISMISSAL
// ===================================

// While the keyboard is up, a downward drag should bring it down instead of dragging the whole sheet away, and a tap on anything that is not a text input should drop it. Once the keyboard is down the sheet closes with a swipe as usual.
private struct KeyboardDismissing: ViewModifier {
    @State private var keyboardUp = false

    func body(content: Content) -> some View {
        content
            .interactiveDismissDisabled(keyboardUp)
            .scrollDismissesKeyboard(.interactively)
            .background(TapToDismissKeyboard())
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                keyboardUp = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardUp = false
            }
    }
}

extension View {
    func dismissesKeyboard() -> some View {
        modifier(KeyboardDismissing())
    }
}

// A control that edits a text field (like the plus/minus button on a number) reports its frame here, so tapping it does not drop the keyboard the person is still typing on.
enum KeyboardKeepers {
    static var frame: CGRect = .zero
}

// SwiftUI has no "tap anywhere else" hook, so this watches taps on the window. It never swallows a tap (buttons and toggles still do their job), and it ignores taps on a text field or text view so tapping from one field to another just moves focus.
private struct TapToDismissKeyboard: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: AnchorView, context: Context) {}

    static func dismantleUIView(_ uiView: AnchorView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class AnchorView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window {
                coordinator?.attach(to: window)
            } else {
                coordinator?.detach()
            }
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private let recognizer = UITapGestureRecognizer()
        private weak var window: UIWindow?

        override init() {
            super.init()
            recognizer.addTarget(self, action: #selector(tapped))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
        }

        func attach(to window: UIWindow) {
            guard self.window !== window else { return }
            detach()
            window.addGestureRecognizer(recognizer)
            self.window = window
        }

        func detach() {
            window?.removeGestureRecognizer(recognizer)
            window = nil
        }

        @objc private func tapped() {
            window?.endEditing(true)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            // A little slack around the frame, because fingers land on edges.
            if KeyboardKeepers.frame != .zero, KeyboardKeepers.frame.insetBy(dx: -6, dy: -6).contains(touch.location(in: nil)) {
                return false
            }

            var view = touch.view
            while let current = view {
                if current is UITextField || current is UITextView { return false }
                view = current.superview
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

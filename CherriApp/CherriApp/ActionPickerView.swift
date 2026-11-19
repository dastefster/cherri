// ===================================
// Action Picker
// v0.0.21 BUILD 2026-11-18 19:42
// Searchable list of every Cherri action. Tapping one opens its fill-in form (or inserts it straight away if it has no parameters), swiping left quick-adds starter code, swiping right stars it as a favorite, and the info button opens its help. Favorites sit in their own gold section at the top and can be reordered. A highlighted card at the top opens the shortcut's name, color and icon editor.
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
    @StateObject private var favorites = FavoritesStore()
    @State private var editMode: EditMode = .inactive
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
                ToolbarItem(placement: .confirmationAction) {
                    if showsFavoritesEdit {
                        Button {
                            withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                        } label: {
                            // Without this the two titles cross-fade on top of each other while the button resizes.
                            Text(editMode.isEditing ? "Done" : "Edit Favorites")
                                .contentTransition(.identity)
                                .transaction { $0.animation = nil }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search actions")
            // Reordering only makes sense on the plain list, and it ends on its own once the last favorite is gone.
            .onChange(of: query) { _, _ in editMode = .inactive }
            .onChange(of: favorites.names.isEmpty) { _, empty in
                if empty { editMode = .inactive }
            }
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

    // How far a favorite's card sits inside its row, on every side. Also the gap between neighbors is twice this.
    private static let favoriteCardInset: CGFloat = 6

    // The Edit button only shows when there is a favorite on screen to edit.
    private var showsFavoritesEdit: Bool {
        guard let catalog, query.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return favorites.names.contains { name in catalog.actions.contains { $0.name == name } }
    }

    private func list(for catalog: ActionCatalog) -> some View {
        let search = query.trimmingCharacters(in: .whitespaces).lowercased()
        let sections = catalog.categories.compactMap { category -> (CatalogCategory, [CatalogAction])? in
            let matches = catalog.actions.filter { $0.category == category.id && !ActionVariants.isAlternate($0.name) && (search.isEmpty || $0.matches(search)) }
            return matches.isEmpty ? nil : (category, matches)
        }

        // Hidden while searching so nothing shows up twice. Names the catalog no longer has stay saved but aren't listed.
        let favoriteActions = search.isEmpty
            ? favorites.names.compactMap { name in catalog.actions.first { $0.name == name && !ActionVariants.isAlternate($0.name) } }
            : []

        return List {
            if showsStyleCard(for: search) {
                Section { styleCard }
            }

            if !favoriteActions.isEmpty {
                Section {
                    ForEach(favoriteActions) { action in
                        actionRow(for: action)
                            // Matches the inset on the card behind it, so the text keeps the same distance from the card's edge.
                            .padding(.horizontal, Self.favoriteCardInset)
                            .padding(.vertical, Self.favoriteCardInset)
                            // Swipe-to-delete would fight Quick Add, so removing is only offered while editing.
                            .deleteDisabled(!editMode.isEditing)
                    }
                    .onMove { offsets, destination in
                        favorites.move(visible: favoriteActions.map(\.name), from: offsets, to: destination)
                    }
                    .onDelete { offsets in
                        favorites.remove(visible: favoriteActions.map(\.name), at: offsets)
                    }
                    // Each favorite is its own rounded card. The list clips a row's outer corners by its position, with a bigger radius than ours, and a lifted row keeps that clip. The card sits a few points inside the row so the clip never reaches it, which leaves all four corners the same.
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(FavoritesStore.rowBackground)
                            .padding(Self.favoriteCardInset)
                    )
                    .listRowSeparator(.hidden)
                } header: {
                    // The same tile as the Settings rows, and a title in the normal text color so it stays readable in light mode.
                    HStack(spacing: 10) {
                        SettingsIcon(symbol: "star.fill", color: FavoritesStore.tint, weight: .bold)
                        Text("Favorites")
                            .font(.title3.bold())
                            // An explicit color, because a section header turns .primary into a muted gray.
                            .foregroundStyle(Color(UIColor.label))
                    }
                    .textCase(nil)
                }
            }

            ForEach(sections, id: \.0.id) { section in
                Section(section.0.title) {
                    ForEach(section.1) { action in
                        actionRow(for: action)
                    }
                }
            }
        }
        .environment(\.editMode, $editMode)
        // White rows on the pale default page barely show their edges in light mode, so the page behind them is a step darker there.
        .scrollContentBackground(colorScheme == .light ? .hidden : .automatic)
        .background(colorScheme == .light ? Color(UIColor.systemGray5) : Color.clear)
        .sensoryFeedback(.selection, trigger: favorites.names)
    }

    // ===================================
    // ACTION ROW
    // ===================================

    // Tapping only ever inserts. Starring lives on a swipe and the long-press menu, away from anything small to miss.
    private func actionRow(for action: CatalogAction) -> some View {
        let isFavorite = favorites.contains(action.name)
        let editing = editMode.isEditing

        return HStack(spacing: 12) {
            Button {
                if !editing { choose(action) }
            } label: {
                row(for: action)
            }
            .buttonStyle(.plain)

            if !editing {
                Button {
                    present(.help(action))
                } label: {
                    Image(systemName: "info.circle")
                        .font(.title3)
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
            }
        }
        .swipeActions(edge: .trailing) {
            // A glyph in the label is what makes iOS draw it as a round button with the title underneath, like Favorite.
            Button {
                onInsert(action.insertionText)
                dismiss()
            } label: {
                Label("Quick Add", systemImage: "bolt.fill")
            }
            .tint(.accentColor)
        }
        // No full swipe, so a long drag can't star something by accident.
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                favorites.toggle(action.name)
            } label: {
                Label(isFavorite ? "Unfavorite" : "Favorite", systemImage: isFavorite ? "star.slash" : "star.fill")
            }
            .tint(FavoritesStore.tint)
        }
        .contextMenu {
            Button {
                favorites.toggle(action.name)
            } label: {
                Label(isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: isFavorite ? "star.slash" : "star")
            }

            Button {
                present(.help(action))
            } label: {
                Label("Help", systemImage: "info.circle")
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

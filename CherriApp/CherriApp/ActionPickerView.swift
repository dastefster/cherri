// ===================================
// Action Picker
// v0.0.8 BUILD 2026-11-07 14:15
// Searchable list of every Cherri action. Tapping one opens its fill-in form (or inserts it straight away if it has no parameters), swiping left quick-inserts starter code, and the info button opens its help. A highlighted card at the top opens the shortcut's name, color and icon editor.
// dev by @dastefster 🍒🔨
// ===================================

import SwiftUI

// ===================================
// PICKER
// ===================================

struct ActionPickerView: View {
    let source: String
    let onInsert: (String) -> Void
    let onInsertValue: (String) -> Void
    let onStyle: (ShortcutStyle) -> Void

    @Environment(\.dismiss) private var dismiss
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .searchable(text: $query, prompt: "Search actions")
        }
        .task { await load() }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .help(let action):
                ActionHelpView(action: action) { value in
                    onInsertValue(value)
                    dismiss()
                }
            case .form(let action):
                ActionFormView(action: action, source: source) { text in
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
                                sheet = .help(action)
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
                            .tint(.blue)
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
            sheet = .style
        } label: {
            HStack(spacing: 12) {
                ShortcutIconTile(colorName: style.color, glyphName: style.glyph, size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Name, color and icon")
                        .font(.headline)
                    Text(style.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.accentColor.opacity(0.12)))
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
            Text(action.name)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            if let description = action.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    // ===================================
    // CHOOSE
    // ===================================

    // An action with parameters opens its form; one without is inserted straight away.
    private func choose(_ action: CatalogAction) {
        if action.params.isEmpty {
            onInsert(action.insertionText)
            dismiss()
        } else {
            sheet = .form(action)
        }
    }

    // ===================================
    // LOAD
    // ===================================

    private func load() async {
        guard catalog == nil else { return }

        do {
            catalog = try await Task.detached(priority: .userInitiated) {
                try ActionCatalog.load()
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

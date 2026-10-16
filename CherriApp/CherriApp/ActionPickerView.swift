// ===================================
// Action Picker
// v0.0.7 BUILD 2026-10-15 22:25
// Searchable list of every Cherri action. Tapping one opens its fill-in form (or inserts it straight away if it has no parameters), swiping left quick-inserts starter code, and the info button opens its help.
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

    @Environment(\.dismiss) private var dismiss
    @State private var catalog: ActionCatalog?
    @State private var loadError: String?
    @State private var query = ""
    @State private var sheet: PickerSheet?

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

    var id: String {
        switch self {
        case .help(let action):
            return "help-\(action.name)"
        case .form(let action):
            return "form-\(action.name)"
        }
    }
}

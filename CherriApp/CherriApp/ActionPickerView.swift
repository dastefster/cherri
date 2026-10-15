// ===================================
// Action Picker
// v0.0.3 BUILD 2026-10-15 15:30
// Searchable list of every Cherri action. Tapping one hands starter code back to the editor; the info button opens its help, where an allowed value can be tapped to insert it.
// dev by @dastefster 🍒🔨
// ===================================

import SwiftUI

// ===================================
// PICKER
// ===================================

struct ActionPickerView: View {
    let onInsert: (String) -> Void
    let onInsertValue: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var catalog: ActionCatalog?
    @State private var loadError: String?
    @State private var query = ""
    @State private var helpAction: CatalogAction?

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
        .sheet(item: $helpAction) { action in
            ActionHelpView(action: action) { value in
                onInsertValue(value)
                dismiss()
            }
        }
    }

    // ===================================
    // LIST
    // ===================================

    private func list(for catalog: ActionCatalog) -> some View {
        let search = query.trimmingCharacters(in: .whitespaces).lowercased()
        let sections = catalog.categories.compactMap { category -> (CatalogCategory, [CatalogAction])? in
            let matches = catalog.actions.filter { $0.category == category.id && (search.isEmpty || $0.matches(search)) }
            return matches.isEmpty ? nil : (category, matches)
        }

        return List {
            ForEach(sections, id: \.0.id) { section in
                Section(section.0.title) {
                    ForEach(section.1) { action in
                        HStack(spacing: 12) {
                            Button {
                                onInsert(action.insertionText)
                                dismiss()
                            } label: {
                                row(for: action)
                            }
                            .buttonStyle(.plain)

                            Button {
                                helpAction = action
                            } label: {
                                Image(systemName: "info.circle")
                                    .font(.title3)
                                    .foregroundStyle(.tint)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func row(for action: CatalogAction) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(action.name)
                .font(.system(.body, design: .monospaced))
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

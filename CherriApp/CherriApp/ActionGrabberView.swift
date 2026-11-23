// ===================================
// Action Grabber View
// v0.0.5 BUILD 2026-11-23 09:30
// Lists every action in a downloaded shortcut so the person can tap the ones they want, then copies them to the clipboard to paste into another shortcut in the Shortcuts app. Tapping the If, Repeat or Menu line itself takes the whole block; tapping an action inside one takes just that action. If the selection reads from actions that aren't selected, it says so and offers to include them, so a paste never lands with broken variable links. A search box narrows the list for long shortcuts, and Select Range takes everything between two taps (blocks it touches come in whole).
// dev by @dastefster 🍒🔨
// ===================================

import SwiftUI

// ===================================
// GRABBER SCREEN
// ===================================

struct ActionGrabberView: View {
    let fetched: ShortcutImporter.Fetched

    @Environment(\.dismiss) private var dismiss
    @State private var list: GrabList?
    @State private var loadError: String?
    @State private var selection: Set<Int> = []
    // Set after a copy; cleared as soon as the selection changes, since the clipboard no longer matches it.
    @State private var copiedCount: Int?
    @State private var copyFailed = false
    @State private var query = ""
    // Select Range works in two taps: this is on from choosing it until the second tap, and rangeStart holds the first.
    @State private var choosingRange = false
    @State private var rangeStart: Int?

    // ===================================
    // BODY
    // ===================================

    var body: some View {
        NavigationStack {
            Group {
                if let list {
                    content(list)
                } else if let loadError {
                    Text(loadError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding()
                } else {
                    ProgressView("Reading actions…")
                }
            }
            .navigationTitle(fetched.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                if let list {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Select Range", systemImage: "arrow.up.and.down.text.horizontal") {
                                choosingRange = true
                                rangeStart = nil
                            }
                            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                                let matches = list.rows(matching: query).map(\.index)
                                Button("Select All Matches", systemImage: "text.magnifyingglass") { change(selection.union(matches)) }
                                    .disabled(matches.isEmpty)
                            }
                            Button("Select All", systemImage: "checkmark.circle") { change(Set(list.rows.map(\.index))) }
                            Button("Select None", systemImage: "circle") { change([]) }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .task { await load() }
            .searchable(text: $query, prompt: "Search actions")
        }
    }

    // ===================================
    // LIST
    // ===================================

    @ViewBuilder
    private func content(_ list: GrabList) -> some View {
        let missing = list.missingDependencies(for: selection)
        let shown = list.rows(matching: query)

        List {
            Section {
                Text("Tap the actions you want to copy. Tapping the If, Repeat or Menu line itself takes the whole block. Tapping an action inside one takes just that action.")
                    .font(.footnote)
                    .foregroundStyle(Color.helperText)
            }

            if choosingRange {
                rangeSection
            }

            if !missing.isEmpty {
                dependencySection(list, missing: missing)
            }

            Section {
                ForEach(shown) { row in
                    Button { tap(row, in: list) } label: {
                        rowLabel(row, selected: selection.contains(row.index), isRangeStart: rangeStart == row.index)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .overlay {
            if shown.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .safeAreaInset(edge: .bottom) { copyBar(list) }
    }

    private func rowLabel(_ row: GrabRow, selected: Bool, isRangeStart: Bool) -> some View {
        HStack(spacing: 12) {
            // The first tap of a range is marked with a flag until the second tap closes it.
            Image(systemName: isRangeStart ? "flag.circle.fill" : (selected ? "checkmark.circle.fill" : "circle"))
                .font(.title3)
                .foregroundStyle(selected || isRangeStart ? Color("CherriPurpleText") : Color.helperText)

            // Indentation shows how deep an action sits inside If, Repeat and Menu blocks.
            Color.clear.frame(width: CGFloat(row.indent) * 16, height: 1)

            Image(systemName: row.symbol)
                .frame(width: 22)
                .foregroundStyle(Color.helperText)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.helperText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // ===================================
    // RANGE
    // ===================================

    private var rangeSection: some View {
        Section {
            Label(rangeStart == nil ? "Tap the first action of the range" : "Now tap the last action", systemImage: "flag.circle")
            Text("Everything in between is selected. A block the range touches comes in whole.")
                .font(.footnote)
                .foregroundStyle(Color.helperText)
            Button("Cancel", role: .cancel) {
                choosingRange = false
                rangeStart = nil
            }
        }
    }

    // A tap either toggles the row, or, while a range is being chosen, sets one end of it.
    private func tap(_ row: GrabRow, in list: GrabList) {
        guard choosingRange else {
            change(list.selectionAfterToggling(row.index, from: selection))
            return
        }

        guard let start = rangeStart else {
            rangeStart = row.index
            return
        }

        change(selection.union(list.range(from: start, to: row.index)))
        choosingRange = false
        rangeStart = nil
    }

    // ===================================
    // DEPENDENCIES
    // ===================================

    private func dependencySection(_ list: GrabList, missing: Set<Int>) -> some View {
        Section {
            Label {
                Text("This selection needs \(missing.count) more action\(missing.count == 1 ? "" : "s")")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            Text("Some of what you picked uses values made by actions you didn't pick. Without them, the copied actions would lose those links when pasted.")
                .font(.footnote)
                .foregroundStyle(Color.helperText)
            if list.readsLoopOutsideItsLoop(selection) {
                Text("Repeat Index and Repeat Item only work inside a Repeat. Include the Repeat, or paste these into a Repeat that's already in the other shortcut.")
                    .font(.footnote)
                    .foregroundStyle(Color.helperText)
            }
            Button {
                change(selection.union(missing))
            } label: {
                Label("Include Them", systemImage: "plus.circle.fill")
            }
        }
    }

    // ===================================
    // COPY
    // ===================================

    private func copyBar(_ list: GrabList) -> some View {
        VStack(spacing: 8) {
            if copyFailed {
                Text("Couldn't copy those actions.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if let copiedCount {
                Text("Copied \(copiedCount) action\(copiedCount == 1 ? "" : "s"). In Shortcuts, open the shortcut you want them in, tap the small icon at the top left of an action (not the action itself), then tap Paste Above or Paste Below.")
                    .font(.footnote)
                    .foregroundStyle(Color.helperText)
                    .multilineTextAlignment(.center)
            }

            Button {
                copy(list)
            } label: {
                Text(selection.isEmpty ? "Select Actions to Copy" : "Copy \(selection.count) Action\(selection.count == 1 ? "" : "s")")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color("CherriPurpleText"))
            .controlSize(.large)
            .disabled(selection.isEmpty)
        }
        .padding()
        .background(.bar)
    }

    private func change(_ newSelection: Set<Int>) {
        selection = newSelection
        copiedCount = nil
        copyFailed = false
    }

    private func copy(_ list: GrabList) {
        if let count = ActionClipboard.copy(list.actions(for: selection)) {
            copiedCount = count
            copyFailed = false
        } else {
            copiedCount = nil
            copyFailed = true
        }
    }

    // ===================================
    // LOAD
    // ===================================

    // The catalog turns identifiers into readable names. It loads off the main thread, the same way the action picker does.
    private func load() async {
        guard list == nil else { return }

        let plist = fetched.plist
        let name = fetched.name

        do {
            list = try await Task.detached(priority: .userInitiated) {
                let catalog = try ActionCatalog.load().addingVariableActions()
                return try GrabList.parse(plist: plist, name: name, titles: Self.titles(from: catalog))
            }.value
        } catch {
            loadError = error.localizedDescription
        }
    }

    // Several Cherri actions can share one identifier (set and toggle pairs, for instance); the shortest name is the plainest.
    private nonisolated static func titles(from catalog: ActionCatalog) -> [String: String] {
        var titles: [String: String] = [:]
        for action in catalog.actions {
            guard let identifier = action.identifier else { continue }
            let title = action.displayName
            if let existing = titles[identifier], existing.count <= title.count { continue }
            titles[identifier] = title
        }
        return titles
    }
}

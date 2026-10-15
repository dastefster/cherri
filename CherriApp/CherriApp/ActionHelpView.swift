// ===================================
// Action Help
// v0.0.4 BUILD 2026-10-15 18:08
// Help sheet for one action: how to call it, what each parameter expects, defaults, and allowed values. Tapping an allowed value inserts it, quoted, at the editor cursor.
// dev by @dastefster 🍒🔨
// ===================================

import SwiftUI

// ===================================
// HELP SHEET
// ===================================

struct ActionHelpView: View {
    let action: CatalogAction
    let onInsertValue: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(action.signature)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)

                    if let description = action.description, !description.isEmpty {
                        Text(description)
                    }
                    if let warning = action.warning, !warning.isEmpty {
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    if let returns = action.returns, !returns.isEmpty {
                        LabeledContent("Returns", value: returns)
                    }
                }

                if !action.availabilityNotes.isEmpty {
                    Section("Availability") {
                        ForEach(action.availabilityNotes, id: \.self) { note in
                            Text(note)
                        }
                    }
                }

                Section {
                    if action.params.isEmpty {
                        Text("This action takes no parameters.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(action.params, id: \.name) { param in
                            ParamRow(param: param, onInsertValue: onInsertValue)
                        }
                    }
                } header: {
                    Text("Parameters")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if action.params.contains(where: { $0.isOptional }) {
                            Text("Arguments go in this order. To skip an optional parameter and set a later one, write nil in its place.")
                        }
                        if action.params.contains(where: { $0.values?.isEmpty == false }) {
                            Text("Tap an allowed value to insert it at the cursor in your code.")
                        }
                    }
                }
            }
            .navigationTitle(action.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// ===================================
// PARAMETER ROW
// ===================================

private struct ParamRow: View {
    let param: CatalogParam
    let onInsertValue: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(param.name)
                    .font(.system(.body, design: .monospaced).bold())
                Spacer()
                Text(param.isOptional ? "optional" : "required")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(typeLine)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let defaultValue = param.defaultValue, !defaultValue.isEmpty {
                Text("Default: \(param.values?.isEmpty == false ? Self.quoted(defaultValue) : defaultValue)")
                    .font(.footnote)
            }

            if let values = param.values, !values.isEmpty {
                DisclosureGroup("\(values.count) allowed values") {
                    ForEach(values, id: \.self) { value in
                        Button {
                            onInsertValue(Self.quoted(value))
                        } label: {
                            HStack {
                                Text(Self.quoted(value))
                                    .font(.system(.footnote, design: .monospaced))
                                Spacer()
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(.tint)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    // Allowed values are strings in Cherri, so they are shown (and inserted) with their quotes.
    private static func quoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    // A list of choices is clearer as a count than as the compiler's internal name for the list.
    private var typeLine: String {
        var parts = [param.values?.isEmpty == false ? "one of \(param.values?.count ?? 0) options" : param.type]
        if param.literal == true {
            parts.append("type it directly, not a variable")
        }
        if param.repeats == true {
            parts.append("can be repeated")
        }
        if param.qty == true {
            parts.append("takes a quantity")
        }

        return parts.joined(separator: " · ")
    }
}

// ===================================
// DESCRIPTIONS
// ===================================

extension CatalogAction {
    // Matches Cherri's own notation: ? marks an optional parameter and ... one that can be repeated.
    var signature: String {
        let list = params.map { param -> String in
            var text = param.isOptional ? "?\(param.name)" : param.name
            if param.repeats == true {
                text += "..."
            }
            return text
        }

        // Long calls get a line per parameter so a ? never wraps away from its name.
        if list.count > 2 {
            return "\(name)(\n" + list.map { "    \($0)" }.joined(separator: ",\n") + "\n)"
        }

        return "\(name)(" + list.joined(separator: ", ") + ")"
    }

    var availabilityNotes: [String] {
        var notes: [String] = []
        if macOnly == true {
            notes.append("Mac only")
        }
        if nonMacOnly == true {
            notes.append("iPhone and iPad only")
        }
        if let minVersion, minVersion > 0 {
            notes.append("Needs iOS \(String(format: "%g", minVersion)) or later")
        }
        if let maxVersion, maxVersion > 0 {
            notes.append("Removed after iOS \(String(format: "%g", maxVersion))")
        }

        return notes
    }
}

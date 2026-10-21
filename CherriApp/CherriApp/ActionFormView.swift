// ===================================
// Action Form
// v0.0.4 BUILD 2026-10-20 22:55
// Fill-in form for one action: a field per parameter in plain words, a live preview of the Cherri call, and an Insert button that writes the call with nil in any skipped slot.
// dev by @dastefster 🍒🔨
// ===================================

import SwiftUI

// ===================================
// FORM
// ===================================

struct ActionFormView: View {
    let action: CatalogAction
    let source: String
    let onInsert: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String] = [:]
    @State private var useAlternate = false

    var body: some View {
        let variant = ActionVariants.variant(for: action.name)
        let preview = action.call(with: values, named: useAlternate ? variant?.alternate : nil)

        NavigationStack {
            Form {
                if let description = action.description, !description.isEmpty {
                    Section {
                        Text(description)
                    }
                }

                if let variant {
                    Section {
                        Toggle(variant.switchTitle, isOn: $useAlternate)
                    } footer: {
                        Text(variant.switchNote)
                    }
                }

                Section {
                    ForEach(action.params, id: \.name) { param in
                        ParamField(param: param, value: binding(for: param), variables: EditorVariables.names(in: source))
                    }
                } header: {
                    Text("Parameters")
                } footer: {
                    if action.params.contains(where: { $0.isOptional }) {
                        Text("Leave an optional field empty to use its default.")
                    }
                }

                Section {
                    Text(preview.text)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                } header: {
                    Text("Your code")
                } footer: {
                    if preview.placeholders > 0 {
                        Text("Empty required fields get a placeholder you can edit in the code afterwards.")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(action.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Insert") {
                        onInsert(preview.text)
                    }
                }
            }
        }
    }

    private func binding(for param: CatalogParam) -> Binding<String> {
        Binding(
            get: { values[param.name] ?? "" },
            set: { values[param.name] = $0 }
        )
    }
}

// ===================================
// PARAMETER FIELD
// ===================================

private struct ParamField: View {
    let param: CatalogParam
    @Binding var value: String
    let variables: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(param.name.spacedFromCamelCase)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(param.isOptional ? "optional" : "required")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            control
        }
        .padding(.vertical, 2)
    }

    // A list of options or a yes/no becomes a menu, everything else a text field.
    @ViewBuilder
    private var control: some View {
        if let options = param.values, !options.isEmpty {
            Picker(param.name, selection: $value) {
                Text(unsetLabel).tag("")
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if param.type == "bool" {
            Picker(param.name, selection: $value) {
                Text(unsetLabel).tag("")
                Text("On (true)").tag("true")
                Text("Off (false)").tag("false")
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 8) {
                TextField(param.name, text: $value, prompt: Text(prompt), axis: isMultiline ? .vertical : .horizontal)
                    .lineLimit(isMultiline ? 1...12 : 1...1)
                    .keyboardType(isNumeric ? .numbersAndPunctuation : .default)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: usesCode ? .monospaced : .default))

                if param.type == "variable" {
                    variableMenu
                }
            }
        }
    }

    // Picking a name avoids typos and the easy-to-forget @ that mutable variables need.
    private var variableMenu: some View {
        Menu {
            if !variables.isEmpty {
                Section("In your code") {
                    ForEach(variables, id: \.self) { name in
                        Button(name) { value = name }
                    }
                }
            }

            Section("Built in") {
                ForEach(EditorVariables.builtIns, id: \.self) { name in
                    Button(name) { value = name }
                }
            }
        } label: {
            Image(systemName: "chevron.down.circle")
                .font(.title3)
        }
    }

    private var unsetLabel: String {
        if let defaultValue = param.defaultValue, !defaultValue.isEmpty {
            return "Default (\(defaultValue))"
        }

        return param.isOptional ? "Not set" : "Choose…"
    }

    private var prompt: String {
        if let defaultValue = param.defaultValue, !defaultValue.isEmpty {
            return "Default: \(defaultValue)"
        }

        switch param.type {
        case "variable":
            return "Variable, like @name"
        case "dictionary":
            return "{}"
        case "array":
            return "[]"
        case "number", "float":
            return "Number"
        default:
            return param.isOptional ? "Optional" : "Required"
        }
    }

    private var isNumeric: Bool {
        param.type == "number" || param.type == "float"
    }

    private var usesCode: Bool {
        ["variable", "dictionary", "array", "rawtext"].contains(param.type)
    }

    // A single-line field flattens pasted newlines into spaces, which turns a whole script into one // comment.
    private var isMultiline: Bool {
        param.type == "rawtext"
    }
}

// ===================================
// BUILDING THE CALL
// ===================================

extension CatalogAction {
    // Skipped optional slots become nil and trailing empty ones are dropped, because Cherri arguments are positional.
    func call(with entered: [String: String], named override: String? = nil) -> (text: String, placeholders: Int) {
        let entries = params.map { param -> (param: CatalogParam, raw: String?) in
            let raw = entered[param.name] ?? ""
            return (param, raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : raw)
        }

        var last = -1
        for (index, entry) in entries.enumerated() where entry.raw != nil || !entry.param.isOptional {
            last = index
        }

        var placeholders = 0
        let args = entries.prefix(last + 1).map { entry -> String in
            if let raw = entry.raw {
                return entry.param.encoded(raw)
            }
            if entry.param.isOptional {
                return "nil"
            }

            placeholders += 1
            return entry.param.placeholder
        }

        return ("\(override ?? name)(" + args.joined(separator: ", ") + ")", placeholders)
    }
}

extension CatalogParam {
    // How a typed value is written in Cherri: text and options in quotes, numbers, booleans and variables as typed.
    func encoded(_ raw: String) -> String {
        if let values, !values.isEmpty {
            return Self.quote(raw)
        }

        switch type {
        case "text", "string":
            return Self.quote(raw)
        case "rawtext":
            return "'" + raw.replacingOccurrences(of: "'", with: "\\'") + "'"
        default:
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func quote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

// ===================================
// Action Form
// v0.0.13 BUILD 2026-11-11 16:58
// Fill-in form for one action: a field per parameter in plain words, a live preview of the Cherri call, and an Insert button that writes the call with nil in any skipped slot. A list slot, or any slot that can be repeated (List, Email Address, URL, ...), takes its items in rows like the Shortcuts app's List action. An action that returns something can be given a name, so later actions can use that result.
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
    @State private var resultName = ""

    var body: some View {
        let variant = ActionVariants.variant(for: action.name)
        let taken = EditorVariables.names(in: source)
        let preview = action.call(with: values, named: useAlternate ? variant?.alternate : nil, takenNames: taken, resultName: resultName)

        // Cherri does not allow a second constant with the same name, so a clash is renamed and the person is told.
        let cleanedName = CatalogAction.cleanedResultName(resultName)
        let finalName = CatalogAction.resultVariable(from: resultName, avoiding: taken)
        let renameNote: String? = (finalName != nil && finalName != cleanedName) ? "\"\(cleanedName)\" is already used in your code, so this is saved as \(finalName ?? "")." : nil

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
                            .foregroundStyle(Color.helperText)
                    }
                }

                Section {
                    ForEach(action.params, id: \.name) { param in
                        ParamField(
                            param: param,
                            value: binding(for: param),
                            variables: EditorVariables.names(in: source),
                            listEntry: param.takesTypedList
                                ? ListEntryBindings(mode: binding(forKey: "\(param.name)#mode"), items: binding(forKey: "\(param.name)#items"))
                                : nil,
                            repeatItems: param.isRepeatingText ? binding(forKey: "\(param.name)#items") : nil
                        )
                    }
                } header: {
                    Text("Parameters")
                } footer: {
                    if action.params.contains(where: { $0.isOptional }) {
                        Text("Leave an optional field empty to use its default.")
                            .foregroundStyle(Color.helperText)
                    }
                }

                if action.canNameResult {
                    Section {
                        TextField("Name", text: $resultName, prompt: Text("Optional, like items"))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.body, design: .monospaced))
                    } header: {
                        Text("Save the result")
                    } footer: {
                        if let renameNote {
                            Text(renameNote)
                                .foregroundStyle(.orange)
                        } else {
                            Text("Optional. Give the result a name to use it in later actions, like a list for Choose from List. Only useful for actions that give something back.")
                        }
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
            .scrollBounceBehavior(.always)
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
        .dismissesKeyboard()
    }

    private func binding(for param: CatalogParam) -> Binding<String> {
        binding(forKey: param.name)
    }

    // Typed list items live in the same dictionary under their own keys, so the call builder sees them without extra state.
    private func binding(forKey key: String) -> Binding<String> {
        Binding(
            get: { values[key] ?? "" },
            set: { values[key] = $0 }
        )
    }
}

// ===================================
// PARAMETER FIELD
// ===================================

// Whether a list slot is filled from a variable or typed in, and the typed items.
struct ListEntryBindings {
    let mode: Binding<String>
    let items: Binding<String>
}

// One row in the typed list. The id keeps rows stable while others are added or deleted.
private struct ListRow: Identifiable, Equatable {
    let id = UUID()
    var text = ""
}

// Rows like the Shortcuts app's List action: a red minus on each row, a green plus at the bottom. The items are handed back as one line per row.
private struct ItemRowsEditor: View {
    @Binding var text: String
    @State private var rows: [ListRow]
    @FocusState private var focusedRow: UUID?

    // Rebuilt from the saved text, so switching away and back does not lose what was typed. Two empty rows to start, like a new List action.
    init(text: Binding<String>) {
        _text = text
        let saved = text.wrappedValue.components(separatedBy: "\n")
        _rows = State(initialValue: text.wrappedValue.isEmpty ? [ListRow(), ListRow()] : saved.map { ListRow(text: $0) })
    }

    var body: some View {
        VStack(spacing: 12) {
            ForEach(rows) { row in
                HStack(spacing: 10) {
                    // Borderless, or a tap anywhere in the form row would press every button in it.
                    Button {
                        rows.removeAll { $0.id == row.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)

                    TextField("Item", text: textBinding(for: row.id))
                        .focused($focusedRow, equals: row.id)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .onSubmit { addRow() }
                }
            }

            Button {
                addRow()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color("CherriGreen"))
                    Text("Add New Item")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .buttonStyle(.borderless)
        }
        .onChange(of: rows) { _, _ in
            // The call builder reads one item per line and drops the blank ones.
            text = rows.map(\.text).joined(separator: "\n")
        }
    }

    private func addRow() {
        let row = ListRow()
        rows.append(row)
        focusedRow = row.id
    }

    // Looked up by id each time, because an index can be gone by the time a deleted row redraws.
    private func textBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { rows.first { $0.id == id }?.text ?? "" },
            set: { newValue in
                if let index = rows.firstIndex(where: { $0.id == id }) {
                    rows[index].text = newValue
                }
            }
        )
    }
}

private struct ParamField: View {
    let param: CatalogParam
    @Binding var value: String
    let variables: [String]
    var listEntry: ListEntryBindings?
    var repeatItems: Binding<String>?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(param.name.spacedFromCamelCase)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(param.isOptional ? "optional" : "required")
                    .font(.caption)
                    .foregroundStyle(Color.helperText)
            }

            control
        }
        .padding(.vertical, 2)
    }

    // A list of options or a yes/no becomes a menu, everything else a text field.
    @ViewBuilder
    private var control: some View {
        if let repeatItems {
            ItemRowsEditor(text: repeatItems)
        } else if let listEntry {
            listControl(listEntry)
        } else if let options = param.values, !options.isEmpty {
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
            textControl
        }
    }

    private var textControl: some View {
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

    // People who don't know Cherri can't be expected to make a variable first, so a list can be typed straight in, row by row.
    @ViewBuilder
    private func listControl(_ entry: ListEntryBindings) -> some View {
        Picker("List source", selection: entry.mode) {
            Text("Variable").tag("")
            Text("Type items").tag("items")
        }
        .pickerStyle(.segmented)

        if entry.mode.wrappedValue == "items" {
            ItemRowsEditor(text: entry.items)
        } else {
            textControl
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
    func call(with entered: [String: String], named override: String? = nil, takenNames: [String] = [], resultName: String = "") -> (text: String, placeholders: Int) {
        // Typed list items become a variable on the line above the call, named so it never clashes with one already in the code.
        var preamble: [String] = []

        let entries = params.map { param -> (param: CatalogParam, raw: String?, items: [String]) in
            var raw = entered[param.name] ?? ""
            var items: [String] = []

            if param.isRepeatingText {
                items = CatalogParam.listItems(from: entered["\(param.name)#items"] ?? "")
            } else if param.takesTypedList, entered["\(param.name)#mode"] == "items" {
                let typed = CatalogParam.listItems(from: entered["\(param.name)#items"] ?? "")
                if !typed.isEmpty {
                    let variable = CatalogParam.freeListName(avoiding: takenNames)
                    preamble.append("\(variable) = \(CatalogParam.listLiteral(of: typed))")
                    raw = variable
                }
            }

            return (param, raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : raw, items)
        }

        var last = -1
        for (index, entry) in entries.enumerated() where entry.raw != nil || !entry.items.isEmpty || !entry.param.isOptional {
            last = index
        }

        var placeholders = 0
        let args = entries.prefix(last + 1).flatMap { entry -> [String] in
            // A repeating slot writes one argument per row.
            if !entry.items.isEmpty {
                return entry.items.map { entry.param.encoded($0) }
            }
            if let raw = entry.raw {
                return [entry.param.encoded(raw)]
            }
            if entry.param.isOptional {
                return ["nil"]
            }

            placeholders += 1
            return [entry.param.placeholder]
        }

        var call = "\(override ?? name)(" + args.joined(separator: ", ") + ")"
        if let variable = Self.resultVariable(from: resultName, avoiding: takenNames) {
            call = "const \(variable) = " + call
        }

        return ((preamble + [call]).joined(separator: "\n"), placeholders)
    }

    // The compiler leaves most of its own actions without a declared return type (List is one), so the catalog cannot say which actions give something back. Offering the field everywhere is harmless because it is optional.
    var canNameResult: Bool { true }

    // Only letters, digits and underscores make a name Cherri accepts, and a leading digit would not parse.
    static func cleanedResultName(_ typed: String) -> String {
        var name = String(typed.filter { $0.isLetter || $0.isNumber || $0 == "_" })
        if let first = name.first, first.isNumber {
            name = "n" + name
        }

        return name
    }

    static func resultVariable(from typed: String, avoiding taken: [String]) -> String? {
        let wanted = cleanedResultName(typed)
        guard !wanted.isEmpty else { return nil }

        // Variables come back as @name and constants as name, but either one blocks the name.
        let used = Set(taken.map { $0.hasPrefix("@") ? String($0.dropFirst()) : $0 })
        var name = wanted
        var number = 2

        while used.contains(name) {
            name = wanted + String(number)
            number += 1
        }

        return name
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

    // The list slot of the list actions (Choose from List, Get First Item, ...) takes a variable, so typed items need one made for them.
    var takesTypedList: Bool {
        name == "list" && type == "variable" && !isOptional
    }

    // A text slot Cherri lets you repeat (List, Email Address, URL, ...) takes its values in rows.
    var isRepeatingText: Bool {
        repeats == true && (type == "text" || type == "string")
    }

    // Blank rows are dropped, because an empty entry is never what someone meant.
    static func listItems(from text: String) -> [String] {
        text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func listLiteral(of items: [String]) -> String {
        "[" + items.map(quote).joined(separator: ", ") + "]"
    }

    static func freeListName(avoiding taken: [String]) -> String {
        var name = "@items"
        var number = 2

        while taken.contains(name) {
            name = "@items\(number)"
            number += 1
        }

        return name
    }

    private static func quote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

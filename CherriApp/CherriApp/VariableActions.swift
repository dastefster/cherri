// ===================================
// Variable Actions
// v0.0.3 BUILD 2026-11-18 17:20
// Set Variable and Add to Variable for the action picker. In Cherri these are not actions you call but syntax (@name = value and @name += value), so the compiler's catalog does not list them. These hand-made entries sit in their own Variables section, appear in the picker, search and forms like any other action, and write the syntax.
// dev by @dastefster 🍒🔨
// ===================================

import Foundation

// ===================================
// ENTRIES
// ===================================

nonisolated enum VariableActions {
    static let categoryID = "variables"
    static let setName = "setVariable"
    static let addName = "addToVariable"

    static let category = CatalogCategory(id: categoryID, title: "Variables")

    // The value slot is not a plain typed field: the form gives it a Text, Number or Variable switch, so its type here is only the words the help sheet shows.
    private static let parameters = [
        CatalogParam(name: "name", type: "text", values: nil, optional: false, literal: nil, repeats: nil, qty: nil, defaultValue: nil),
        CatalogParam(name: "value", type: "text, number or variable", values: nil, optional: false, literal: nil, repeats: nil, qty: nil, defaultValue: nil)
    ]

    static let actions: [CatalogAction] = [
        CatalogAction(
            name: setName,
            identifier: "is.workflow.actions.setvariable",
            title: "Set Variable",
            description: "Saves a value under a name so later actions can use it. Written as @name = value.",
            warning: nil,
            category: categoryID,
            subcategory: nil,
            params: parameters,
            returns: nil,
            macOnly: nil,
            nonMacOnly: nil,
            minVersion: nil,
            maxVersion: nil
        ),
        CatalogAction(
            name: addName,
            identifier: "is.workflow.actions.appendvariable",
            title: "Add to Variable",
            description: "Adds to a variable you already made: math on a number, more text on text, a new item on a list. Written as @name += value.",
            warning: nil,
            category: categoryID,
            subcategory: nil,
            params: parameters,
            returns: nil,
            macOnly: nil,
            nonMacOnly: nil,
            minVersion: nil,
            maxVersion: nil
        )
    ]

    // The Cherri operator each entry writes.
    static func operatorText(for name: String) -> String? {
        switch name {
        case setName:
            return "="
        case addName:
            return "+="
        default:
            return nil
        }
    }

    static func syntax(for name: String) -> String? {
        guard let operatorText = operatorText(for: name) else { return nil }
        return "@name \(operatorText) value"
    }

    // Words people know these by from the Shortcuts app, so a search finds them.
    static func aliases(for name: String) -> [String] {
        switch name {
        case setName:
            return ["set variable", "variable", "assign", "store", "save", "var"]
        case addName:
            return ["add to variable", "variable", "append", "increment", "plus", "+="]
        default:
            return []
        }
    }
}

// ===================================
// CATALOG
// ===================================

extension ActionCatalog {
    // The Variables section goes first, because Set Variable is one of the most used actions in Shortcuts.
    nonisolated func addingVariableActions() -> ActionCatalog {
        ActionCatalog(
            compilerVersion: compilerVersion,
            categories: [VariableActions.category] + categories,
            actions: VariableActions.actions + actions
        )
    }
}

// ===================================
// STATEMENT
// ===================================

extension CatalogAction {
    var isVariableAction: Bool {
        VariableActions.operatorText(for: name) != nil
    }

    // The picker row shows the call name for a real action, and the syntax for these.
    var listSubtitle: String {
        VariableActions.syntax(for: name) ?? name
    }

    // Cherri cannot compile text added to a variable that is set nowhere in the code, because it has nothing to tell it what kind of variable to add to. Stopping it here means the error never shows up later. A variable set only further down still compiles, so that is not blocked. An empty name is not blocked either, since it gets an editable placeholder.
    func blockReason(with entered: [String: String], knownNames: [String]) -> String? {
        guard name == VariableActions.addName else { return nil }
        guard (entered["value#kind"] ?? "").isEmpty else { return nil }

        let variable = CatalogAction.cleanedResultName(entered["name"] ?? "")
        guard !variable.isEmpty, !knownNames.contains("@" + variable) else { return nil }

        return "@\(variable) isn't set anywhere in your code yet. Text can only be added to a variable that already exists, so use Set Variable for it first."
    }

    // Things that compile but give a result the person would not expect, found by running them in Shortcuts. Cherri picks the action from the value being added, not from the variable: a number becomes Math, text becomes joined text, and a variable becomes a plain Set Variable (except on lists, which append). So the trouble comes from the combinations. Anything that works as expected, like text added to anything or items added to a list, stays quiet, and so does a variable whose kind cannot be told.
    func warnings(with entered: [String: String], codeAbove: String) -> [String] {
        guard name == VariableActions.addName else { return [] }

        let variable = CatalogAction.cleanedResultName(entered["name"] ?? "")
        guard !variable.isEmpty else { return [] }

        let setAbove = EditorVariables.names(in: codeAbove).contains("@" + variable)
        let held = setAbove ? EditorVariables.kind(of: variable, in: codeAbove) : nil

        switch entered["value#kind"] ?? "" {
        case "number":
            if !setAbove {
                return ["@\(variable) isn't set above this point, so the math has nothing to start from and the result will be blank."]
            }

            if held == .text {
                return ["@\(variable) holds text. Adding a number replaces the text with just the number."]
            }
        case "variable":
            if held == .text || held == .number {
                return ["Adding a variable replaces @\(variable) instead of adding to it. Only lists add."]
            }
        default:
            break
        }

        return []
    }

    // Writes @name = value or @name += value from what the form collected. Empty slots get a placeholder the person can edit in the code, like every other action.
    func variableStatement(with entered: [String: String], takenNames: [String]) -> (text: String, placeholders: Int)? {
        guard let operatorText = VariableActions.operatorText(for: name) else { return nil }

        var placeholders = 0

        var variable = CatalogAction.cleanedResultName(entered["name"] ?? "")
        if variable.isEmpty {
            variable = "name"
            placeholders += 1
        }

        let raw = (entered["value"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let kind = entered["value#kind"] ?? ""
        var value = raw

        if raw.isEmpty {
            placeholders += 1

            switch kind {
            case "number":
                value = "0"
            case "variable":
                value = "@variable"
            default:
                value = "\"\""
            }
        } else {
            switch kind {
            case "variable":
                // Mutable variables need the @, so a typed name that matches one gets it.
                if !raw.hasPrefix("@"), takenNames.contains("@" + raw) {
                    value = "@" + raw
                }
            case "number":
                break
            default:
                value = "\"" + raw.replacingOccurrences(of: "\"", with: "\\\"") + "\""
            }
        }

        return ("@\(variable) \(operatorText) \(value)", placeholders)
    }
}

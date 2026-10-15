// ===================================
// Action Catalog
// v0.0.4 BUILD 2026-10-15 18:35
// Loads the list of every Cherri action from the embedded compiler, gives each a readable name, and turns an action into starter code to insert.
// dev by @dastefster 🍒🔨
// ===================================

import Foundation
import Cherri

// ===================================
// MODELS
// ===================================

nonisolated struct CatalogParam: Codable, Hashable {
    let name: String
    let type: String
    let values: [String]?
    let optional: Bool?
    let literal: Bool?
    let repeats: Bool?
    let qty: Bool?
    let defaultValue: String?

    enum CodingKeys: String, CodingKey {
        case name, type, values, optional, literal, repeats, qty
        case defaultValue = "default"
    }

    var isOptional: Bool { optional ?? false }
}

nonisolated struct CatalogAction: Codable, Identifiable, Hashable {
    let name: String
    let title: String?
    let description: String?
    let warning: String?
    let category: String
    let subcategory: String?
    let params: [CatalogParam]
    let returns: String?
    let macOnly: Bool?
    let nonMacOnly: Bool?
    let minVersion: Double?
    let maxVersion: Double?

    var id: String { name }
}

nonisolated struct CatalogCategory: Codable, Hashable, Identifiable {
    let id: String
    let title: String
}

nonisolated struct ActionCatalog: Codable {
    let compilerVersion: String
    let categories: [CatalogCategory]
    let actions: [CatalogAction]
}

// ===================================
// LOADING
// ===================================

extension ActionCatalog {
    // The first call makes the compiler load all of its actions, so call this off the main thread.
    nonisolated static func load() throws -> ActionCatalog {
        var error: NSError?
        let json = CherriActionCatalog(&error)
        if let error {
            throw error
        }

        return try JSONDecoder().decode(ActionCatalog.self, from: Data(json.utf8))
    }
}

// ===================================
// SEARCH AND INSERTION
// ===================================

extension CatalogAction {
    func matches(_ query: String) -> Bool {
        name.lowercased().contains(query)
            || displayName.lowercased().contains(query)
            || (ActionVariants.variant(for: name)?.alternate.lowercased().contains(query) ?? false)
            || (title ?? "").lowercased().contains(query)
            || (description ?? "").lowercased().contains(query)
    }

    // The documented title when Cherri has one, otherwise the call name split into words. Not Apple's official name, just readable.
    var displayName: String {
        if let title, !title.isEmpty {
            return title
        }

        return name.spacedFromCamelCase
    }

    // Starter code with every required argument filled by a placeholder of the right kind. Optional ones are left out.
    var insertionText: String {
        let required = params.filter { !$0.isOptional }
        if required.isEmpty {
            return "\(name)()"
        }

        return "\(name)(" + required.map(\.placeholder).joined(separator: ", ") + ")"
    }
}

extension CatalogParam {
    var placeholder: String {
        if let first = values?.first {
            return "\"\(first)\""
        }

        switch type {
        case "number", "float":
            return "0"
        case "bool":
            return "true"
        case "dictionary":
            return "{}"
        case "array":
            return "[]"
        case "rawtext":
            return "''"
        default:
            return "\"\""
        }
    }
}

// ===================================
// CAMEL CASE SPLITTING
// ===================================

extension String {
    // "getBatteryLevel" becomes "Get Battery Level" and "getURL" becomes "Get URL".
    var spacedFromCamelCase: String {
        let chars = Array(self)
        var result = ""

        for (index, char) in chars.enumerated() {
            if index > 0 && char.isUppercase {
                let previous = chars[index - 1]
                let nextIsLower = index + 1 < chars.count && chars[index + 1].isLowercase

                if previous.isLowercase || previous.isNumber || (previous.isUppercase && nextIsLower) {
                    result.append(" ")
                }
            }
            result.append(char)
        }

        return result.prefix(1).uppercased() + result.dropFirst()
    }
}

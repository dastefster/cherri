// ===================================
// Shortcut Action List
// v0.0.4 BUILD 2026-11-23 09:30
// Reads the actions out of a downloaded shortcut file so the person can pick some to copy. Names each action, works out indentation and control-flow blocks, and finds which other actions a selection depends on, so a paste never lands with a broken variable link. Pure Foundation, no UI.
// dev by @dastefster 🍒🔨
// ===================================

import Foundation

// ===================================
// ROW
// ===================================

// One action in the shortcut, exactly as stored, plus what the list needs to show it.
nonisolated struct GrabRow: Identifiable {
    let index: Int
    var id: Int { index }
    let identifier: String
    let title: String
    // A short peek at what the action does (its text, variable name, and so on), or the app's name for actions from other apps.
    let subtitle: String?
    let symbol: String
    let indent: Int
    // Set for If/Repeat/Menu rows: every row of one block shares this. mode is 0 for the start, 1 for a middle (Otherwise, a menu item), 2 for the end.
    let blockID: String?
    let blockMode: Int?
    // The UUID this action's output is known by, so other actions can point at it.
    let producedUUID: String?
    // Outputs this action reads, by the UUID of the action that makes them.
    let referencedUUIDs: [String]
    // Named variables this action reads.
    let referencedVariables: [String]
    // The name this action gives a variable (Set Variable only).
    let setsVariable: String?
    // The action dictionary exactly as it was in the file, so a copy is the shortcut's own and loses nothing.
    let action: [String: Any]
}

// ===================================
// LIST
// ===================================

nonisolated enum GrabError: LocalizedError {
    case notAShortcut

    var errorDescription: String? {
        "That file doesn't look like a shortcut, so there are no actions to list."
    }
}

nonisolated struct GrabList {
    let name: String
    let rows: [GrabRow]
    // First and last row of each block, so tapping any part of it can take the whole block.
    private let blockRanges: [String: ClosedRange<Int>]
    // Which row makes the output known by each UUID.
    private let producers: [String: Int]

    // titles maps an action identifier (is.workflow.actions.gettext) to a readable name, normally built from the compiler's catalog.
    static func parse(plist: Data, name: String, titles: [String: String]) throws -> GrabList {
        guard let root = try? PropertyListSerialization.propertyList(from: plist, options: [], format: nil) as? [String: Any],
              let actions = root["WFWorkflowActions"] as? [[String: Any]] else {
            throw GrabError.notAShortcut
        }

        var rows: [GrabRow] = []
        var depth = 0

        for (index, action) in actions.enumerated() {
            let identifier = action["WFWorkflowActionIdentifier"] as? String ?? ""
            let params = action["WFWorkflowActionParameters"] as? [String: Any] ?? [:]
            let blockID = params["GroupingIdentifier"] as? String
            let mode = blockID == nil ? nil : params["WFControlFlowMode"] as? Int

            // A block's start opens a level, a middle sits at the outer level and reopens, an end closes it.
            var indent = depth
            switch mode {
            case 0:
                indent = depth
                depth += 1
            case 1:
                depth = max(depth - 1, 0)
                indent = depth
                depth += 1
            case 2:
                depth = max(depth - 1, 0)
                indent = depth
            default:
                break
            }

            let naming = describe(identifier: identifier, mode: mode, params: params, titles: titles)
            var references = References()
            collectReferences(in: params, into: &references)

            rows.append(GrabRow(
                index: index,
                identifier: identifier,
                title: naming.title,
                subtitle: summary(of: params, identifier: identifier, mode: mode) ?? naming.app,
                symbol: naming.symbol,
                indent: indent,
                blockID: blockID,
                blockMode: mode,
                producedUUID: params["UUID"] as? String,
                referencedUUIDs: references.uuids,
                referencedVariables: references.variables,
                setsVariable: identifier == "is.workflow.actions.setvariable" ? params["WFVariableName"] as? String : nil,
                action: action
            ))
        }

        return GrabList(name: name, rows: rows)
    }

    private init(name: String, rows: [GrabRow]) {
        self.name = name
        self.rows = rows

        var ranges: [String: ClosedRange<Int>] = [:]
        var producers: [String: Int] = [:]
        for row in rows {
            if let blockID = row.blockID {
                if let existing = ranges[blockID] {
                    ranges[blockID] = min(existing.lowerBound, row.index)...max(existing.upperBound, row.index)
                } else {
                    ranges[blockID] = row.index...row.index
                }
            }
            if let uuid = row.producedUUID, producers[uuid] == nil {
                producers[uuid] = row.index
            }
        }
        self.blockRanges = ranges
        self.producers = producers
    }

    // ===================================
    // SELECTION
    // ===================================

    // Tapping part of a block (the If, the Otherwise, the End If) takes the whole block, contents included. Anything else is just itself.
    func indexes(toggledBy index: Int) -> [Int] {
        guard rows.indices.contains(index) else { return [] }
        if let blockID = rows[index].blockID, let range = blockRanges[blockID] {
            return Array(range)
        }
        return [index]
    }

    func selectionAfterToggling(_ index: Int, from selection: Set<Int>) -> Set<Int> {
        let group = indexes(toggledBy: index)
        var result = selection
        if group.allSatisfy({ selection.contains($0) }) {
            group.forEach { result.remove($0) }
        } else {
            group.forEach { result.insert($0) }
        }
        return result
    }

    // Every row from one tapped row to another, in either order. A block the range touches comes in whole, so a range can never end with an If and no End If (or the other way round). Nested blocks are handled by repeating until nothing more is pulled in.
    func range(from first: Int, to second: Int) -> Set<Int> {
        guard rows.indices.contains(first), rows.indices.contains(second) else { return [] }
        var low = min(first, second)
        var high = max(first, second)

        var changed = true
        while changed {
            changed = false
            for row in rows[low...high] {
                guard let blockID = row.blockID, let block = blockRanges[blockID] else { continue }
                if block.lowerBound < low { low = block.lowerBound; changed = true }
                if block.upperBound > high { high = block.upperBound; changed = true }
            }
        }
        return Set(low...high)
    }

    // ===================================
    // SEARCH
    // ===================================

    // Every word typed has to show up somewhere in the row's name, its subtitle, or the app it comes from. Ignores case and accents.
    func rows(matching query: String) -> [GrabRow] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return rows }

        return rows.filter { row in
            let text = [row.title, row.subtitle ?? ""].joined(separator: " ")
            return words.allSatisfy { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }

    // ===================================
    // DEPENDENCIES
    // ===================================

    // The rows a selection reads from but doesn't include. Copying without them would paste actions whose variables point at nothing. Follows the chain, so an included row's own needs are listed too, and pulls in a whole block when what's needed is part of one.
    func missingDependencies(for selection: Set<Int>) -> Set<Int> {
        var covered = selection
        var queue = Array(selection)
        var needed = Set<Int>()

        while let current = queue.popLast() {
            for producer in producerIndexes(for: rows[current]) {
                for index in indexes(toggledBy: producer) where !covered.contains(index) {
                    covered.insert(index)
                    needed.insert(index)
                    queue.append(index)
                }
            }

            // Only the Repeat and End Repeat are added, not every other action inside the loop, so one action can be wrapped in its loop without dragging the rest along. The Repeat's own count or list is followed like anything else.
            for wrapper in loopWrapperIndexes(for: rows[current]) where !covered.contains(wrapper) {
                covered.insert(wrapper)
                needed.insert(wrapper)
                queue.append(wrapper)
            }
        }

        return needed
    }

    // True when something in the selection reads Repeat Index or Repeat Item but its Repeat isn't in the selection, so the paste would show a broken (red) variable unless it lands inside a loop.
    func readsLoopOutsideItsLoop(_ selection: Set<Int>) -> Bool {
        selection.contains { index in
            loopWrapperIndexes(for: rows[index]).contains { !selection.contains($0) }
        }
    }

    private static let loopVariables: Set<String> = ["Repeat Index", "Repeat Item"]
    private static let repeatIdentifiers: Set<String> = ["is.workflow.actions.repeat.count", "is.workflow.actions.repeat.each"]

    // The Repeat and End Repeat rows around an action that reads Repeat Index or Repeat Item. Those variables only exist inside a loop. Empty when the action reads neither, or isn't inside a Repeat in the first place.
    private func loopWrapperIndexes(for row: GrabRow) -> [Int] {
        guard row.referencedVariables.contains(where: { Self.loopVariables.contains($0) }) else { return [] }

        // The innermost Repeat is the one that starts closest above the row.
        var innermost: ClosedRange<Int>?
        for range in blockRanges.values where range.lowerBound < row.index && row.index < range.upperBound {
            guard Self.repeatIdentifiers.contains(rows[range.lowerBound].identifier) else { continue }
            if innermost == nil || range.lowerBound > innermost!.lowerBound {
                innermost = range
            }
        }

        guard let loop = innermost else { return [] }
        return [loop.lowerBound, loop.upperBound]
    }

    private func producerIndexes(for row: GrabRow) -> [Int] {
        var result: [Int] = []

        for uuid in row.referencedUUIDs {
            if let producer = producers[uuid], producer != row.index {
                result.append(producer)
            }
        }

        // A named variable comes from the closest Set Variable above the action that reads it. Names with no Set Variable (Ask Each Time and the like) are built in and need nothing. Repeat Index and Repeat Item are handled separately, because they need their loop.
        for name in row.referencedVariables {
            if let setter = rows[..<row.index].last(where: { $0.setsVariable == name }) {
                result.append(setter.index)
            }
        }

        return result
    }

    // The selected actions, in the order they appear in the shortcut.
    func actions(for selection: Set<Int>) -> [[String: Any]] {
        rows.filter { selection.contains($0.index) }.map(\.action)
    }
}

// ===================================
// REFERENCES
// ===================================

private nonisolated struct References {
    var uuids: [String] = []
    var variables: [String] = []
}

// Walks every parameter, however deeply it's nested (dictionaries, text with variable chips, lists), and notes each place that points at another action's output or at a named variable.
private nonisolated func collectReferences(in value: Any, into references: inout References) {
    if let dict = value as? [String: Any] {
        if let uuid = dict["OutputUUID"] as? String, !references.uuids.contains(uuid) {
            references.uuids.append(uuid)
        }
        if dict["Type"] as? String == "Variable",
           let name = dict["VariableName"] as? String,
           !references.variables.contains(name) {
            references.variables.append(name)
        }
        for child in dict.values {
            collectReferences(in: child, into: &references)
        }
    } else if let list = value as? [Any] {
        for child in list {
            collectReferences(in: child, into: &references)
        }
    }
}

// ===================================
// NAMING
// ===================================

private nonisolated func describe(identifier: String, mode: Int?, params: [String: Any], titles: [String: String]) -> (title: String, symbol: String, app: String?) {
    switch identifier {
    case "is.workflow.actions.conditional":
        return (["If", "Otherwise", "End If"][min(max(mode ?? 0, 0), 2)], "arrow.triangle.branch", nil)
    case "is.workflow.actions.choosefrommenu":
        return (["Choose from Menu", "Menu Item", "End Menu"][min(max(mode ?? 0, 0), 2)], "list.bullet", nil)
    case "is.workflow.actions.repeat.count":
        return (mode == 2 ? "End Repeat" : "Repeat", "repeat", nil)
    case "is.workflow.actions.repeat.each":
        return (mode == 2 ? "End Repeat" : "Repeat with Each", "repeat", nil)
    case "is.workflow.actions.setvariable":
        return ("Set Variable", "x.squareroot", nil)
    case "is.workflow.actions.appendvariable":
        return ("Add to Variable", "x.squareroot", nil)
    case "is.workflow.actions.getvariable":
        return ("Get Variable", "x.squareroot", nil)
    case "is.workflow.actions.gettext":
        return (titles[identifier] ?? "Text", "text.alignleft", nil)
    case "is.workflow.actions.comment":
        return (titles[identifier] ?? "Comment", "text.bubble", nil)
    case "is.workflow.actions.dictionary":
        return (titles[identifier] ?? "Dictionary", "curlybraces", nil)
    default:
        if let title = titles[identifier] ?? handNamed[identifier] {
            return (title, "square.grid.2x2", nil)
        }
        let pretty = prettify(identifier)
        return (pretty.title, "square.grid.2x2", pretty.app)
    }
}

// Actions the catalog doesn't carry whose identifiers are one run-together word, so they can't be split into readable words. Add to this when a shortcut turns up one that reads badly.
private nonisolated let handNamed: [String: String] = [
    "is.workflow.actions.gettypeaction": "Get File of Type",
]

// A readable name for an action the catalog doesn't know, such as a third-party app's own action. com.zlineman.Jellyfish.GrabJellycutIntent becomes "Grab Jellycut", from "Jellyfish".
private nonisolated func prettify(_ identifier: String) -> (title: String, app: String?) {
    let standard = "is.workflow.actions."
    if identifier.hasPrefix(standard) {
        let words = identifier.dropFirst(standard.count).split(separator: ".").map { String($0).spacedFromCamelCase }
        return (words.joined(separator: " "), nil)
    }

    let parts = identifier.split(separator: ".").map(String.init)
    guard var last = parts.last else { return (identifier, nil) }
    for suffix in ["Intent", "Action"] where last.hasSuffix(suffix) && last.count > suffix.count {
        last = String(last.dropLast(suffix.count))
        break
    }

    let app = parts.count >= 3 ? parts[parts.count - 2] : nil
    return (last.spacedFromCamelCase, app?.spacedFromCamelCase)
}

// ===================================
// SUMMARY
// ===================================

// Keys worth showing as a peek, best first.
private nonisolated let summaryKeys = [
    "WFCommentActionText", "WFTextActionText", "WFVariableName", "WFMenuItemTitle", "WFMenuPrompt",
    "WFAlertActionMessage", "WFAlertActionTitle", "WFURLActionURL", "URL", "WFNumberActionNumber",
]

// Parameters that are bookkeeping, not content, when falling back to "the first readable value".
private nonisolated let bookkeepingKeys: Set<String> = [
    "UUID", "GroupingIdentifier", "WFControlFlowMode", "CustomOutputName", "AppIntentDescriptor", "ShowWhenRun",
]

private nonisolated func summary(of params: [String: Any], identifier: String, mode: Int?) -> String? {
    // A bare start or end has nothing to peek at, and an If's input is a variable chip, not words.
    if identifier == "is.workflow.actions.conditional" || mode == 2 { return nil }

    for key in summaryKeys {
        if let text = readableText(params[key]) { return text }
    }
    for key in params.keys.sorted() where !bookkeepingKeys.contains(key) {
        if let text = readableText(params[key]) { return text }
    }
    return nil
}

// Plain text as is. A variable shows by name in braces, the way Cherri writes it ({Repeat Index}), whether it's the whole value or sits inside text. Anything else is skipped.
private nonisolated func readableText(_ value: Any?) -> String? {
    var raw: String?
    if let text = value as? String {
        raw = text
    } else if let dict = value as? [String: Any],
              let inner = dict["Value"] as? [String: Any] {
        if let text = inner["string"] as? String {
            raw = fillChips(in: text, attachments: inner["attachmentsByRange"] as? [String: Any] ?? [:])
        } else if inner["Type"] is String {
            // The whole value is one variable, with no text around it.
            raw = "{\(chipName(inner))}"
        }
    }

    guard let raw else { return nil }
    let oneLine = raw.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    guard !oneLine.isEmpty else { return nil }
    return oneLine.count > 60 ? String(oneLine.prefix(60)) + "…" : oneLine
}

// Each chip in a text value is a placeholder character, and a table says which variable sits at which position. Keys look like "{3, 1}": where the chip is, and how long. A chip with no entry stays a ▢.
private nonisolated func fillChips(in text: String, attachments: [String: Any]) -> String {
    let source = text as NSString
    var result = ""
    var last = 0

    for position in 0..<source.length where source.character(at: position) == 0xFFFC {
        result += source.substring(with: NSRange(location: last, length: position - last))
        last = position + 1

        let entry = attachments.first { key, _ in
            let start = key.trimmingCharacters(in: CharacterSet(charactersIn: "{}")).split(separator: ",").first
            return start.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } == position
        }
        if let chip = entry?.value as? [String: Any] {
            result += "{\(chipName(chip))}"
        } else {
            result += "▢"
        }
    }

    return result + source.substring(from: last)
}

// What a variable chip is called in the Shortcuts editor.
private nonisolated func chipName(_ attachment: [String: Any]) -> String {
    switch attachment["Type"] as? String {
    case "Variable": return attachment["VariableName"] as? String ?? "Variable"
    case "ActionOutput": return attachment["OutputName"] as? String ?? "Result"
    case "ExtensionInput": return "Shortcut Input"
    case "Clipboard": return "Clipboard"
    case "CurrentDate": return "Current Date"
    case "Ask": return "Ask Each Time"
    case let type?: return type.spacedFromCamelCase
    case nil: return "Variable"
    }
}

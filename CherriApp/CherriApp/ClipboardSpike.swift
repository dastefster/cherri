// ===================================
// Clipboard Spike
// v0.0.1 BUILD 2026-11-22 07:20
// Debug-only experiment: writes three linked Shortcuts actions to the clipboard as com.apple.shortcuts.action items so we can test whether Shortcuts on iPhone pastes them when a third-party app is the writer.
// dev by @dastefster 🍒🔨
// ===================================

#if DEBUG
import UIKit

// ===================================
// CLIPBOARD SPIKE
// ===================================

enum ClipboardSpike {
    // The type Shortcuts itself uses for copied actions (verified on the Mac: one pasteboard item per action, each holding a binary plist of one bare action dictionary).
    static let actionType = "com.apple.shortcuts.action"

    // Fixed UUID so the Set Variable can point at the Text action. If Shortcuts keeps the link after paste, the output reference survives a third-party write.
    private static let textUUID = "5A1C0DE0-0000-4000-8000-00000000A001"

    // ===================================
    // BUILD THE THREE ACTIONS
    // ===================================

    private static func actions() -> [[String: Any]] {
        // 1. Text: produces the output the next action will reference.
        let text: [String: Any] = [
            "WFWorkflowActionIdentifier": "is.workflow.actions.gettext",
            "WFWorkflowActionParameters": [
                "UUID": textUUID,
                "WFTextActionText": "Clipboard spike works",
            ] as [String: Any],
        ]

        // 2. Set Variable: input is an ActionOutput reference to the Text above (tests whether OutputUUID links survive).
        let setVariable: [String: Any] = [
            "WFWorkflowActionIdentifier": "is.workflow.actions.setvariable",
            "WFWorkflowActionParameters": [
                "WFVariableName": "spike",
                "WFInput": [
                    "Value": [
                        "OutputName": "Text",
                        "OutputUUID": textUUID,
                        "Type": "ActionOutput",
                    ] as [String: Any],
                    "WFSerializationType": "WFTextTokenAttachment",
                ] as [String: Any],
            ] as [String: Any],
        ]

        // 3. Alert: message is just the named variable (tests whether a name-based reference survives).
        let alert: [String: Any] = [
            "WFWorkflowActionIdentifier": "is.workflow.actions.alert",
            "WFWorkflowActionParameters": [
                "WFAlertActionTitle": "Spike",
                "WFAlertActionMessage": [
                    "Value": [
                        "string": "\u{FFFC}",
                        "attachmentsByRange": [
                            "{0, 1}": [
                                "Type": "Variable",
                                "VariableName": "spike",
                            ] as [String: Any],
                        ] as [String: Any],
                    ] as [String: Any],
                    "WFSerializationType": "WFTextTokenString",
                ] as [String: Any],
            ] as [String: Any],
        ]

        return [text, setVariable, alert]
    }

    // ===================================
    // WRITE TO THE CLIPBOARD
    // ===================================

    // One pasteboard item per action, in order, each a binary plist under the Shortcuts action type. Returns how many items were written, or nil if serializing failed.
    @discardableResult
    static func copyTestActions() -> Int? {
        var items: [[String: Any]] = []
        for action in actions() {
            guard let data = try? PropertyListSerialization.data(fromPropertyList: action, format: .binary, options: 0) else {
                return nil
            }
            items.append([actionType: data])
        }
        UIPasteboard.general.setItems(items, options: [:])
        return items.count
    }
}
#endif

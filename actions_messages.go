/*
 * Copyright (c) Cherri
 */

package main

// Messages (com.apple.MobileSMS) actions added in iOS 27. Every definition here was read from a device export
// on iOS 27: Shortcuts only writes a parameter that was touched, so untouched options are omitted.
const messagesBundleIdentifier = "com.apple.MobileSMS"

// messagesIntent builds the app intent descriptor shared by the Messages actions, varying only by identifier.
func messagesIntent(appIntentIdentifier string) appIntent {
	return appIntent{
		name:                "Messages",
		bundleIdentifier:    messagesBundleIdentifier,
		appIntentIdentifier: appIntentIdentifier,
	}
}

// messagesTapbackCodes maps each Tapback to the numeric code Messages stores, which are the same codes iMessage
// uses for its reactions. The export only holds the code, so the order was confirmed against the action's menu.
var messagesTapbackCodes = map[string]string{
	"Love":      "2000",
	"Like":      "2001",
	"Dislike":   "2002",
	"Laugh At":  "2003",
	"Emphasize": "2004",
	"Question":  "2005",
}

// messagesInbox is how Open Inbox stores each of its choices: a numeric filter mode and the SF Symbol shown beside it.
type messagesInbox struct {
	mode   string
	symbol string
}

var messagesInboxes = map[string]messagesInbox{
	"Messages":         {"2", "message.and.message"},
	"Unknown Senders":  {"3", "person.crop.circle.badge.questionmark"},
	"Spam":             {"9", "xmark.bin"},
	"Recently Deleted": {"7", "trash"},
	"Unread":           {"8", "message.badge"},
	"Drafts":           {"26", "ellipsis.message"},
	"Send Later":       {"10", "clock"},
}

// messagesVariableValue builds a variable argument for the Messages intents. Their Ask Each Time carries no
// VariableName, unlike the one Cherri writes for the standard actions.
func messagesVariableValue(arg actionArgument) any {
	var attachment = variableValue(arg.value.(varValue))
	if token, ok := attachment.(WFTextTokenAttachment); ok && token.Value.Type == Ask {
		token.Value.VariableName = ""
		return token
	}

	return attachment
}

func init() {
	enumerations["messagesTapbacks"] = []string{"Love", "Like", "Dislike", "Laugh At", "Emphasize", "Question"}
	enumerations["messagesInboxes"] = []string{"Messages", "Unknown Senders", "Spam", "Recently Deleted", "Unread", "Drafts", "Send Later"}

	actions["sendTapback"] = &actionDefinition{
		doc: selfDoc{
			title:       "Send Tapback",
			description: "Sends a Tapback reaction to `message`.",
			category:    "sharing",
			subcategory: "Email & SMS Messaging",
		},
		appIdentifier: messagesBundleIdentifier,
		identifier:    "SendMessageReactionIntent",
		appIntent:     messagesIntent("SendMessageReactionIntent"),
		minVersion:    27,
		parameters: []parameterDefinition{
			{
				name:      "tapback",
				validType: String,
				enum:      "messagesTapbacks",
			},
			{
				name:      "message",
				validType: Variable,
				key:       "message",
			},
		},
		appendParamsFunc: func(args []actionArgument) map[string]any {
			var params = make(map[string]any)
			if len(args) > 0 {
				if args[0].valueType == Variable {
					params["reaction"] = messagesVariableValue(args[0])
				} else {
					params["reaction"] = map[string]any{
						"value.which":    "WFLinkEnumerationContentItem_com.apple.MobileSMS_Tapback",
						"value.substate": messagesTapbackCodes[args[0].value.(string)],
					}
				}
			}

			// The picker key holds the same message as the visible parameter.
			if len(args) > 1 && args[1].valueType == Variable {
				params["WFLinkMessagesEntityVariablePickerKey"] = variableValue(args[1].value.(varValue))
			}

			return params
		},
	}

	actions["markConversationAsRead"] = &actionDefinition{
		doc: selfDoc{
			title:       "Mark Conversation as Read",
			description: "Marks `conversation` as read, or as unread when `unread` is true. `openWhenRun` opens Messages to do it.",
			category:    "sharing",
			subcategory: "Email & SMS Messaging",
		},
		appIdentifier: messagesBundleIdentifier,
		identifier:    "MarkConversationAsUnreadIntent",
		appIntent:     messagesIntent("MarkConversationAsUnreadIntent"),
		minVersion:    27,
		parameters: []parameterDefinition{
			{
				name:      "conversation",
				validType: Variable,
				key:       "conversation",
			},
			{
				name:         "unread",
				validType:    Bool,
				literal:      true,
				defaultValue: false,
				optional:     true,
			},
			{
				name:         "openWhenRun",
				validType:    Bool,
				key:          "OpenWhenRun",
				defaultValue: true,
				optional:     true,
			},
		},
		appendParamsFunc: func(args []actionArgument) map[string]any {
			var params = make(map[string]any)
			if len(args) > 1 {
				// The state is stored as a number, not a boolean.
				params["unreadState"] = 0
				if unread, ok := argumentValue(args, 1).(bool); ok && unread {
					params["unreadState"] = 1
				}
			}

			return params
		},
	}

	actions["openMessagesInbox"] = &actionDefinition{
		doc: selfDoc{
			title:       "Open Messages Inbox",
			description: "Opens Messages to one of its inboxes, such as Spam or Unread.",
			category:    "sharing",
			subcategory: "Email & SMS Messaging",
		},
		appIdentifier: messagesBundleIdentifier,
		identifier:    "ChangeFilterModeIntent",
		appIntent:     messagesIntent("ChangeFilterModeIntent"),
		minVersion:    27,
		parameters: []parameterDefinition{
			{
				name:      "inbox",
				validType: String,
				enum:      "messagesInboxes",
				literal:   true,
			},
		},
		appendParamsFunc: func(args []actionArgument) map[string]any {
			var params = make(map[string]any)
			if len(args) > 0 {
				var name = args[0].value.(string)
				var inbox = messagesInboxes[name]
				params["filterMode"] = map[string]any{
					"value":      inbox.mode,
					"title":      map[string]any{"key": name},
					"symbol":     map[string]any{"systemName": inbox.symbol},
					"identifier": inbox.mode,
					"subtitle":   map[string]any{"key": name},
				}
			}

			return params
		},
	}
}

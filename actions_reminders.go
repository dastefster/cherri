/*
 * Copyright (c) Cherri
 */

package main

// Reminders (com.apple.reminders) App Intents for lists, groups and sections, read from device exports. Shortcuts
// only writes a parameter that was touched, and the exports had no names for the new lists and sections, so only
// parameters seen in an export are defined. The rest stay blank in the action for the Shortcut's user to fill in.
const remindersBundleIdentifier = "com.apple.reminders"

// remindersIntent builds the app intent descriptor shared by the Reminders actions, varying only by identifier.
func remindersIntent(appIntentIdentifier string) appIntent {
	return appIntent{
		name:                "Reminders",
		bundleIdentifier:    remindersBundleIdentifier,
		appIntentIdentifier: appIntentIdentifier,
	}
}

// remindersAction defines a Reminders intent action, keeping the identifier and descriptor from drifting apart.
func remindersAction(title, description, intentIdentifier string, parameters []parameterDefinition) *actionDefinition {
	return &actionDefinition{
		doc: selfDoc{
			title:       title,
			description: description,
			category:    "calendar",
			subcategory: "Reminders",
		},
		appIdentifier: remindersBundleIdentifier,
		identifier:    intentIdentifier,
		appIntent:     remindersIntent(intentIdentifier),
		parameters:    parameters,
	}
}

func init() {
	actions["createReminderGroup"] = remindersAction(
		"Create Reminders Group",
		"Creates a group of lists named `name`. Pick the lists to put in it in the Shortcut.",
		"CreateGroupAppIntent",
		[]parameterDefinition{
			{name: "name", validType: String, key: "name", optional: true},
		},
	)

	actions["createReminderList"] = remindersAction(
		"Create Reminders List",
		"Creates a list in `group`. Pick the name in the Shortcut.",
		"TTRCreateListAppIntent",
		[]parameterDefinition{
			{name: "group", validType: Variable, key: "group", optional: true},
		},
	)

	actions["createReminderSection"] = remindersAction(
		"Create Reminders Section",
		"Creates a section in `list`. Pick the name in the Shortcut.",
		"CreateSectionAppIntent",
		[]parameterDefinition{
			{name: "list", validType: Variable, key: "list", optional: true},
		},
	)

	actions["updateReminderList"] = remindersAction(
		"Update Reminders List",
		"Renames `list` to `name`.",
		"UpdateListAppIntent",
		[]parameterDefinition{
			{name: "list", validType: Variable, key: "target", optional: true},
			{name: "name", validType: String, key: "name", optional: true},
		},
	)

	actions["deleteReminderGroups"] = remindersAction(
		"Delete Reminders Groups",
		"Deletes the groups in `groups`.",
		"DeleteRemindersListGroupsAppIntent",
		[]parameterDefinition{
			{name: "groups", validType: Variable, key: "entities", optional: true},
		},
	)

	actions["deleteReminderLists"] = remindersAction(
		"Delete Reminders Lists",
		"Deletes the lists in `lists`.",
		"DeleteListsAppIntent",
		[]parameterDefinition{
			{name: "lists", validType: Variable, key: "entities", optional: true},
		},
	)

	actions["deleteReminderSections"] = remindersAction(
		"Delete Reminders Sections",
		"Deletes the sections in `sections`.",
		"DeleteSectionsAppIntent",
		[]parameterDefinition{
			{name: "sections", validType: Variable, key: "entities", optional: true},
		},
	)

	actions["searchReminders"] = remindersAction(
		"Search Reminders",
		"Searches Reminders. Pick the search options in the Shortcut.",
		"TTRSearchRemindersAppIntent",
		nil,
	)
}

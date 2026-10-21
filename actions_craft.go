/*
 * Copyright (c) Cherri
 */

package main

import "strconv"

// Craft (com.lukilabs.lukiapp) actions, read from device exports of every action. Shortcuts only writes a
// parameter that was touched, and the exports had no Craft content to point the pickers at, so only parameters
// seen in an export are defined. The rest stay blank in the action for the Shortcut's user to fill in.
const (
	craftBundleIdentifier = "com.lukilabs.lukiapp"
	craftTeamIdentifier   = "LVV532B7S8"
)

// craftIntent builds the app intent descriptor shared by the Craft actions, varying only by identifier.
func craftIntent(appIntentIdentifier string) appIntent {
	return appIntent{
		name:                "Craft",
		bundleIdentifier:    craftBundleIdentifier,
		appIntentIdentifier: appIntentIdentifier,
		teamIdentifier:      craftTeamIdentifier,
	}
}

// craftAction defines a Craft action, keeping the identifier and descriptor from drifting apart.
func craftAction(title, description, intentIdentifier string, parameters []parameterDefinition) *actionDefinition {
	return &actionDefinition{
		doc: selfDoc{
			title:       title,
			description: description,
			category:    "documents",
			subcategory: "Craft",
		},
		appIdentifier: craftBundleIdentifier,
		identifier:    intentIdentifier,
		appIntent:     craftIntent(intentIdentifier),
		parameters:    parameters,
	}
}

func init() {
	actions["craftCreateDocument"] = craftAction(
		"Create Craft Document",
		"Creates a document in Craft with `title` and `content`. Pick the space and folder in the Shortcut.",
		"CreateDocumentAppIntent",
		[]parameterDefinition{
			{name: "title", validType: String, key: "title", optional: true},
			{name: "content", validType: String, key: "content", optional: true},
		},
	)

	actions["craftFindPage"] = craftAction(
		"Find Craft Page",
		"Finds pages in Craft titled `title`. Pick the space in the Shortcut.",
		"FindPageIntent",
		[]parameterDefinition{
			{name: "title", validType: String, key: "title", optional: true},
		},
	)

	actions["craftGetBlocks"] = craftAction(
		"Get Craft Blocks",
		"Gets `number` blocks from Craft. Pick the space in the Shortcut.",
		"GetBlocksAppIntent",
		[]parameterDefinition{
			{name: "number", validType: Integer, literal: true, optional: true},
		},
	)
	actions["craftGetBlocks"].appendParamsFunc = func(args []actionArgument) map[string]any {
		var params = make(map[string]any)
		if len(args) == 0 {
			return params
		}

		// Craft stores the count as text, not a number.
		if args[0].valueType == Variable {
			params["number"] = variableValue(args[0].value.(varValue))
		} else {
			params["number"] = strconv.Itoa(int(args[0].value.(int)))
		}

		return params
	}

	actions["craftAddToDocument"] = craftAction(
		"Add to Craft Document",
		"Adds to the Craft `document` passed in, such as the output of another Craft action.",
		"AddToDocumentAppIntent",
		[]parameterDefinition{
			{name: "document", validType: Variable, key: "document"},
		},
	)

	actions["craftAddSubpageToDocument"] = craftAction(
		"Add Subpage to Craft Document",
		"Adds a subpage to a Craft document. Pick the document in the Shortcut.",
		"AddSubpageToDocumentAppIntent",
		nil,
	)

	actions["craftDeleteDocument"] = craftAction(
		"Delete Craft Document",
		"Deletes a Craft document. Pick the document in the Shortcut.",
		"DeleteDocumentAppIntent",
		nil,
	)

	actions["craftMoveDocument"] = craftAction(
		"Move Craft Document",
		"Moves a Craft document. Pick the document and destination in the Shortcut.",
		"MoveDocumentAppIntent",
		nil,
	)

	actions["craftRenameDocument"] = craftAction(
		"Rename Craft Document",
		"Renames a Craft document. Pick the document and new title in the Shortcut.",
		"RenameDocumentAppIntent",
		nil,
	)

	actions["craftOpenDocument"] = craftAction(
		"Open Craft Document",
		"Opens a Craft document. Pick the document in the Shortcut.",
		"OpenDocumentAppIntent",
		nil,
	)

	actions["craftOpenDailyNote"] = craftAction(
		"Open Craft Daily Note",
		"Opens today's daily note in Craft.",
		"OpenDailyNoteIntent",
		nil,
	)

	actions["craftCreateFolder"] = craftAction(
		"Create Craft Folder",
		"Creates a folder in Craft named `name`. Pick the space in the Shortcut.",
		"CreateFolderAppIntent",
		[]parameterDefinition{
			{name: "name", validType: String, key: "name", optional: true},
		},
	)

	actions["craftRenameFolder"] = craftAction(
		"Rename Craft Folder",
		"Renames a Craft folder to `rename`. Pick the folder in the Shortcut.",
		"RenameFolderAppIntent",
		[]parameterDefinition{
			{name: "rename", validType: String, key: "rename", optional: true},
		},
	)

	actions["craftDeleteFolder"] = craftAction(
		"Delete Craft Folder",
		"Deletes a Craft folder. Pick the folder in the Shortcut.",
		"DeleteFolderAppIntent",
		nil,
	)

	actions["craftMoveFolder"] = craftAction(
		"Move Craft Folder",
		"Moves a Craft folder. Pick the folder and destination in the Shortcut.",
		"MoveFolderAppIntent",
		nil,
	)

	actions["craftOpenFolder"] = craftAction(
		"Open Craft Folder",
		"Opens a Craft folder. Pick the folder in the Shortcut.",
		"OpenFolderAppIntent",
		nil,
	)

	actions["craftOpenAndSearch"] = craftAction(
		"Open Craft and Search",
		"Opens Craft to its search.",
		"OpenAndSearchAppIntent",
		nil,
	)

	actions["craftOpenQuickEntry"] = craftAction(
		"Open Craft Quick Entry",
		"Opens Craft's quick entry. Pick the space and folder in the Shortcut.",
		"OpenQuickEntryAppIntent",
		nil,
	)

	actions["craftOpenTag"] = craftAction(
		"Open Craft Tag",
		"Opens a tag in Craft. Pick the tag in the Shortcut.",
		"OpenTagAppIntent",
		nil,
	)

	// Only the text is defined: the export also held a numeric type and a person picker that could not be named.
	actions["craftCreateReminder"] = craftAction(
		"Create Craft Reminder",
		"Creates a reminder in Craft with `text`. Pick the type and person in the Shortcut.",
		"CreateReminderAppIntent",
		[]parameterDefinition{
			{name: "text", validType: String, key: "text", optional: true},
		},
	)

	// The intent is named CreateTaskListIntent, but its export holds a single task's title and content.
	actions["craftCreateTask"] = craftAction(
		"Create Craft Task",
		"Creates a task in Craft with `title` and `content`. Pick the space in the Shortcut.",
		"CreateTaskListIntent",
		[]parameterDefinition{
			{name: "title", validType: String, key: "task", optional: true},
			{name: "content", validType: String, key: "content", optional: true},
		},
	)

	// The status is left out until its other values are known, since only "pending" has been seen.
	actions["craftSetTaskStatus"] = craftAction(
		"Set Craft Task Status",
		"Sets the status of a Craft task. Pick the task and status in the Shortcut.",
		"SetTaskStatusAppIntent",
		nil,
	)

	// The Notes, Reminders and Search actions below are the older Siri-style Craft intents, read from one device
	// export. They overlap the document actions above, so only text parameters and passed-in results are
	// defined; pickers for a note, list or reminder stay blank for the Shortcut's user to fill in.
	actions["craftAppendTextToNote"] = craftAction(
		"Append Text to Craft Note",
		"Appends `content` to a Craft note. Pick the note in the Shortcut.",
		"CraftNoteAppendTextIntent",
		[]parameterDefinition{
			{name: "content", validType: String, key: "content", optional: true},
		},
	)

	actions["craftCreateNote"] = craftAction(
		"Create Craft Note",
		"Creates a note in Craft named `name` with `content`.",
		"CraftCreateNoteIntent",
		[]parameterDefinition{
			{name: "name", validType: String, key: "name", optional: true},
			{name: "content", validType: String, key: "content", optional: true},
		},
	)

	// Craft has a second, document-based Create Reminder above; this one takes a list rather than a document.
	actions["craftCreateReminderInList"] = craftAction(
		"Create Craft Reminder in List",
		"Creates a reminder titled `title`. Pick the list in the Shortcut.",
		"CraftCreateReminderIntent",
		[]parameterDefinition{
			{name: "title", validType: String, key: "title", optional: true},
		},
	)

	actions["craftDeleteReminders"] = craftAction(
		"Delete Craft Reminders",
		"Deletes the Craft reminders passed in as `entities`, such as the output of Create Craft Reminder in List.",
		"CraftDeleteRemindersIntent",
		[]parameterDefinition{
			{name: "entities", validType: Variable, key: "entities", optional: true},
		},
	)

	// Shortcuts marks an entity query as needing the app installed, as it does for Menu Box's Find. The export
	// also held a folder filter, which is left for the Shortcut's user to set.
	actions["craftFindNote"] = craftAction(
		"Find Craft Notes",
		"Finds notes in Craft. Set the filter in the Shortcut.",
		"NoteAppEntity",
		nil,
	)
	actions["craftFindNote"].appIntent.requiresAppInstallation = true
	actions["craftFindNote"].outputType = Variable
	actions["craftFindNote"].outputName = "Note"

	actions["craftOpenNote"] = craftAction(
		"Open Craft Note",
		"Opens a Craft note. Pass a note from another action as `target`, or pick it in the Shortcut.",
		"CraftOpenNoteIntent",
		[]parameterDefinition{
			{name: "target", validType: Variable, key: "target", optional: true},
		},
	)

	// The intent is named CraftOpenTaskIntent, but it is the action Craft labels Open Reminder.
	actions["craftOpenReminder"] = craftAction(
		"Open Craft Reminder",
		"Opens a Craft reminder. Pass a reminder from another action as `target`, or pick it in the Shortcut.",
		"CraftOpenTaskIntent",
		[]parameterDefinition{
			{name: "target", validType: Variable, key: "target", optional: true},
		},
	)

	actions["craftSearchDocuments"] = craftAction(
		"Search Craft Documents",
		"Searches Craft for `criteria`.",
		"CraftSearchInAppIntent",
		[]parameterDefinition{
			{name: "criteria", validType: String, key: "criteria", optional: true},
		},
	)

	actions["craftUpdateNote"] = craftAction(
		"Update Craft Note",
		"Updates a Craft note. Pick the note in the Shortcut.",
		"CraftUpdateNoteIntent",
		nil,
	)

	// The flagged switch was also in the export, but as a bare boolean that is left for the Shortcut to set.
	actions["craftUpdateReminder"] = craftAction(
		"Update Craft Reminder",
		"Updates a Craft reminder with a `note`. Pick the reminder in the Shortcut.",
		"CraftUpdateReminderIntent",
		[]parameterDefinition{
			{name: "note", validType: String, key: "note", optional: true},
		},
	)

	// Only one destination was exported (type "2"), so the destination is left for the Shortcut to pick.
	actions["craftOpenTasksList"] = craftAction(
		"Open Craft Tasks List",
		"Opens a Craft tasks list such as the Inbox or Today. Pick the list in the Shortcut.",
		"OpenTaskListIntent",
		nil,
	)
}

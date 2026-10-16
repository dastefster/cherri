/*
 * Copyright (c) Cherri
 */

package main

import "strconv"

// Craft (com.lukilabs.lukiapp) Documents actions, read from device exports of every action. Shortcuts only writes
// a parameter that was touched, and the exports had no Craft content to point the document pickers at, so only
// parameters seen in an export are defined. The rest stay blank in the action for the Shortcut's user to fill in.
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

// craftDocumentAction defines a Craft Documents action, keeping the identifier and descriptor from drifting apart.
func craftDocumentAction(title, description, intentIdentifier string, parameters []parameterDefinition) *actionDefinition {
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
	actions["craftCreateDocument"] = craftDocumentAction(
		"Create Craft Document",
		"Creates a document in Craft with `title` and `content`. Pick the space and folder in the Shortcut.",
		"CreateDocumentAppIntent",
		[]parameterDefinition{
			{name: "title", validType: String, key: "title", optional: true},
			{name: "content", validType: String, key: "content", optional: true},
		},
	)

	actions["craftFindPage"] = craftDocumentAction(
		"Find Craft Page",
		"Finds pages in Craft titled `title`. Pick the space in the Shortcut.",
		"FindPageIntent",
		[]parameterDefinition{
			{name: "title", validType: String, key: "title", optional: true},
		},
	)

	actions["craftGetBlocks"] = craftDocumentAction(
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

	actions["craftAddToDocument"] = craftDocumentAction(
		"Add to Craft Document",
		"Adds to the Craft `document` passed in, such as the output of another Craft action.",
		"AddToDocumentAppIntent",
		[]parameterDefinition{
			{name: "document", validType: Variable, key: "document"},
		},
	)

	actions["craftAddSubpageToDocument"] = craftDocumentAction(
		"Add Subpage to Craft Document",
		"Adds a subpage to a Craft document. Pick the document in the Shortcut.",
		"AddSubpageToDocumentAppIntent",
		nil,
	)

	actions["craftDeleteDocument"] = craftDocumentAction(
		"Delete Craft Document",
		"Deletes a Craft document. Pick the document in the Shortcut.",
		"DeleteDocumentAppIntent",
		nil,
	)

	actions["craftMoveDocument"] = craftDocumentAction(
		"Move Craft Document",
		"Moves a Craft document. Pick the document and destination in the Shortcut.",
		"MoveDocumentAppIntent",
		nil,
	)

	actions["craftRenameDocument"] = craftDocumentAction(
		"Rename Craft Document",
		"Renames a Craft document. Pick the document and new title in the Shortcut.",
		"RenameDocumentAppIntent",
		nil,
	)

	actions["craftOpenDocument"] = craftDocumentAction(
		"Open Craft Document",
		"Opens a Craft document. Pick the document in the Shortcut.",
		"OpenDocumentAppIntent",
		nil,
	)

	actions["craftOpenDailyNote"] = craftDocumentAction(
		"Open Craft Daily Note",
		"Opens today's daily note in Craft.",
		"OpenDailyNoteIntent",
		nil,
	)
}

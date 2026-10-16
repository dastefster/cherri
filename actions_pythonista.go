/*
 * Copyright (c) Cherri
 */

package main

import (
	"fmt"
	"strings"
)

// Actions from Pythonista 3 (com.omz-software.Pythonista3), a third-party Python IDE. Unlike the App
// Intents providers in this package, Pythonista's actions are older SiriKit-style intents: they carry no
// AppIntentDescriptor and use plain camelCase parameter keys, so only the workflow identifier is needed.
//
// Pythonista only exists on iOS and iPadOS, so every definition here is nonMacOnly. Everything below was
// read from device exports; Shortcuts omits any parameter that was never touched, so the Cherri definitions
// only write what the caller passed.
const pythonistaBundleIdentifier = "com.omz-software.Pythonista3"

// Argument positions shared by the two Run actions.
const (
	pythonistaRunArgScript = iota
	pythonistaRunArgArguments
	pythonistaRunArgInputFiles
)

// pythonistaRunDoc builds the doc shared by the two Run actions, which only differ in where the code comes from.
func pythonistaRunDoc(title string, description string) selfDoc {
	return selfDoc{
		title: title,
		description: description + " `arguments` are passed to the script. `runInApp` opens Pythonista to run it, and " +
			"`returnToShortcuts` (only used when `runInApp` is on) switches back when it finishes. `showWhenRun` only " +
			"applies when `runInApp` is off, and the script output is only available to later actions in that case. " +
			"From the Pythonista app.",
		category:    "thirdparty",
		subcategory: "Pythonista",
	}
}

// pythonistaRunParameters lists the parameters after the code source, which are the same for both Run
// actions. The arguments list and the code source itself are built in pythonistaRunParams because Shortcuts
// writes them in shapes the automatic handling does not produce.
func pythonistaRunParameters(source parameterDefinition) []parameterDefinition {
	return []parameterDefinition{
		source,
		{
			name:      "arguments",
			validType: Arr,
			literal:   true,
			optional:  true,
		},
		{
			name:      "inputFiles",
			validType: Variable,
			key:       "inputFiles",
			optional:  true,
		},
		{
			name:         "runInApp",
			validType:    Bool,
			key:          "runInApp",
			defaultValue: false,
			optional:     true,
		},
		{
			name:         "returnToShortcuts",
			validType:    Bool,
			key:          "returnToShortcuts",
			defaultValue: false,
			optional:     true,
		},
		{
			name:         "showWhenRun",
			validType:    Bool,
			key:          "ShowWhenRun",
			defaultValue: true,
			optional:     true,
		},
	}
}

// pythonistaScriptPath builds the Script value. A variable is written as an attachment, and Ask Each Time
// as an attachment with only its type; unlike the standard actions, Pythonista's export has no VariableName.
func pythonistaScriptPath(arg actionArgument) any {
	if arg.valueType != Variable {
		return arg.value
	}

	var attachment = variableValue(arg.value.(varValue))
	if token, ok := attachment.(WFTextTokenAttachment); ok && token.Value.Type == Ask {
		token.Value.VariableName = ""

		return token
	}

	return attachment
}

// pythonistaRunParams builds the parameters of the two Run actions that automatic handling cannot.
// Shortcuts always writes inputFiles, as an empty list when nothing is connected; a single script argument is
// written as a bare value and two or more as a list, and each one is either plain text or a text token.
func pythonistaRunParams(args []actionArgument, build func(arg actionArgument) (key string, value any)) map[string]any {
	var params = map[string]any{
		"inputFiles": []any{},
	}
	if len(args) > pythonistaRunArgScript {
		var key, value = build(args[pythonistaRunArgScript])
		params[key] = value
	}
	if len(args) > pythonistaRunArgArguments && args[pythonistaRunArgArguments].valueType == Arr {
		var items = args[pythonistaRunArgArguments].value.([]interface{})
		var values = make([]any, 0, len(items))
		for _, item := range items {
			values = append(values, attachmentValues(fmt.Sprint(item)))
		}
		switch len(values) {
		case 0:
		case 1:
			params["scriptArguments"] = values[0]
		default:
			params["scriptArguments"] = values
		}
	}

	return params
}

func init() {
	actions["getPythonistaFile"] = &actionDefinition{
		doc: selfDoc{
			title: "Get Pythonista File",
			description: "Gets a file from the Pythonista library by `filename`, which can include subfolders. " +
				"Use the `icloud/` prefix for files in Pythonista's iCloud folder. With `errorIfNotFound` off the " +
				"shortcut continues when the file is missing. From the Pythonista app.",
			category:    "thirdparty",
			subcategory: "Pythonista",
		},
		appIdentifier: pythonistaBundleIdentifier,
		identifier:    "PA3ReadFileIntent",
		nonMacOnly:    true,
		parameters: []parameterDefinition{
			{
				name:      "filename",
				validType: String,
				key:       "filename",
			},
			{
				name:         "errorIfNotFound",
				validType:    Bool,
				key:          "errorIfNotFound",
				defaultValue: true,
				optional:     true,
			},
			{
				name:         "showWhenRun",
				validType:    Bool,
				key:          "ShowWhenRun",
				defaultValue: true,
				optional:     true,
			},
		},
		outputType: Variable,
		outputName: "File",
	}

	actions["runPythonistaScript"] = &actionDefinition{
		doc: pythonistaRunDoc(
			"Run Pythonista Script",
			"Runs a script from the Pythonista library. `script` is the path shown in the Shortcuts script picker "+
				"(for example `iCloud/script.py`), passed through exactly as written because a picked path can contain an "+
				"invisible U+2060 character. It can also be a whole variable or `Ask`, but not text with inline variables.",
		),
		appIdentifier: pythonistaBundleIdentifier,
		identifier:    "PA3RunScriptIntent",
		nonMacOnly:    true,
		defaultAction: true,
		parameters: pythonistaRunParameters(parameterDefinition{
			name:      "script",
			validType: String,
		}),
		check: func(args []actionArgument, _ *actionDefinition) {
			if len(args) > pythonistaRunArgScript && args[pythonistaRunArgScript].valueType == String &&
				strings.ContainsAny(args[pythonistaRunArgScript].value.(string), "{}") {
				parserError("Pythonista's script picker only accepts a path or a whole variable, not text with inline variables.")
			}
		},
		appendParamsFunc: func(args []actionArgument) map[string]any {
			return pythonistaRunParams(args, func(arg actionArgument) (string, any) {
				return "scriptPath", pythonistaScriptPath(arg)
			})
		},
		outputType: Variable,
		outputName: "Script Output",
	}

	actions["runPythonistaInlineScript"] = &actionDefinition{
		doc: pythonistaRunDoc(
			"Run Pythonista Inline Script",
			"Runs Python code written into the action instead of a library script. Use a raw string ('...') for `source` "+
				"so braces in the code are not read as variables.",
		),
		appIdentifier: pythonistaBundleIdentifier,
		identifier:    "PA3RunScriptIntent",
		nonMacOnly:    true,
		parameters: pythonistaRunParameters(parameterDefinition{
			name:      "source",
			validType: String,
		}),
		appendParams: map[string]any{
			"isInlineScript": true,
		},
		appendParamsFunc: func(args []actionArgument) map[string]any {
			return pythonistaRunParams(args, func(arg actionArgument) (string, any) {
				return "inlineScriptSource", paramValue(arg, String)
			})
		},
		outputType: Variable,
		outputName: "Script Output",
	}

	actions["addPythonistaFile"] = &actionDefinition{
		doc: selfDoc{
			title: "Add Pythonista File",
			description: "Adds `file` to the Pythonista library as `filename`, which can include subfolders. " +
				"Use the `icloud/` prefix for Pythonista's iCloud folder. With `overwrite` off an existing file is kept. " +
				"From the Pythonista app.",
			category:    "thirdparty",
			subcategory: "Pythonista",
		},
		appIdentifier: pythonistaBundleIdentifier,
		identifier:    "PA3AddFileIntent",
		nonMacOnly:    true,
		parameters: []parameterDefinition{
			{
				name:      "file",
				validType: Variable,
				key:       "file",
			},
			{
				name:      "filename",
				validType: String,
				key:       "filename",
			},
			{
				name:         "overwrite",
				validType:    Bool,
				key:          "overwrite",
				defaultValue: false,
				optional:     true,
			},
			{
				name:         "showWhenRun",
				validType:    Bool,
				key:          "ShowWhenRun",
				defaultValue: true,
				optional:     true,
			},
		},
	}
}

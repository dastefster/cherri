// ===================================
// Cherri Action Catalog
// v0.0.1 BUILD 2026-10-15 13:52
// Exports every standard Cherri action as JSON so the app can build its action picker and parameter help.
// dev by @dastefster 🍒🔨
// ===================================

package cherrilib

import (
	"encoding/json"
	"fmt"
	"sort"
	"strings"
)

// ===================================
// CATALOG SHAPE
// ===================================

type catalogParam struct {
	Name     string   `json:"name"`
	Type     string   `json:"type"`
	Values   []string `json:"values,omitempty"`
	Optional bool     `json:"optional,omitempty"`
	Literal  bool     `json:"literal,omitempty"`
	Repeats  bool     `json:"repeats,omitempty"`
	Qty      bool     `json:"qty,omitempty"`
	Default  string   `json:"default,omitempty"`
}

type catalogAction struct {
	Name        string         `json:"name"`
	Title       string         `json:"title,omitempty"`
	Description string         `json:"description,omitempty"`
	Warning     string         `json:"warning,omitempty"`
	Category    string         `json:"category"`
	Subcategory string         `json:"subcategory,omitempty"`
	Params      []catalogParam `json:"params"`
	Returns     string         `json:"returns,omitempty"`
	MacOnly     bool           `json:"macOnly,omitempty"`
	NonMacOnly  bool           `json:"nonMacOnly,omitempty"`
	MinVersion  float64        `json:"minVersion,omitempty"`
	MaxVersion  float64        `json:"maxVersion,omitempty"`
}

type catalogCategory struct {
	ID    string `json:"id"`
	Title string `json:"title"`
}

type catalog struct {
	CompilerVersion string            `json:"compilerVersion"`
	Categories      []catalogCategory `json:"categories"`
	Actions         []catalogAction   `json:"actions"`
}

// ===================================
// CATEGORIES
// ===================================

// Same display names the upstream docs generator uses.
func categoryTitle(id string) string {
	switch id {
	case "pdf":
		return "PDF"
	case "a11y":
		return "Accessibility"
	case "intelligence":
		return "Apple Intelligence"
	case "thirdparty":
		return "Third-Party Apps"
	}
	if id == "" {
		return id
	}

	return strings.ToUpper(id[:1]) + id[1:]
}

// Actions written in Cherri don't record which file they came from when everything is loaded at once, so this
// reads the embedded action files and matches each `action ...` line to a registered action name.
func categoriesFromFiles() map[string]string {
	var result = map[string]string{}
	var entries, dirErr = stdActions.ReadDir("actions")
	if dirErr != nil {
		return result
	}

	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".cherri") {
			continue
		}
		var category = strings.TrimSuffix(entry.Name(), ".cherri")
		var data, readErr = stdActions.ReadFile("actions/" + entry.Name())
		if readErr != nil {
			continue
		}

		for _, line := range strings.Split(string(data), "\n") {
			if !strings.HasPrefix(line, "action ") {
				continue
			}
			var fields = strings.Fields(line)

			// Toggle sets generate a `set` and a `toggle` action from one line, named after the last word.
			if len(fields) > 2 && fields[1] == "toggleSet" {
				for _, token := range fields[2:] {
					if strings.HasPrefix(token, "'") || token == "mac" || token == "!mac" {
						continue
					}
					if cut := strings.IndexAny(token, "([{"); cut >= 0 {
						token = token[:cut]
					}
					for _, prefix := range []string{"set", "toggle"} {
						if _, registered := actions[prefix+token]; registered {
							result[prefix+token] = category
						}
					}
					break
				}
				continue
			}

			for _, token := range fields[1:] {
				// Quoted tokens are short identifiers, which can coincide with a real action name.
				if strings.HasPrefix(token, "'") {
					continue
				}
				if cut := strings.IndexAny(token, "(:{"); cut >= 0 {
					token = token[:cut]
				}
				if _, registered := actions[token]; registered {
					result[token] = category
					break
				}
			}
		}
	}

	return result
}

// ===================================
// EXPORT
// ===================================

// ActionCatalog returns every standard action, with its parameters and allowed values, as a JSON document.
func ActionCatalog() (result string, err error) {
	compileLock.Lock()
	defer compileLock.Unlock()

	var restoreOutput = captureOutput()
	var failure any
	func() {
		defer func() { failure = recover() }()

		prepareArgs("")
		ensureStandardActions()
	}()
	var output = strings.TrimSpace(restoreOutput())
	resetParser()

	if failure != nil {
		return "", fmt.Errorf("could not load actions: %v\n%s", failure, output)
	}

	var fileCategories = categoriesFromFiles()
	var seenCategories = map[string]bool{}
	var list = []catalogAction{}

	for name, def := range actions {
		var category = def.doc.category
		if category == "" {
			category = fileCategories[name]
		}
		if category == "" {
			category = "other"
		}
		seenCategories[category] = true

		var params = []catalogParam{}
		for _, param := range def.parameters {
			var entry = catalogParam{
				Name:     param.name,
				Type:     string(param.validType),
				Optional: param.optional,
				Literal:  param.literal,
				Repeats:  param.infinite,
				Qty:      param.qty,
			}
			if param.enum != "" {
				entry.Type = param.enum
				entry.Values = getEnum(param.enum)
			}
			if param.defaultValue != nil {
				entry.Default = fmt.Sprintf("%v", param.defaultValue)
			}
			params = append(params, entry)
		}

		list = append(list, catalogAction{
			Name:        name,
			Title:       def.doc.title,
			Description: def.doc.description,
			Warning:     def.doc.warning,
			Category:    category,
			Subcategory: def.doc.subcategory,
			Params:      params,
			Returns:     string(def.outputType),
			MacOnly:     def.macOnly,
			NonMacOnly:  def.nonMacOnly,
			MinVersion:  def.minVersion,
			MaxVersion:  def.maxVersion,
		})
	}

	sort.Slice(list, func(i, j int) bool {
		if list[i].Category != list[j].Category {
			return list[i].Category < list[j].Category
		}
		return list[i].Name < list[j].Name
	})

	var categories = []catalogCategory{}
	for id := range seenCategories {
		categories = append(categories, catalogCategory{ID: id, Title: categoryTitle(id)})
	}
	sort.Slice(categories, func(i, j int) bool { return categories[i].Title < categories[j].Title })

	var encoded, jsonErr = json.Marshal(catalog{CompilerVersion: version, Categories: categories, Actions: list})
	if jsonErr != nil {
		return "", jsonErr
	}

	return string(encoded), nil
}

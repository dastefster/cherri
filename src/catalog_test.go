// ===================================
// Cherri Action Catalog Tests
// v0.0.1 BUILD 2026-10-15 13:52
// Checks the catalog export is valid JSON, covers the standard actions, and stays consistent with Compile.
// dev by @dastefster 🍒🔨
// ===================================

package cherrilib

import (
	"encoding/json"
	"testing"
)

// ===================================
// TESTS
// ===================================

func TestActionCatalog(t *testing.T) {
	var raw, err = ActionCatalog()
	if err != nil {
		t.Fatal(err)
	}

	var parsed catalog
	if jsonErr := json.Unmarshal([]byte(raw), &parsed); jsonErr != nil {
		t.Fatalf("catalog is not valid JSON: %v", jsonErr)
	}
	if len(parsed.Actions) < 300 {
		t.Fatalf("expected hundreds of actions, got %d", len(parsed.Actions))
	}

	var byName = map[string]catalogAction{}
	var uncategorized []string
	for _, action := range parsed.Actions {
		byName[action.Name] = action
		if action.Category == "other" {
			uncategorized = append(uncategorized, action.Name)
		}
	}

	for _, name := range []string{"alert", "getText", "downloadURL"} {
		if _, found := byName[name]; !found {
			t.Errorf("expected action %s in the catalog", name)
		}
	}
	t.Logf("%d actions, %d categories, %d uncategorized, %d bytes", len(parsed.Actions), len(parsed.Categories), len(uncategorized), len(raw))
	if len(uncategorized) > 0 {
		t.Logf("uncategorized: %v", uncategorized)
	}
	t.Logf("alert: %+v", byName["alert"])
}

// Loading actions for the catalog must not break compiling afterward, in either order.
func TestCatalogThenCompile(t *testing.T) {
	if _, err := ActionCatalog(); err != nil {
		t.Fatal(err)
	}
	var out, err = Compile("alert(\"hi\")\n", "Shortcut")
	if err != nil {
		t.Fatal(err)
	}
	if !looksLikeShortcut(out) {
		t.Fatal("compile after catalog did not produce a Shortcut")
	}
	if _, err := ActionCatalog(); err != nil {
		t.Fatalf("catalog after compile failed: %v", err)
	}
}

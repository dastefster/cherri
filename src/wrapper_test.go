// ===================================
// Cherri Library Wrapper Tests
// v0.0.2 BUILD 2026-10-15 01:45
// Runs upstream's Cherri test files through Compile() and checks errors come back instead of killing the process.
// dev by @dastefster 🍒🔨
// ===================================

package cherrilib

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// ===================================
// HELPERS
// ===================================

func looksLikeShortcut(b []byte) bool {
	return strings.HasPrefix(string(b), "<?xml") && strings.Contains(string(b), "WFWorkflowActions")
}

// Files that only make sense next to other files on disk. An app compiles a single text buffer, so these can't apply.
var needsDiskFiles = map[string]string{
	"include.cherri":  "includes a sibling file",
	"includes.cherri": "includes a sibling file",
	"menus.cherri":    "reads an icon from assets/",
}

// ===================================
// TESTS
// ===================================

func TestUpstreamSuite(t *testing.T) {
	var upstream = os.Getenv("CHERRI_UPSTREAM")
	if upstream == "" {
		t.Skip("set CHERRI_UPSTREAM to a Cherri checkout")
	}

	var files, globErr = filepath.Glob(filepath.Join(upstream, "tests", "*.cherri"))
	if globErr != nil || len(files) == 0 {
		t.Fatalf("no test files found under %s", upstream)
	}

	var failed int
	for _, file := range files {
		var base = filepath.Base(file)
		if base == "decomp-expected.cherri" || base == "decomp-me.cherri" {
			continue
		}
		if reason, skip := needsDiskFiles[base]; skip {
			t.Logf("skipping %s: %s", base, reason)
			continue
		}

		var source, readErr = os.ReadFile(file)
		if readErr != nil {
			t.Fatal(readErr)
		}

		var result, compileErr = Compile(string(source), strings.TrimSuffix(base, ".cherri"))
		if compileErr != nil {
			failed++
			t.Errorf("%s failed:\n%s", base, compileErr)
			continue
		}
		if !looksLikeShortcut(result) {
			failed++
			t.Errorf("%s: output does not look like a Shortcut (%d bytes)", base, len(result))
		}
	}

	t.Logf("%d test files, %d failed", len(files), failed)
}

func TestErrorReturnsInsteadOfExiting(t *testing.T) {
	var _, err = Compile("thisActionDoesNotExist(\"x\")\n", "Broken")
	if err == nil {
		t.Fatal("expected an error for an undefined action")
	}
	t.Logf("error text: %s", err)

	// If the process was still alive and clean, compiling again must work.
	var result, goodErr = Compile("alert(\"hi\")\n", "Fine")
	if goodErr != nil || !looksLikeShortcut(result) {
		t.Fatalf("compile after an error failed: %v", goodErr)
	}
}

func TestNoStateLeakBetweenCompiles(t *testing.T) {
	var first = "@name = \"a\"\nalert(\"{@name}\")\n"
	var second = "const n = 5\nshow(\"{n}\")\n"

	for i := 0; i < 3; i++ {
		for _, source := range []string{first, second} {
			var result, err = Compile(source, "Loop")
			if err != nil || !looksLikeShortcut(result) {
				t.Fatalf("round %d failed: %v", i, err)
			}
		}
	}
}

func TestCompilerVersion(t *testing.T) {
	if CompilerVersion() == "" {
		t.Fatal("empty version")
	}
	t.Logf("Cherri %s", CompilerVersion())
}

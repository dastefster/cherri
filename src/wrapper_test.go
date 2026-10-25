// ===================================
// Cherri Library Wrapper Tests
// v0.0.5 BUILD 2026-10-25 04:50
// Runs upstream's Cherri test files through Compile() and checks errors come back instead of killing the process. Also round-trips Decompile().
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

// ===================================
// DECOMPILE TESTS
// ===================================

func TestDecompileRoundTrip(t *testing.T) {
	var source = "#define name Round Trip\nconst greeting = \"hello\"\nalert(\"{greeting}\", \"Hi\")\n"

	var compiled, compileErr = Compile(source, "Round Trip")
	if compileErr != nil {
		t.Fatalf("compile failed: %v", compileErr)
	}

	var code, decompileErr = Decompile(compiled, "Round Trip")
	if decompileErr != nil {
		t.Fatalf("decompile failed: %v", decompileErr)
	}
	t.Logf("decompiled:\n%s", code)

	if !strings.Contains(code, "alert(") || !strings.Contains(code, "hello") {
		t.Fatalf("decompiled code lost the actions: %s", code)
	}

	// The decompiled code has to compile again, or import would hand the user a broken editor.
	var _, recompileErr = Compile(code, "Round Trip")
	if recompileErr != nil {
		t.Fatalf("decompiled code does not recompile: %v", recompileErr)
	}
}

// The Scriptable Run actions keep their arguments outside the parameter keys, so the importer once dropped the
// script and produced a call that could not compile. Round-trip every optional argument to keep that fixed.
func TestDecompileScriptableRoundTrip(t *testing.T) {
	var source = "#define name Scriptable\n#define mac false\n" +
		"@who = \"Stefan\"\n" +
		"const out = runScriptableInlineScript('const n = args.plainTexts[0];\\nScript.setShortcutOutput(\"it\\'s \" + n);', nil, [\"{@who}\", \"two\"], nil, nil, nil, true, false)\n" +
		"alert(\"{out}\", \"Done\")\n"

	var compiled, compileErr = Compile(source, "Scriptable")
	if compileErr != nil {
		t.Fatalf("compile failed: %v", compileErr)
	}

	var code, decompileErr = Decompile(compiled, "Scriptable")
	if decompileErr != nil {
		t.Fatalf("decompile failed: %v", decompileErr)
	}
	t.Logf("decompiled:\n%s", code)

	if !strings.Contains(code, "Script.setShortcutOutput") || !strings.Contains(code, "plainTexts[0]") {
		t.Fatalf("decompiled code lost the script: %s", code)
	}

	var again, recompileErr = Compile(code, "Scriptable")
	if recompileErr != nil {
		t.Fatalf("decompiled code does not recompile: %v", recompileErr)
	}
	var redecompiled, _ = Decompile(again, "Scriptable")
	if redecompiled != code {
		t.Fatalf("decompile is not stable across a recompile:\n--- first\n%s\n--- second\n%s", code, redecompiled)
	}
}

// Decompiling a shortcut with an action the compiler doesn't know loads an extra action file. That used to leave
// its enums behind, so the next import of the same kind failed with "Duplicate enumeration".
func TestDecompileRepeatedUnknownAction(t *testing.T) {
	var unknown = []byte(`<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>WFWorkflowActions</key><array><dict>
<key>WFWorkflowActionIdentifier</key><string>AsheKube.app.a-Shell.ExecuteCommandIntent</string>
<key>WFWorkflowActionParameters</key><dict><key>UUID</key><string>5D879823-DF04-43BC-A34A-F582298CE7EF</string></dict>
</dict></array>
<key>WFWorkflowClientVersion</key><string>5037.111</string>
<key>WFWorkflowIcon</key><dict><key>WFWorkflowIconGlyphNumber</key><integer>61440</integer><key>WFWorkflowIconStartColor</key><integer>946986751</integer></dict>
<key>WFWorkflowMinimumClientVersion</key><integer>900</integer>
<key>WFWorkflowTypes</key><array/>
</dict></plist>`)

	for i := 0; i < 4; i++ {
		var code, err = Decompile(unknown, "Execute Command")
		if err != nil {
			t.Fatalf("import %d failed: %v", i+1, err)
		}
		if !strings.Contains(code, "ExecuteCommandIntent") {
			t.Fatalf("import %d lost the action: %s", i+1, code)
		}
	}

	// Compiling afterwards must still work with the state restored.
	if _, err := Compile("#define name After\nalert(\"x\")\n", "After"); err != nil {
		t.Fatalf("compile after repeated imports failed: %v", err)
	}
}

func TestDecompileRejectsGarbageAndSigned(t *testing.T) {
	if _, err := Decompile([]byte("nope"), "x"); err == nil {
		t.Fatal("expected an error for too-short input")
	}
	if _, err := Decompile([]byte("AEA1\x00\x00\x00\x00\x00\x00\x00\x00"), "x"); err == nil {
		t.Fatal("expected an error for a signed Shortcut")
	}
}

func TestDecompileUpstreamShortcuts(t *testing.T) {
	var files, _ = filepath.Glob("../../cherri-src/tests/*_unsigned.shortcut")
	if len(files) == 0 {
		t.Skip("no sample shortcuts found")
	}

	var passed, failed int
	for _, file := range files {
		var data, readErr = os.ReadFile(file)
		if readErr != nil {
			continue
		}

		var code, err = Decompile(data, "Sample")
		if err != nil {
			failed++
			t.Logf("FAIL %s: %.160s", filepath.Base(file), strings.ReplaceAll(err.Error(), "\n", " "))
			continue
		}

		passed++
		_ = code
	}
	t.Logf("decompiled %d of %d sample shortcuts", passed, passed+failed)
}

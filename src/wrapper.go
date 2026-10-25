// ===================================
// Cherri Library Wrapper
// v0.0.7 BUILD 2026-10-25 05:35
// Exposes the Cherri compiler as a library so gomobile can bind it into a Swift app.
// dev by @dastefster 🍒🔨
// ===================================

package cherrilib

import (
	"fmt"
	"io"
	"maps"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"sync"

	"github.com/electrikmilk/args-parser"
)

// ===================================
// EXIT INTERCEPTION
// ===================================

// exitSignal stands in for os.Exit inside the compiler. A real exit would kill the host app on the first
// typo in the user's code, so it unwinds back to Compile instead.
type exitSignal struct {
	code int
}

// cherriExit is what build.sh rewrites every os.Exit call in the compiler to.
func cherriExit(code int) {
	panic(exitSignal{code: code})
}

// ===================================
// OUTPUT CAPTURE
// ===================================

// captureOutput redirects stdout, because the compiler prints its errors instead of returning them.
// The returned function restores stdout and gives back everything that was printed.
func captureOutput() (restore func() string) {
	var original = os.Stdout
	var reader, writer, pipeErr = os.Pipe()
	if pipeErr != nil {
		return func() string { return "" }
	}

	os.Stdout = writer

	// Read concurrently so a chatty compile can't fill the pipe and block forever.
	var done = make(chan string)
	go func() {
		var captured, _ = io.ReadAll(reader)
		done <- string(captured)
	}()

	return func() string {
		_ = writer.Close()
		os.Stdout = original

		return <-done
	}
}

// ===================================
// COMPILE
// ===================================

// The compiler keeps its state in package globals, so only one compile can run at a time.
var compileLock sync.Mutex

var unsafeNameChars = regexp.MustCompile(`[^A-Za-z0-9 _-]`)

// Every standard action is loaded once and stays loaded, the same way upstream's test suite does it. Including
// them again per compile would re-register their enums and actions, which the compiler rejects as duplicates.
var standardActionsLoaded bool

var standardIncludeLine = regexp.MustCompile(`(?m)^[ \t]*#include[ \t]+'actions/[^']*'.*$`)

// ensureStandardActions loads the standard actions the first time anything needs them.
func ensureStandardActions() {
	if !standardActionsLoaded {
		loadStandardActions()
		baselineIncluded = slices.Clone(included)
		standardActionsLoaded = true
	}
}

// baselineIncluded is the list of action files the compiler counts as already included once the standard library
// has loaded. The compiler skips those when it goes looking for an unknown action, so a reset that empties the list
// makes the next run include them a second time and fail with "Duplicate enumeration".
var baselineIncluded []string

// resetState clears the compiler's global state between runs, but keeps what the loaded standard library needs.
func resetState() {
	resetParser()
	included = slices.Clone(baselineIncluded)
}

// CompilerVersion returns the version of the Cherri compiler this library was built from.
func CompilerVersion() string {
	return version
}

// Compile turns Cherri source into an unsigned Shortcut file (XML plist). `name` becomes the Shortcut's name.
// Signing is a separate step because it needs the network on iOS.
func Compile(source string, name string) (result []byte, err error) {
	compileLock.Lock()
	defer compileLock.Unlock()

	name = strings.TrimSpace(unsafeNameChars.ReplaceAllString(name, ""))
	if name == "" {
		name = "Shortcut"
	}

	var dir, dirErr = os.MkdirTemp("", "cherri")
	if dirErr != nil {
		return nil, dirErr
	}
	defer os.RemoveAll(dir)

	var sourcePath = filepath.Join(dir, name+".cherri")
	// Blanked rather than removed so error line numbers still match what the user typed.
	source = standardIncludeLine.ReplaceAllString(source, "")

	if writeErr := os.WriteFile(sourcePath, []byte(source), 0600); writeErr != nil {
		return nil, writeErr
	}

	var restoreOutput = captureOutput()
	var failure any
	func() {
		defer func() { failure = recover() }()

		prepareArgs(sourcePath)
		ensureStandardActions()
		main()
	}()
	var output = strings.TrimSpace(restoreOutput())

	// A failed compile leaves half-built state behind, so reset either way like the test suite does.
	resetState()

	if failure != nil {
		if exit, exited := failure.(exitSignal); !exited || exit.code != 0 {
			if exited {
				return nil, fmt.Errorf("%s", output)
			}

			return nil, fmt.Errorf("internal compiler error: %v\n%s", failure, output)
		}
	}

	// A #define name in the source renames the output file, so look for it instead of assuming the name.
	var outputs, _ = filepath.Glob(filepath.Join(dir, "*"+unsignedEnd))
	if len(outputs) == 0 {
		return nil, fmt.Errorf("compiler produced no Shortcut: %s", output)
	}

	var shortcutBytes, readErr = os.ReadFile(outputs[0])
	if readErr != nil {
		return nil, readErr
	}

	return shortcutBytes, nil
}

// prepareArgs sets up the argument state main() reads, which normally comes from the command line.
func prepareArgs(sourcePath string) {
	os.Args = []string{"cherri", sourcePath}

	for key := range args.Args {
		delete(args.Args, key)
	}
	args.Args["no-ansi"] = ""
	args.Args["skip-sign"] = ""
	// The toolkit database is a macOS file the compiler consults when it meets an action it doesn't know. The phone
	// has no such file, so skip it everywhere and every platform behaves the same.
	args.Args["no-toolkit"] = ""
}

// ===================================
// DECOMPILE
// ===================================

// Decompile turns an unsigned Shortcut file (XML or binary plist) back into Cherri source for the import feature.
// `name` only names the temporary output; the Shortcut's own name comes back as a #define inside the source.
func Decompile(shortcutBytes []byte, name string) (result string, err error) {
	compileLock.Lock()
	defer compileLock.Unlock()

	// hasSignedBytes reads the first eight bytes, so anything shorter can't be a Shortcut at all.
	if len(shortcutBytes) < 8 {
		return "", fmt.Errorf("that doesn't look like a Shortcut file")
	}
	if hasSignedBytes(shortcutBytes) {
		return "", fmt.Errorf("signed Shortcuts can't be imported, use an iCloud link instead")
	}

	name = strings.TrimSpace(unsafeNameChars.ReplaceAllString(name, ""))
	if name == "" {
		name = "Shortcut"
	}

	var dir, dirErr = os.MkdirTemp("", "cherri")
	if dirErr != nil {
		return "", dirErr
	}
	defer os.RemoveAll(dir)

	var restoreOutput = captureOutput()
	var failure any
	func() {
		defer func() { failure = recover() }()

		prepareArgs(filepath.Join(dir, name+".cherri"))
		// decompile() writes its result to a file, so point that at the temp folder.
		args.Args["output"] = dir + "/"
		// The Shortcuts app names every output after its action, so one shortcut often has many outputs called
		// "Dictionary". The compiler only renames duplicates when this flag is set, which the CLI's own import does.
		args.Args["import"] = ""
		ensureStandardActions()

		// Meeting an action it doesn't know makes the decompiler load another action file, which registers that
		// file's enums and actions in globals the reset below never clears. The next import that reaches the same
		// file then fails with "Duplicate enumeration", so put both back the way they were when this import ends.
		var actionsBefore = maps.Clone(actions)
		var enumerationsBefore = maps.Clone(enumerations)
		defer func() {
			actions = actionsBefore
			enumerations = enumerationsBefore
		}()

		basename = name
		decompile(shortcutBytes)
	}()
	var output = strings.TrimSpace(restoreOutput())

	resetState()

	if failure != nil {
		if exit, exited := failure.(exitSignal); !exited || exit.code != 0 {
			if exited {
				return "", fmt.Errorf("%s", output)
			}

			return "", fmt.Errorf("internal decompiler error: %v\n%s", failure, output)
		}
	}

	var outputs, _ = filepath.Glob(filepath.Join(dir, "*.cherri"))
	if len(outputs) == 0 {
		return "", fmt.Errorf("decompiler produced no code: %s", output)
	}

	var codeBytes, readErr = os.ReadFile(outputs[0])
	if readErr != nil {
		return "", readErr
	}

	return string(codeBytes), nil
}

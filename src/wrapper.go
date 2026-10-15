// ===================================
// Cherri Library Wrapper
// v0.0.3 BUILD 2026-10-15 13:45
// Exposes the Cherri compiler as a library so gomobile can bind it into a Swift app.
// dev by @dastefster 🍒🔨
// ===================================

package cherrilib

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
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
		standardActionsLoaded = true
	}
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
	resetParser()

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
}

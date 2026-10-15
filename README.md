# Cherri app: Go wrapper

Turns a Cherri checkout into a library (`cherrilib`) that a Swift app can call through gomobile. Upstream Cherri is never modified: `build.sh` copies it into `build/cherrilib/` and rewrites the copy.

## Use

```bash
git clone --depth 1 --branch add-messages-actions https://github.com/dastefster/cherri cherri-src

# Library plus tests
./build.sh ./cherri-src
cd build/cherrilib && CHERRI_UPSTREAM=../../cherri-src go test -count=1 ./...

# iOS framework (needs Xcode and gomobile)
./bind.sh ./cherri-src
```

`bind.sh` writes `Cherri.xcframework`. Swift calls `CherriCompile(source, name, &error)` and `CherriCompilerVersion()`.

## What `build.sh` rewrites

1. `package main` becomes `package cherrilib`, since gomobile can only bind a library package.
2. Every `os.Exit(` becomes `cherriExit(`, which unwinds back to `Compile` so a typo can't kill the app.
3. Unused `"os"` imports left behind are removed.
4. `checkMissingStandardInclude` returns early while parsing, because every standard action is already loaded and the lookup would re-register enums and hide the real "Undefined action" error.
5. `resetParser()` is extracted from upstream's `cherri_test.go` so the global-state reset never drifts from upstream.

## Why there is a `bind` package

gomobile wraps every exported name in the package it is given, and the compiler exports internal constants it can't convert (`unsupported const type untyped rune for ObjectReplaceChar`). `src/bind.go` is a thin front door that exports only `Compile` and `CompilerVersion`, and that is the package gomobile binds.

## API

`Compile(source, name string) ([]byte, error)` returns the unsigned Shortcut plist, or the compiler's own error text with line and column. `CompilerVersion() string` returns the Cherri version.

Signing is a separate step. macOS signs with `shortcuts sign`; elsewhere Cherri falls back to the HubSign web service, which needs the network.

#!/usr/bin/env bash
# ===================================
# Cherri Library Build
# v0.0.2 BUILD 2026-10-15 01:42
# Copies a Cherri checkout into build/cherrilib and turns it into an importable, non-fatal library.
# dev by @dastefster 🍒🔨
# ===================================

set -euo pipefail

# ===================================
# SETUP
# ===================================

UPSTREAM="${1:?usage: build.sh /path/to/cherri}"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/build/cherrilib"

rm -rf "$OUT"
mkdir -p "$OUT"

# ===================================
# COPY UPSTREAM
# ===================================

cp "$UPSTREAM"/*.go "$OUT"/
rm -f "$OUT"/*_test.go
cp -r "$UPSTREAM"/actions "$OUT"/actions
cp "$UPSTREAM"/stdfunc.cherri "$UPSTREAM"/go.mod "$UPSTREAM"/go.sum "$OUT"/

# ===================================
# REWRITE
# ===================================

# perl instead of sed -i, because macOS and Linux disagree on sed's in-place syntax and perl behaves the same on both.
# gomobile can only bind a library package, and a real os.Exit would kill the host app.
perl -pi -e 's/^package main$/package cherrilib/' "$OUT"/*.go
perl -pi -e 's/os\.Exit\(/cherriExit(/g' "$OUT"/*.go
perl -pi -e 's#^module .*#module cherrilib#' "$OUT"/go.mod

# Some files only used "os" for os.Exit, which leaves an unused import behind.
for file in "$OUT"/*.go; do
  if ! grep -qE '(^|[^A-Za-z0-9_])os\.[A-Za-z]' "$file"; then
    perl -ni -e 'print unless /^\s*"os"$/' "$file"
  fi
done

# Every standard action is already loaded, so the "requires include" lookup can only re-register them and
# bury the real "Undefined action" error under a duplicate enumeration error.
perl -pi -e 's/^(func checkMissingStandardInclude\(identifier \*string, parsing bool\) \{)$/$1\n\tif parsing {\n\t\treturn\n\t}\n/' "$OUT"/actions_std.go

# The reset between compiles lives in upstream's test file, so extract it and it can never drift from upstream.
{
  echo "package cherrilib"
  echo
  awk '/^func resetParser\(\) \{/,/^}/' "$UPSTREAM"/cherri_test.go
} > "$OUT"/reset_gen.go

# ===================================
# ADD WRAPPER
# ===================================

cp "$HERE"/src/wrapper.go "$HERE"/src/wrapper_test.go "$OUT"/

echo "built $OUT"

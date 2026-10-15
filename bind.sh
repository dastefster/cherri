#!/usr/bin/env bash
# ===================================
# Cherri Framework Build
# v0.0.1 BUILD 2026-10-15 01:58
# Builds the library, then binds it with gomobile into Cherri.xcframework for the iOS app.
# dev by @dastefster 🍒🔨
# ===================================

set -euo pipefail

# ===================================
# SETUP
# ===================================

UPSTREAM="${1:?usage: bind.sh /path/to/cherri}"
HERE="$(cd "$(dirname "$0")" && pwd)"
export PATH="$PATH:$(go env GOPATH)/bin"

# ===================================
# BUILD
# ===================================

"$HERE"/build.sh "$UPSTREAM"

cd "$HERE"/build/cherrilib

# build.sh regenerates go.mod every run, so gomobile's runtime package has to be added back each time.
go get golang.org/x/mobile/bind

rm -rf "$HERE"/Cherri.xcframework
gomobile bind -target=ios,iossimulator -o "$HERE"/Cherri.xcframework cherrilib/bind

echo "built $HERE/Cherri.xcframework"

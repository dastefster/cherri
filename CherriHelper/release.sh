#!/bin/bash
# ===================================
# v0.0.2 BUILD 2026-11-21@11:45
# v0.0.1 BUILD 2026-11-21@11:44
# Builds the helper, signs it with the Developer ID certificate, packs it into a DMG, has Apple notarize it, and staples the ticket.
# dev by @dastefster 🍒🔨
# ===================================

set -euo pipefail

IDENTITY="Developer ID Application: Stefan Alexander Hottel (B6A27JW462)"
TEAM="B6A27JW462"
PROFILE="cherri-notary"

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/../build/helper-release"
BUILD="$OUT/derived"
STAGE="$OUT/dmg-stage"

# ===================================
# BUILD
# ===================================

rm -rf "$OUT"
mkdir -p "$OUT"

xcodebuild -project "$HERE/CherriHelper.xcodeproj" -scheme CherriHelper -configuration Release \
  -derivedDataPath "$BUILD" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  build | grep -E "error:|BUILD (SUCCEEDED|FAILED)"

APP="$BUILD/Build/Products/Release/CherriHelper.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$OUT/Cherri-Helper-$VERSION.dmg"

echo "== verifying app signature"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E "Authority|TeamIdentifier|flags|Timestamp"

# ===================================
# DMG
# ===================================

mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/Cherri Helper.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Cherri Helper" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
codesign --sign "$IDENTITY" --timestamp "$DMG"

# ===================================
# NOTARIZE
# ===================================

echo "== submitting to Apple (a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

echo "== final check"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG" || true
xcrun stapler validate "$DMG"
echo "DONE: $DMG"

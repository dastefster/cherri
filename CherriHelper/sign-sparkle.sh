#!/bin/bash
# ===================================
# Sparkle re-signing
# v0.0.1 BUILD 2026-11-21@12:25
# Re-signs Sparkle's helper tools inside the built app with the Developer ID certificate, inside out, so Apple will notarize it.
# dev by @dastefster 🍒🔨
# ===================================

# Usage: sign-sparkle.sh "<path to .app>" "<signing identity>"
set -euo pipefail

APP="$1"
ID="$2"
FW="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"

sign() { codesign --force --sign "$ID" --options runtime --timestamp "$@"; }

# Inside out: the small pieces first, then the framework, then the app that holds them.
sign "$FW/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$FW/XPCServices/Downloader.xpc"
sign "$FW/Autoupdate"
sign "$FW/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"
sign "$APP"

codesign --verify --deep --strict "$APP"
echo "Sparkle pieces signed and verified"

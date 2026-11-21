#!/bin/bash
# ===================================
# Fake First Run
# v0.0.1 BUILD 2026-11-21@15:55
# Makes the installed Cherri Helper behave like a brand-new install so the welcome screen shows again. Dev tool, not shipped.
# dev by @dastefster 🍒🔨
# ===================================
#
#   ./fake-first-run.sh            quit the helper, set the pairing key aside, clear the setup flags, relaunch
#   ./fake-first-run.sh --restore  quit the helper, put the saved pairing key back, relaunch (your iPhone stays paired)

set -euo pipefail

APP="/Applications/Cherri Helper.app"
ID="com.dastefster.CherriHelper"
KEY="$HOME/Library/Application Support/CherriHelper/pairing.key"
SAVED="$HOME/Library/Application Support/CherriHelper/pairing.key.saved"

pkill -x CherriHelper 2>/dev/null || true
sleep 1

if [ "${1:-}" = "--restore" ]; then
  if [ -f "$SAVED" ]; then
    mv -f "$SAVED" "$KEY"
    echo "Restored the saved pairing key."
  else
    echo "No saved key found. Nothing to restore."
  fi
else
  # Never overwrite an older saved key: that one is the pairing worth keeping.
  if [ -f "$KEY" ] && [ ! -f "$SAVED" ]; then
    mv "$KEY" "$SAVED"
    echo "Saved your pairing key. Run with --restore to bring it back."
  fi
  defaults delete "$ID" hasCompletedWelcome 2>/dev/null || true
  defaults delete "$ID" hasEverPaired 2>/dev/null || true
  echo "Cleared the setup flags."
fi

open "$APP"

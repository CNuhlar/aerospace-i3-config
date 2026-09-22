#!/bin/bash
# i3's dmenu slot: open Spotlight, and leave a note for focus-guard.sh saying a
# launch is in flight. That note is what lets the guard tell "I asked for this
# app just now" from "focus happened to move" - so launching an app you already
# have open gives you a NEW window instead of just raising the old one.
set -u
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

AERO=$(command -v aerospace || echo /opt/homebrew/bin/aerospace)
STATE="$HOME/.cache/aerospace-i3"
mkdir -p "$STATE"

# Who is in front and how many windows exist right now, so the guard can see
# what changed once Spotlight hands over.
"$AERO" list-windows --focused --format '%{app-name}' 2>/dev/null | head -1 > "$STATE/launch-app"
"$AERO" list-windows --all --count 2>/dev/null > "$STATE/launch-count"
date +%s > "$STATE/launch-at"

# The delay matters: if alt is still held when cmd+space is sent, macOS reads it
# as cmd+alt+space, which is "Spotlight window" and opens a Finder search.
osascript -e 'delay 0.3' -e 'tell application "System Events" to key code 49 using {command down}' >/dev/null 2>&1

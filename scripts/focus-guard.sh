#!/usr/bin/env bash
# Stop app activation from yanking you to another workspace.
#
# AeroSpace follows an app when you activate it: if Safari's only window lives
# on workspace 3 and you activate Safari from workspace 1, you are moved to
# workspace 3. This script keeps you where you are and gives the app a new
# window on the current workspace instead.
#
# Wired up as on-focus-changed in aerospace.toml. Disable at any time with:
#   touch ~/.cache/aerospace-i3/disabled
set -u

AERO=$(command -v aerospace || echo /opt/homebrew/bin/aerospace)
STATE="$HOME/.cache/aerospace-i3"
mkdir -p "$STATE"

[ -e "$STATE/disabled" ] && exit 0

cur=$("$AERO" list-workspaces --focused 2>/dev/null) || exit 0
[ -n "$cur" ] || exit 0
exp=$(cat "$STATE/expected" 2>/dev/null || true)

# No expectation yet, a deliberate move still in flight ('*'), or we are exactly
# where we asked to be: nothing to do, just remember where we are.
if [ -z "$exp" ] || [ "$exp" = '*' ] || [ "$exp" = "$cur" ]; then
  printf '%s' "$cur" > "$STATE/expected"
  exit 0
fi

# --- we were moved to another workspace without asking ---

# One instance at a time; the work below triggers focus changes of its own.
lock="$STATE/lock.d"
if [ -d "$lock" ]; then
  # drop a stale lock from a crashed run
  find "$STATE" -maxdepth 1 -name lock.d -type d -mmin +1 -exec rmdir {} \; 2>/dev/null
fi
mkdir "$lock" 2>/dev/null || exit 0
trap 'rmdir "$lock" 2>/dev/null' EXIT

wid=$("$AERO" list-windows --focused --format '%{window-id}' 2>/dev/null | head -1)
[ -n "$wid" ] || exit 0

before=$("$AERO" list-windows --all --format '%{window-id}' 2>/dev/null | sort -n)

# The app we were dragged to is frontmost right now, so cmd+N reaches it.
osascript -e 'tell application "System Events" to keystroke "n" using command down' 2>/dev/null
sleep 0.8

after=$("$AERO" list-windows --all --format '%{window-id}' 2>/dev/null | sort -n)
new=$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | head -1)

if [ -n "$new" ]; then
  # Got a new window: bring that one back with us.
  "$AERO" move-node-to-workspace --window-id "$new" "$exp" 2>/dev/null
else
  # App has no cmd+N (or it did something else). Fall back to summoning the
  # existing window instead of leaving the user stranded.
  "$AERO" move-node-to-workspace --window-id "$wid" "$exp" 2>/dev/null
fi

printf '%s' "$exp" > "$STATE/expected"
"$AERO" workspace "$exp" 2>/dev/null

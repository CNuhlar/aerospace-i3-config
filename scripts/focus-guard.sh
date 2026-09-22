#!/bin/bash
# Stop app activation from yanking you to another workspace.
#
# AeroSpace follows an app when you activate it: if Safari's only window lives
# on workspace 3 and you activate Safari from workspace 2, you are moved to
# workspace 3. This script puts you straight back and gives the app a new
# window where you already were.
#
# Order matters. Going back is the FIRST thing it does, so the detour is a
# flicker rather than a visible trip to another workspace. Only then does it
# ask the app for a new window, which is why it clicks the app's own
# File > New Window menu item instead of sending cmd+N: by that point the app
# is no longer frontmost and a keystroke would land in the wrong window.
#
# Wired up as on-focus-changed in aerospace.toml. Disable at any time with:
#   touch ~/.cache/aerospace-i3/disabled
set -u
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

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

# One instance at a time; everything below causes focus changes of its own.
[ -d "$STATE/lock.d" ] && find "$STATE" -maxdepth 1 -name lock.d -type d -mmin +1 -exec rmdir {} \; 2>/dev/null
mkdir "$STATE/lock.d" 2>/dev/null || exit 0
trap 'rmdir "$STATE/lock.d" 2>/dev/null' EXIT

# Who dragged us here, and what did the window list look like before we acted?
read -r wid app <<<"$("$AERO" list-windows --focused --format '%{window-id} %{app-name}' 2>/dev/null | head -1)"
[ -n "${wid:-}" ] || exit 0
before=$("$AERO" list-windows --all --format '%{window-id}' 2>/dev/null | sort -n)

# Back home first, before anything slow.
printf '%s' "$exp" > "$STATE/expected"
"$AERO" workspace "$exp" 2>/dev/null

# Ask the app for a new window through its own File menu. Targets the process
# directly, so it works while the app sits in the background.
osascript - "$app" <<'OSA' >/dev/null 2>&1
on run argv
  set procName to item 1 of argv
  tell application "System Events" to tell process procName
    repeat with mb in {"File", "Shell", "Dosya"}
      try
        set fm to menu 1 of menu bar item mb of menu bar 1
        repeat with mi in menu items of fm
          set n to name of mi as text
          if n contains "New" and n contains "Window" then
            click mi
            return "ok"
          end if
        end repeat
      end try
    end repeat
  end tell
  return "none"
end run
OSA

# Wait briefly for a window to show up.
new=""
for _ in 1 2 3 4 5 6; do
  sleep 0.2
  new=$("$AERO" list-windows --all --format '%{window-id}' 2>/dev/null | sort -n \
        | comm -13 <(printf '%s\n' "$before") - | head -1)
  [ -n "$new" ] && break
done

if [ -n "$new" ]; then
  # New windows land on the focused workspace, which is already home. Move it
  # only if the app placed it somewhere else.
  where=$("$AERO" list-windows --all --format '%{window-id} %{workspace}' 2>/dev/null | awk -v w="$new" '$1==w{print $2}')
  [ -n "$where" ] && [ "$where" != "$exp" ] && "$AERO" move-node-to-workspace --window-id "$new" "$exp" 2>/dev/null
else
  # No File > New Window (or the app ignored it). Summon the existing window
  # rather than leaving the app unreachable from here.
  "$AERO" move-node-to-workspace --window-id "$wid" "$exp" 2>/dev/null
fi

printf '%s' "$exp" > "$STATE/expected"

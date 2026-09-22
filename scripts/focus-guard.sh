#!/bin/bash
# Two jobs, both reacting to on-focus-changed:
#
#  1. Activating an app must not drag you to whatever workspace its window
#     happens to live on. Go back, and give the app a window where you are.
#  2. Launching an app from the launcher (mod+d) when it is already open must
#     give you a NEW window, not raise the existing one.
#
# Disable both at any time with:  touch ~/.cache/aerospace-i3/disabled
set -u
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

AERO=$(command -v aerospace || echo /opt/homebrew/bin/aerospace)
STATE="$HOME/.cache/aerospace-i3"
mkdir -p "$STATE"
LAUNCH_TTL=10   # seconds a mod+d launch stays "in flight"

[ -e "$STATE/disabled" ] && exit 0

cur=$("$AERO" list-workspaces --focused 2>/dev/null) || exit 0
[ -n "$cur" ] || exit 0
exp=$(cat "$STATE/expected" 2>/dev/null || true)

# Total window count across focus changes. A drop means a window was CLOSED,
# which hands focus to another window of the same app and is otherwise
# indistinguishable from an activation - answering that with a new window makes
# apps spring back to life every time you close one.
count=$("$AERO" list-windows --all --count 2>/dev/null || echo 0)
prev_count=$(cat "$STATE/count" 2>/dev/null || echo "$count")
printf '%s' "$count" > "$STATE/count"

# Ask an app for a new window through its own File menu. Targets the process
# directly, so it works while the app sits in the background - by the time this
# runs the app is usually not frontmost any more and a cmd+N keystroke would
# land in the wrong window.
new_window() {
  osascript - "$1" <<'OSA' >/dev/null 2>&1
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
}

take_lock() {
  [ -d "$STATE/lock.d" ] && find "$STATE" -maxdepth 1 -name lock.d -type d -mmin +1 -exec rmdir {} \; 2>/dev/null
  mkdir "$STATE/lock.d" 2>/dev/null || return 1
  trap 'rmdir "$STATE/lock.d" 2>/dev/null' EXIT
  return 0
}

launch_pending() {
  local at now
  at=$(cat "$STATE/launch-at" 2>/dev/null || echo 0)
  now=$(date +%s)
  [ "$at" -gt 0 ] && [ $((now - at)) -le "$LAUNCH_TTL" ]
}

clear_launch() { rm -f "$STATE/launch-at" "$STATE/launch-app" "$STATE/launch-count"; }

if [ -z "$exp" ] || [ "$exp" = '*' ] || [ "$exp" = "$cur" ]; then
  # --- no workspace jump ---
  printf '%s' "$cur" > "$STATE/expected"

  # Did mod+d just launch something that was already open? Spotlight raises the
  # existing window rather than making one, so the window count does not move.
  launch_pending || exit 0
  read -r wid app <<<"$("$AERO" list-windows --focused --format '%{window-id} %{app-name}' 2>/dev/null | head -1)"
  [ -n "${app:-}" ] || exit 0
  was=$(cat "$STATE/launch-app" 2>/dev/null || true)
  [ "$app" = "$was" ] && exit 0                      # same app as before: nothing was launched yet
  launch_count=$(cat "$STATE/launch-count" 2>/dev/null || echo "$count")
  clear_launch
  [ "$count" -gt "$launch_count" ] && exit 0         # it opened its own window already
  take_lock || exit 0
  new_window "$app"
  exit 0
fi

# --- we were moved to another workspace without asking ---
take_lock || exit 0

read -r wid app <<<"$("$AERO" list-windows --focused --format '%{window-id} %{app-name}' 2>/dev/null | head -1)"
[ -n "${wid:-}" ] || exit 0
before=$("$AERO" list-windows --all --format '%{window-id}' 2>/dev/null | sort -n)

# Back home first, before anything slow, so the detour is a flicker.
printf '%s' "$exp" > "$STATE/expected"
"$AERO" workspace "$exp" 2>/dev/null

if [ "$count" -lt "$prev_count" ]; then
  clear_launch
  exit 0                                             # a close, not an activation
fi

# Already have a window of this app here? Focus it instead of piling up more -
# unless mod+d asked for a new one on purpose.
if ! launch_pending; then
  here=$("$AERO" list-windows --workspace "$exp" --format '%{window-id} %{app-name}' 2>/dev/null \
         | awk -v a="$app" '$0 ~ a {print $1; exit}')
  if [ -n "$here" ]; then
    "$AERO" focus --window-id "$here" 2>/dev/null
    exit 0
  fi
fi
clear_launch

new_window "$app"

new=""
for _ in 1 2 3 4 5 6; do
  sleep 0.2
  new=$("$AERO" list-windows --all --format '%{window-id}' 2>/dev/null | sort -n \
        | comm -13 <(printf '%s\n' "$before") - | head -1)
  [ -n "$new" ] && break
done

if [ -n "$new" ]; then
  where=$("$AERO" list-windows --all --format '%{window-id} %{workspace}' 2>/dev/null | awk -v w="$new" '$1==w{print $2}')
  [ -n "$where" ] && [ "$where" != "$exp" ] && "$AERO" move-node-to-workspace --window-id "$new" "$exp" 2>/dev/null
else
  # No File > New Window, or the app ignored it: summon the existing window
  # rather than leaving the app unreachable from here.
  "$AERO" move-node-to-workspace --window-id "$wid" "$exp" 2>/dev/null
fi

printf '%s' "$exp" > "$STATE/expected"

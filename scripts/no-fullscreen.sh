#!/bin/bash
# macOS' own fullscreen puts a window in a Space of its own, and AeroSpace does
# not manage Spaces. The window vanishes from its workspace - mod+1..0 will not
# show it - and the only way back is a trackpad gesture. Worse, activating such
# an app looks to focus-guard.sh like being dragged to another workspace, so it
# drags you straight back out again.
#
# So: never stay in macOS fullscreen. The moment a window enters it, leave, and
# use AeroSpace's fullscreen instead - which fills the workspace and stays part
# of the tiling, the way i3 has always done it.
#
# There is no AeroSpace event for this (its 'subscribe' knows about focus and
# workspaces, nothing else) and the Accessibility API cannot see windows in
# other Spaces at all, so it has to be caught as it happens, on the focused
# window. That is one long-lived osascript polling twice a second - measurably
# free, unlike respawning osascript, which costs ~60ms of CPU each time.
#
# Stop it - along with the rest - with:  touch ~/.cache/aerospace-i3/disabled
set -u
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

AERO=$(command -v aerospace || echo /opt/homebrew/bin/aerospace)
. "$(dirname "$0")/lib.sh"

# Exactly one watcher, however many times this gets started - two focus events
# arriving together will both find the pid file empty and both start one, so the
# claim has to be atomic. mkdir is; a pid file on its own is not.
mine=no
if mkdir "$STATE/no-fullscreen.d" 2>/dev/null; then
  mine=yes
else
  alive() { p=$(cat "$STATE/no-fullscreen.pid" 2>/dev/null || true)
            [ -n "$p" ] && [ "$p" != "$$" ] && kill -0 "$p" 2>/dev/null; }
  alive && exit 0
  sleep 0.5          # the winner may not have written its pid yet
  alive && exit 0    # it had: leave it to them
fi                   # otherwise whoever held this is gone - take it over
printf '%s' "$$" > "$STATE/no-fullscreen.pid"

FIFO="$STATE/fullscreen.fifo"
rm -f "$FIFO"; mkfifo "$FIFO" || exit 1

watcher=""
cleanup() {
  [ -n "$watcher" ] && kill "$watcher" 2>/dev/null
  rm -f "$FIFO"
  [ "$(cat "$STATE/no-fullscreen.pid" 2>/dev/null)" = "$$" ] && rmdir "$STATE/no-fullscreen.d" 2>/dev/null
  free_lock
}
trap cleanup EXIT INT TERM

osascript > "$FIFO" 2>&1 <<'OSA' &
repeat
  try
    tell application "System Events"
      set p to first process whose frontmost is true
      if (value of attribute "AXFullScreen" of (value of attribute "AXFocusedWindow" of p)) is true then
        log "FS"
      end if
    end tell
  end try
  delay 0.5
end repeat
OSA
watcher=$!
log "no-fullscreen: watching (pid $$, osascript $watcher)"

last=0
while read -r line; do
  [ "$line" = FS ] || continue
  [ -e "$STATE/disabled" ] && continue

  # The watcher keeps saying so for as long as the window is fullscreen, and
  # leaving takes about a second. Act once per transition, not once per poll.
  now=$(date +%s)
  [ $((now - last)) -lt 3 ] && continue
  last=$now

  read -r wid app <<<"$("$AERO" list-windows --focused --format '%{window-id} %{app-name}' 2>/dev/null | head -1)"
  [ -n "${wid:-}" ] || continue

  wait_for_lock 2
  take_lock || continue
  log "no-fullscreen: $app ($wid) went macOS fullscreen, bringing it back"
  "$AERO" macos-native-fullscreen off --window-id "$wid" 2>/dev/null
  sleep 1.0                      # the Space closing is animated
  "$AERO" fullscreen on --window-id "$wid" 2>/dev/null
  free_lock
  last=$(date +%s)
done < "$FIFO"

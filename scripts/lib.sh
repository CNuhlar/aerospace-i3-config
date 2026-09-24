# Shared by launcher.sh and focus-guard.sh.
STATE="$HOME/.cache/aerospace-i3"
mkdir -p "$STATE"

log() { [ -e "$STATE/debug" ] || return 0; printf '%s %s\n' "$(date '+%H:%M:%S')" "$*" >> "$STATE/log"; }

# Ask an app for a new window through its own File menu. Targets the process
# directly, so it works while the app sits in the background - a cmd+N keystroke
# would land in whatever window happens to be in front instead.
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

# One writer at a time: the guard fires on every focus change and the launcher
# runs alongside it. Callers release it themselves - take_lock_or_quit in each
# of them arms the EXIT trap, which is right for a script that does its work
# and exits.
take_lock() {
  [ -d "$STATE/lock.d" ] && find "$STATE" -maxdepth 1 -name lock.d -type d -mmin +1 -exec rmdir {} \; 2>/dev/null
  mkdir "$STATE/lock.d" 2>/dev/null
}
free_lock() { rmdir "$STATE/lock.d" 2>/dev/null; }

wait_for_lock() {  # $1 = seconds to wait
  local n=$(( ${1:-3} * 10 ))
  while [ $n -gt 0 ] && [ -d "$STATE/lock.d" ]; do sleep 0.1; n=$((n - 1)); done
}

# A mod+d launch the guard should treat as "a new window was asked for on
# purpose". Armed by launcher.sh the moment Spotlight closes, and short-lived:
# it exists to cover the app-activation jump that follows within a second.
LAUNCH_TTL=5
launch_pending() {
  local at
  at=$(cat "$STATE/launch-at" 2>/dev/null || echo 0)
  [ "$at" -gt 0 ] && [ $(( $(date +%s) - at )) -le "$LAUNCH_TTL" ]
}
clear_launch() { rm -f "$STATE/launch-at"; }

# Apps that should be brought to you rather than handed a new empty window when
# they activate from another workspace. See focus-guard.sh for why. Names are
# AeroSpace's app names, one per line; override the list entirely by writing
# your own to ~/.cache/aerospace-i3/follow-apps.
FOLLOW_APPS='Safari
Google Chrome
Firefox
Arc
Brave Browser
Microsoft Edge
Preview'
follows_you() {
  [ -n "${1:-}" ] || return 1
  if [ -r "$STATE/follow-apps" ]; then
    grep -qxiF "$1" "$STATE/follow-apps"
  else
    printf '%s\n' "$FOLLOW_APPS" | grep -qxiF "$1"
  fi
}

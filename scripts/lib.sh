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
    -- Almost every app spells it exactly this way, and naming the item outright
    -- is one round trip where reading the menu item by item is several.
    try
      click menu item "New Window" of menu 1 of menu bar item "File" of menu bar 1
      return "ok"
    end try
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

# Bring a window to a workspace and put it where a newly opened window would go:
# next to the anchor (the window you were on), inside its container, so the last
# mod+h / mod+v decides the side. move-node-to-workspace alone ignores all that
# and appends to the workspace's root container.
#
# What does place it properly is AeroSpace turning a floating window into a
# tiling one - that goes through the same code as a new window, which binds next
# to the workspace's most recent window. Two traps on the way:
#  - the floating container becomes the workspace's most recent child as soon as
#    the window lands in it, and with that empty again at tiling time the lookup
#    finds no window and falls back to the root. Focusing the anchor fixes that.
#  - focusing a window that already has focus is a no-op and marks nothing, so
#    focus the arriving window first, then the anchor.
# A window that was floating to begin with stays floating.
place_window() {  # $1 = window id, $2 = workspace, $3 = anchor window id (may be empty)
  local was
  was=$("$AERO" list-windows --all --format '%{window-id} %{window-layout}' 2>/dev/null | awk -v w="$1" '$1==w{print $2}')
  if [ "$was" = floating ]; then
    "$AERO" move-node-to-workspace --window-id "$1" "$2" 2>/dev/null
    "$AERO" focus --window-id "$1" 2>/dev/null
    return
  fi
  "$AERO" layout --window-id "$1" floating 2>/dev/null
  "$AERO" move-node-to-workspace --window-id "$1" "$2" 2>/dev/null
  "$AERO" focus --window-id "$1" 2>/dev/null
  [ -n "${3:-}" ] && [ "$3" != "$1" ] && "$AERO" focus --window-id "$3" 2>/dev/null
  "$AERO" layout --window-id "$1" tiling 2>/dev/null
  apply_split "$1" "${3:-}"
  [ "$SPLIT_JOINED" = 1 ] || move_to_end "$1"
  "$AERO" focus --window-id "$1" 2>/dev/null
}

# The other half of split.sh: a window has just landed - opened, or brought
# here by place_window - and if it landed beside the window that mod+h / mod+v
# was pressed on, join the two in a container of the orientation asked for.
#
# New windows go right after the window that had focus, so that window is to
# the left of the arrival in a horizontal container, or above it in a vertical
# one - join-with in that direction picks it up, and makes a container of the
# opposite orientation, which is the one asked for whenever the two differ.
apply_split() {  # $1 = window that arrived, $2 = window it was placed next to (if known)
  local line pwid want top lay have dir ws pws
  SPLIT_JOINED=0
  line=$(cat "$STATE/split" 2>/dev/null) || return 0
  read -r pwid want top <<<"$line"
  [ -n "${pwid:-}" ] && [ "$1" != "$pwid" ] || return 0
  [ -n "${2:-}" ] && [ "$2" != "$pwid" ] && return 0
  read -r lay ws <<<"$("$AERO" list-windows --all --format '%{window-id} %{window-layout} %{workspace}' 2>/dev/null | awk -v w="$1" '$1==w{print $2, $3}')"
  pws=$("$AERO" list-windows --all --format '%{window-id} %{workspace}' 2>/dev/null | awk -v w="$pwid" '$1==w{print $2}')
  [ -n "$pws" ] && [ "$ws" = "$pws" ] || return 0
  case "$lay" in
    h_*) have=h; dir=left ;;
    v_*) have=v; dir=up ;;
    *) return 0 ;;   # floating, dialogs
  esac
  # Used up: from here on the container itself carries the orientation, and
  # the next window opened inside it follows it without being told.
  rm -f "$STATE/split"
  if [ "$have" = "$want" ]; then
    log "split: $1 is already $want beside $pwid"
    return 0
  fi
  "$AERO" join-with --window-id "$1" "$dir" 2>/dev/null && SPLIT_JOINED=1
  log "split: joined $1 with $pwid, $want"
}

# A mod+h / mod+v choice belongs to the window it was made on. Once focus moves
# to some other window that already existed, a window opened from there must not
# pick it up. Windows newer than the choice are the arrivals it is waiting for.
forget_split_unless() {  # $1 = window that now has focus
  local pwid want top
  read -r pwid want top < "$STATE/split" 2>/dev/null || return 0
  [ -n "${1:-}" ] || return 0
  if [ "$1" != "$pwid" ] && [ "$1" -le "${top:-0}" ]; then
    rm -f "$STATE/split"
    log "split: focus went to $1, dropping the choice made on $pwid"
  fi
}

# Put a window that just landed at the end of its row (or column) instead of
# right after the window that had focus, which is where AeroSpace puts it.
#
# AeroSpace cannot show its tree, so the row is read off the screen: in a
# horizontal container every child spans the window's full height, so the
# windows after it are the ones to its right that sit within its vertical band
# (and the same turned sideways for a vertical one). If those are all plain
# windows, stepping past them with one swap each is enough. If one is shorter
# than the band, it is part of a nested split: then the float-then-tile trick of
# place_window puts the window right after the last of them, inside that split,
# and one move in the row's direction takes it out to just after the split.
FRAMES="$(dirname "${BASH_SOURCE[0]}")/win-frames"
move_to_end() {  # $1 = window id
  local lay ws ids all f prev dir x y w h anchor full count
  [ -x "$FRAMES" ] || return 0
  read -r lay ws <<<"$("$AERO" list-windows --all --format '%{window-id} %{window-layout} %{workspace}' 2>/dev/null | awk -v w="$1" '$1==w{print $2, $3}')"
  case "$lay" in h_tiles) dir=right ;; v_tiles) dir=down ;; *) return 0 ;; esac
  [ "$ws" = "$("$AERO" list-workspaces --focused 2>/dev/null)" ] || return 0
  # Wait for the layout to reach the window: two equal readings in a row.
  prev=""
  for _ in $(seq 12); do
    all=$("$FRAMES" 2>/dev/null)
    f=$(printf '%s\n' "$all" | awk -v w="$1" '$1==w{print $2, $3, $4, $5; exit}')
    [ -n "$f" ] && [ "$f" = "$prev" ] && break
    prev=$f; sleep 0.03
  done
  [ -n "$f" ] || return 0
  read -r x y w h <<<"$f"
  ids=$("$AERO" list-windows --workspace "$ws" --format '%{window-id} %{window-layout}' 2>/dev/null | awk -v n="$1" '$2 != "floating" && $1 != n {print $1}')
  # The windows after this one in its row: the last of them, whether it spans
  # the full row (a direct sibling) or not (inside a nested split), and how
  # many there are if every one of them is a direct sibling.
  read -r anchor full count <<<"$(printf '%s\n' "$all" | awk -v ids=" $(echo $ids) " -v o="$dir" -v x="$x" -v y="$y" -v w="$w" -v h="$h" '
    index(ids, " " $1 " ") {
      if (o == "right") { inband = ($3 >= y-4 && $3+$5 <= y+h+4); after = ($2 >= x+w-4); key = $2*100000 + $3; span = ($5 >= h-8) }
      else              { inband = ($2 >= x-4 && $2+$4 <= x+w+4); after = ($3 >= y+h-4); key = $3*100000 + $2; span = ($4 >= w-8) }
      if (inband && after) {
        n++; if (!span) nested = 1
        if (best == "" || key > bestkey) { best = $1; bestkey = key; bestspan = span }
      }
    }
    END { if (best != "") print best, bestspan, (nested ? 0 : n) }')"
  [ -n "$anchor" ] || return 0   # already last
  if [ "${count:-0}" -gt 0 ]; then
    # Only plain windows after it: step past them one swap at a time, which
    # just reorders the row with no detour through floating.
    log "end: $1 steps $dir past $count"
    for _ in $(seq "$count"); do "$AERO" move --window-id "$1" --boundaries-action fail "$dir" 2>/dev/null || break; done
    return 0
  fi
  log "end: $1 goes after $anchor (${dir}, $([ "$full" = 1 ] && echo direct || echo nested))"
  "$AERO" layout --window-id "$1" floating 2>/dev/null
  "$AERO" focus --window-id "$1" 2>/dev/null
  "$AERO" focus --window-id "$anchor" 2>/dev/null
  "$AERO" layout --window-id "$1" tiling 2>/dev/null
  [ "$full" = 1 ] || "$AERO" move --window-id "$1" --boundaries-action fail "$dir" 2>/dev/null
  "$AERO" focus --window-id "$1" 2>/dev/null
}

# AeroSpace and macOS can disagree about which window has focus. Close an app's
# window with its own cmd+w and the app stays in front with nothing of it on
# this workspace, while AeroSpace still holds the window it had before - the one
# you see highlighted. Keys go to the invisible app, and mod+arrow only moves on
# from AeroSpace's window, so with nothing in that direction it does nothing.
# AeroSpace takes focusing the window it already has as a no-op, so bring its
# app to the front ourselves; the app's key window is that same window, the one
# it had before the other app took over. With no window focused at all, take
# the first one here. Returns 1 if all was well.
sync_focus() {
  local wid pid front
  read -r wid pid <<<"$("$AERO" list-windows --focused --format '%{window-id} %{app-pid}' 2>/dev/null | head -1)"
  if [ -z "${wid:-}" ]; then
    [ "$("$AERO" list-windows --workspace focused --count 2>/dev/null || echo 0)" -gt 0 ] || return 1
    log "sync: nothing focused, taking the first window here"
    "$AERO" focus --dfs-index 0 2>/dev/null
    return 0
  fi
  front=$(lsappinfo info -only pid "$(lsappinfo front)" 2>/dev/null)
  front=${front#*=}
  [ -z "$front" ] || [ "$front" = "$pid" ] && return 1
  log "sync: pid $front is in front, AeroSpace has $wid (pid $pid) - focusing it"
  osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $pid) to true" >/dev/null 2>&1
  "$AERO" focus --window-id "$wid" 2>/dev/null
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

# The jump a mod+d launch causes can reach the guard before launcher.sh has
# noticed Spotlight close and armed launch-at, and read as a plain activation it
# brought the app's old window over - with the new one following right behind.
# While the launcher is still alive, give it a moment to make up its mind: it
# either arms launch-at or exits.
wait_for_launcher() {  # $1 = tenths of a second to wait at most
  local pid n=${1:-10}
  pid=$(cat "$STATE/launcher.pid" 2>/dev/null) || return 0
  [ -n "$pid" ] || return 0
  while [ $n -gt 0 ] && ! launch_pending && kill -0 "$pid" 2>/dev/null; do
    sleep 0.1; n=$((n - 1))
  done
}

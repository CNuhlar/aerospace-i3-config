#!/bin/bash
# i3's dmenu slot: open Spotlight, and make sure that picking an app you already
# have open gives you a NEW window rather than just raising the old one.
#
# Spotlight will not tell us what it did, so we watch it: we know what was in
# front before, and we know the moment the panel closes. Everything is decided
# in the second after that - there is no long-lived "a launch might be happening"
# flag for an unrelated focus change to walk into.
set -u
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

AERO=$(command -v aerospace || echo /opt/homebrew/bin/aerospace)
. "$(dirname "$0")/lib.sh"

# These two do their work and exit, so the lock can simply live until they do.
take_lock_or_quit() { take_lock || return 1; trap free_lock EXIT; }

sp() { osascript -e "tell application \"System Events\" to tell process \"Spotlight\" to $1" 2>/dev/null; }

# One round trip per poll: "GONE" once the panel has closed, otherwise the query
# text, whether it has been typed into, and the name of the highlighted result -
# the app Return would open.
#
# Reading the highlight is the whole trick: it says what the launch was aimed at,
# so a focus change that lands somewhere else is not mistaken for the launch.
#
# "Typed into" matters because Spotlight reopens holding your last search, fully
# selected. Left alone it stays selected; the first keystroke replaces it. So a
# selection covering the whole field means nobody has touched this prompt, and
# whatever is in it is a leftover rather than a request.
sp_probe() {
  osascript 2>/dev/null <<'OSA'
tell application "System Events" to tell process "Spotlight"
  if not (exists window 1) then return "GONE"
  set q to ""
  set target to ""
  set touched to "0"
  try
    set tf to text field 1 of group 1 of window 1
    set q to value of tf
    if q is not "" and ((value of attribute "AXSelectedText" of tf) as text) is not q then set touched to "1"
  end try
  try
    repeat with l in lists of list 1 of scroll area 1 of group 1 of window 1
      repeat with e in UI elements of l
        if (value of attribute "AXSelected" of e) is true then
          set target to name of static text 1 of e
          exit repeat
        end if
      end repeat
      if target is not "" then exit repeat
    end repeat
  end try
  return "Q" & touched & q & tab & target
end tell
OSA
}
focused_app() { "$AERO" list-windows --focused --format '%{app-name}' 2>/dev/null | head -1; }
win_count() { "$AERO" list-windows --all --count 2>/dev/null || echo 0; }

# Only one watcher at a time. Hitting mod+d again - or leaving the panel open
# and wandering off - must not leave copies of this script polling Spotlight
# behind each other; several at once make it drop clicks and keystrokes.
old=$(cat "$STATE/launcher.pid" 2>/dev/null || true)
[ -n "$old" ] && [ "$old" != "$$" ] && kill "$old" 2>/dev/null
printf '%s' "$$" > "$STATE/launcher.pid"

was=$(focused_app)
before=$(win_count)

# The delay matters: if alt is still held when cmd+space is sent, macOS reads it
# as cmd+alt+space, which is "Spotlight window" and opens a Finder search.
osascript -e 'delay 0.3' -e 'tell application "System Events" to key code 49 using {command down}' >/dev/null 2>&1

for _ in $(seq 20); do
  [ "$(sp '(exists window 1)')" = "true" ] && break
  sleep 0.1
done
[ "$(sp '(exists window 1)')" = "true" ] || { log "launcher: Spotlight never opened"; exit 0; }
log "launcher: open, was=[$was] count=$before"

# Sit on the panel until it goes away.
#
# Poll gently: Spotlight is a live UI, and several of these scripts walking its
# Accessibility tree at once makes it drop clicks and keystrokes. The full probe
# runs every third tick, the cheap "is it still up" check covers the rest. The
# query is a few hundred ms stale at worst, and it has stopped changing by the
# time anyone hits Return.
#
# The reading taken as the panel tears down always claims the field was touched -
# the selection collapses on the way out - so the one before it is what counts.
# A query that differs from the one we first saw is a launch either way, which
# covers typing something short and hitting Return before the next look.
query=""; first=""; target=""; typed=0; prev_typed=0; tick=0
for _ in $(seq 400); do
  tick=$((tick + 1))
  if [ $((tick % 3)) -ne 0 ]; then
    [ "$(sp '(exists window 1)')" = "true" ] || break
    sleep 0.15
    continue
  fi
  v=$(sp_probe)
  [ "$v" = "GONE" ] && break
  v="${v#Q}"
  prev_typed=$typed
  typed="${v%"${v#?}"}"
  v="${v#?}"
  q="${v%%	*}"; t="${v#*	}"
  [ -z "$first" ] && first="$q"
  [ -n "$q" ] && query="$q"
  [ -n "$t" ] && target="$t"
  sleep 0.15
done
[ "$query" = "$first" ] || prev_typed=1
log "launcher: closed, query=[$query] first=[$first] target=[$target] typed=$prev_typed"
[ "$prev_typed" = 1 ] && [ -n "$target" ] || exit 0

# Tell the guard this jump was asked for, so it does not answer with "you
# already have a window of that app here" - here a new one is the whole point.
date +%s > "$STATE/launch-at"

# Give the activation - and the guard, if the app lives on another workspace -
# room to finish before judging what happened.
sleep 0.6
wait_for_lock 3

now=$(focused_app)
count=$(win_count)
log "launcher: settled now=[$now] count=$count"
clear_launch

# The app made its own window, or the guard already made one on the way back
# from another workspace.
[ "$count" -gt "$before" ] && { log "launcher: window count grew, nothing to do"; exit 0; }
[ -n "$now" ] || exit 0

# Only the app the launch was aimed at gets a window. If focus has gone anywhere
# else - you carried on and switched workspace while this was settling, or
# Spotlight was dismissed without launching - there is nothing to do here.
same_app() {  # Spotlight's display name and AeroSpace's can differ: "iTerm" / "iTerm2"
  local a b; a=$(printf '%s' "$1" | tr 'A-Z' 'a-z'); b=$(printf '%s' "$2" | tr 'A-Z' 'a-z')
  [ -n "$a" ] && [ -n "$b" ] && { case "$a" in "$b"*) return 0;; esac; case "$b" in "$a"*) return 0;; esac; }
  return 1
}
same_app "$now" "$target" || { log "launcher: focus is on $now, not the $target we launched - leaving it alone"; exit 0; }

take_lock_or_quit || exit 0
ids=$("$AERO" list-windows --all --format '%{window-id}' 2>/dev/null | sort -n)
log "launcher: asking $now for a new window"
new_window "$now"

# Land on what was just opened, not on whatever we were typing into.
for _ in $(seq 10); do
  sleep 0.2
  new=$("$AERO" list-windows --all --format '%{window-id}' 2>/dev/null | sort -n \
        | comm -13 <(printf '%s\n' "$ids") - | head -1)
  [ -n "$new" ] && { "$AERO" focus --window-id "$new" 2>/dev/null; log "launcher: focused new window $new"; break; }
done

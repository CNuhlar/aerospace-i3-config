#!/bin/bash
# Activating an app must not drag you to whatever workspace its window happens to
# live on. Go back to where you were, and bring the window here instead.
#
# The mod+d "give me a new window" half lives in launcher.sh; all this script
# takes from it is launch_pending, which says the jump about to happen was asked
# for on purpose.
#
# Disable at any time with:  touch ~/.cache/aerospace-i3/disabled
set -u
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

AERO=$(command -v aerospace || echo /opt/homebrew/bin/aerospace)
. "$(dirname "$0")/lib.sh"

# These two do their work and exit, so the lock can simply live until they do.
take_lock_or_quit() { take_lock || return 1; trap free_lock EXIT; }

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

log "guard: focus change, cur=$cur exp=$exp count=$count prev=$prev_count focused=[$("$AERO" list-windows --focused --format '%{window-id} %{app-name}' 2>/dev/null | head -1)]"

# A workspace key was pressed a moment ago. This is that switch, or one from a
# quick run of them, and "expected" may already name a later target than the
# one this callback was fired for. Acting on it moved windows between the
# workspaces you were flipping through - and so did writing our reading of the
# current workspace back over the newer target. Touch nothing.
sw=$(stat -f %m "$STATE/switch-at" 2>/dev/null || echo 0)
recent_switch=0
[ $(( $(date +%s) - sw )) -le 1 ] && recent_switch=1

if [ -z "$exp" ] || [ "$exp" = '*' ] || [ "$exp" = "$cur" ]; then
  # Focus moved within where you are. A window arriving from elsewhere is
  # handled below and must not cancel a pending mod+h / mod+v.
  forget_split_unless "$("$AERO" list-windows --focused --format '%{window-id}' 2>/dev/null | head -1)"
  # Only fill in a target nobody set. ws-goto.sh owns it otherwise.
  [ "$recent_switch" = 0 ] && [ "$exp" != "$cur" ] && printf '%s' "$cur" > "$STATE/expected"
  exit 0
fi

if [ "$recent_switch" = 1 ]; then
  log "guard: on $cur while switching to $exp, not a jump"
  exit 0
fi

# --- we were moved to another workspace without asking ---
log "guard: JUMP $exp -> $cur, count=$count prev=$prev_count"
take_lock_or_quit || { log "guard: lock busy"; exit 0; }

# Going back is itself a focus change, and the app being activated keeps moving
# focus around while it settles. Those follow-on events look like fresh jumps,
# and answering them has dragged unrelated windows off their workspace. Within a
# moment of the last correction, just go home and stop.
at=$(cat "$STATE/corrected-at" 2>/dev/null || echo 0)
date +%s > "$STATE/corrected-at"

read -r wid app <<<"$("$AERO" list-windows --focused --format '%{window-id} %{app-name}' 2>/dev/null | head -1)"
[ -n "${wid:-}" ] || exit 0
before=$("$AERO" list-windows --all --format '%{window-id}' 2>/dev/null | sort -n)

# Back home first, before anything slow, so the detour is a flicker.
printf '%s' "$exp" > "$STATE/expected"
"$AERO" workspace "$exp" 2>/dev/null
# Going home focuses the window you were on. Whatever arrives goes next to it.
anchor=$("$AERO" list-windows --focused --format '%{window-id}' 2>/dev/null | head -1)

if [ $(( $(date +%s) - at )) -le 1 ]; then
  log "guard: still settling from the last correction, back only"
  exit 0
fi

if [ "$count" -lt "$prev_count" ]; then
  log "guard: count dropped, this was a close"
  exit 0
fi

# Whatever came forward is what you asked for - a window picked in Mission
# Control, the browser window a clicked link landed in, the app you cmd+tabbed
# to. Bring that one here, placed as a new window would be, so mod+h / mod+v
# decide the side. Asking the app for a fresh window instead left you with an
# empty one, and apps without File > New Window made you wait for nothing.
if ! launch_pending; then
  log "guard: bringing $app window $wid to $exp next to ${anchor:-nothing}"
  place_window "$wid" "$exp" "$anchor"
  exit 0
fi

# mod+d: a new window is the whole point.
log "guard: asking $app for a new window"
new_window "$app"

# Look before sleeping: the window is usually already there on the first look,
# and a sleep in front of it is dead time you watch go by.
new=""
for _ in $(seq 24); do
  new=$("$AERO" list-windows --all --format '%{window-id}' 2>/dev/null | sort -n \
        | comm -13 <(printf '%s\n' "$before") - | head -1)
  [ -n "$new" ] && break
  sleep 0.05
done

if [ -n "$new" ]; then
  where=$("$AERO" list-windows --all --format '%{window-id} %{workspace}' 2>/dev/null | awk -v w="$new" '$1==w{print $2}')
  if [ -n "$where" ] && [ "$where" != "$exp" ]; then
    place_window "$new" "$exp" "$anchor"
  else
    "$AERO" focus --window-id "$new" 2>/dev/null
  fi
  log "guard: new window $new is on $exp"
else
  # No File > New Window, or the app ignored it: summon the existing window
  # rather than leaving the app unreachable from here.
  log "guard: no new window appeared, bringing $wid over instead"
  place_window "$wid" "$exp" "$anchor"
fi

printf '%s' "$exp" > "$STATE/expected"

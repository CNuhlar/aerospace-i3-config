#!/bin/bash
# Activating an app must not drag you to whatever workspace its window happens to
# live on. Go back to where you were, and give the app a window here instead.
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

if [ -z "$exp" ] || [ "$exp" = '*' ] || [ "$exp" = "$cur" ]; then
  printf '%s' "$cur" > "$STATE/expected"
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

if [ $(( $(date +%s) - at )) -le 1 ]; then
  log "guard: still settling from the last correction, back only"
  exit 0
fi

if [ "$count" -lt "$prev_count" ]; then
  log "guard: count dropped, this was a close"
  exit 0
fi

# Some apps activate because something handed them a page to show - a link
# clicked in another app, a file opened. The window that just came forward is
# the one holding it, so bring that one here. A fresh window would be empty and
# would strand the thing you actually asked for on the app's own workspace.
# mod+d is exempt: there a new window is the whole point. List in lib.sh.
if ! launch_pending && follows_you "$app"; then
  log "guard: $app follows you, dragging window $wid to $exp"
  "$AERO" move-node-to-workspace --window-id "$wid" "$exp" 2>/dev/null
  "$AERO" focus --window-id "$wid" 2>/dev/null
  exit 0
fi

# Already have a window of this app here? Focus it instead of piling up more -
# unless mod+d asked for a new one on purpose.
if ! launch_pending; then
  here=$("$AERO" list-windows --workspace "$exp" --format '%{window-id} %{app-name}' 2>/dev/null \
         | awk -v a="$app" '{id=$1; sub(/^[^ ]* /,""); if ($0 == a) {print id; exit}}')
  if [ -n "$here" ]; then
    log "guard: $app already has window $here on $exp, focusing it"
    "$AERO" focus --window-id "$here" 2>/dev/null
    exit 0
  fi
fi

log "guard: asking $app for a new window"
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
  "$AERO" focus --window-id "$new" 2>/dev/null
  log "guard: new window $new is on $exp"
else
  # No File > New Window, or the app ignored it: summon the existing window
  # rather than leaving the app unreachable from here.
  log "guard: no new window appeared, dragging $wid over instead"
  "$AERO" move-node-to-workspace --window-id "$wid" "$exp" 2>/dev/null
fi

printf '%s' "$exp" > "$STATE/expected"

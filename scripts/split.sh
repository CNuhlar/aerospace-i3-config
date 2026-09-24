#!/bin/bash
# i3's "split h" / "split v": say which side the next window opens on.
#
# AeroSpace's own 'split' only works with the flatten normalization off, and with
# it off every window that leaves a container strands the rest in single-child
# containers nobody can see. mod+s / mod+w / mod+e then change the layout of one
# of those and nothing on screen moves. So the normalization stays on and this
# does the split the way AeroSpace recommends, with join-with: mod+h / mod+v only
# write down what you asked for, and when the next window lands beside that one,
# apply_split (lib.sh) joins the two into a container of that orientation.
#
#   split.sh h|v        remember the choice for the focused window
#   split.sh --apply    on-window-detected: a window just appeared
set -u
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

AERO=$(command -v aerospace || echo /opt/homebrew/bin/aerospace)
. "$(dirname "$0")/lib.sh"

case "${1:-}" in
  h|v)
    wid=$("$AERO" list-windows --focused --format '%{window-id}' 2>/dev/null | head -1)
    [ -n "$wid" ] || exit 0
    # The newest window id so far: anything above it arrived after the choice.
    top=$("$AERO" list-windows --all --format '%{window-id}' 2>/dev/null | sort -n | tail -1)
    printf '%s %s %s\n' "$wid" "$1" "${top:-0}" > "$STATE/split"
    log "split: next to $wid goes $1"
    ;;
  --apply)
    [ -n "${AEROSPACE_WINDOW_ID:-}" ] || exit 0
    apply_split "$AEROSPACE_WINDOW_ID"
    # Not split off on its own: it joins the row, at the end of it.
    [ "$SPLIT_JOINED" = 1 ] || move_to_end "$AEROSPACE_WINDOW_ID"
    ;;
esac

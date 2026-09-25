#!/bin/bash
# i3's "move container to workspace N", one window at a time, keeping windows
# that travel together in the shape they had.
#
# move-node-to-workspace alone appends to the end of the target's root: every
# window came in from the right, and two windows stacked one above the other
# came out side by side (or the other way round, depending on the monitor).
# Here the first move of a run notes where every window on the source workspace
# was, and each window is placed from that:
#  - if mod+h / mod+v was pressed on a window over there, it goes next to that
#    window, the way a window opened there would;
#  - otherwise one that sat right next to the window moved before it goes back
#    on the same side of it, joined into a container of the same orientation if
#    the one it lands in runs the other way;
#  - otherwise one that was first in its row (leftmost, or topmost when the
#    target's root is a column) goes to the front, the rest to the end.
#
# Windows are read off the screen (win-frames), so the snapshot is taken while
# the source workspace is the one showing - which it always is when you press
# the key.
set -u
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

AERO=$(command -v aerospace || echo /opt/homebrew/bin/aerospace)
. "$(dirname "$0")/lib.sh"
FRAMES="$(dirname "$0")/win-frames"

tgt=$1
src=$("$AERO" list-workspaces --focused 2>/dev/null)
wid=$("$AERO" list-windows --focused --format '%{window-id}' 2>/dev/null | head -1)
[ -n "$wid" ] || exit 0
[ "$tgt" = "$src" ] && exit 0

# Line 1: "last-moved-window source target", then "id x y w h" per window on
# the source workspace as it looked before the run began. A run is moves from
# one workspace to another with nothing else moved in between; it ends when
# either side changes, the window moved last is no longer on the target, or it
# has been a while - by then the snapshot no longer shows how things are.
MOVED="$STATE/moved"
prev=""
age=$(( $(date +%s) - $(stat -f %m "$MOVED" 2>/dev/null || echo 0) ))
on_tgt=" $("$AERO" list-windows --workspace "$tgt" --format '%{window-id}' 2>/dev/null | tr '\n' ' ')"
if [ "$age" -le 20 ] && read -r pm ps pt 2>/dev/null < "$MOVED" && [ "$ps" = "$src" ] && [ "$pt" = "$tgt" ] \
   && case "$on_tgt" in *" $pm "*) true ;; *) false ;; esac; then
  prev=$pm
else
  here=" $("$AERO" list-windows --workspace "$src" --format '%{window-id}' 2>/dev/null | tr '\n' ' ')"
  { printf '%s %s %s\n' "$wid" "$src" "$tgt"
    [ -x "$FRAMES" ] && "$FRAMES" 2>/dev/null | awk -v ids="$here" 'index(ids, " " $1 " ")'
  } > "$MOVED"
fi

# Where this window sat against the one moved before it, from the snapshot:
# "h" or "v", and whether it came after (right of / below) or before it. And
# how far it was from the left and top edges the source windows started at.
want=""; after=1
read -r want after dx dy <<<"$(awk -v a="${prev:-none}" -v b="$wid" '
  NR == 1 { next }
  { if (minx == "" || $2 < minx) minx = $2; if (miny == "" || $3 < miny) miny = $3 }
  $1 == a { ax=$2; ay=$3; aw=$4; ah=$5; fa=1 }
  $1 == b { bx=$2; by=$3; bw=$4; bh=$5; fb=1 }
  function near(p, q) { return (p - q < 40 && q - p < 40) }
  function overlap(p1, l1, p2, l2) { return (p1 < p2 + l2 - 20 && p2 < p1 + l1 - 20) }
  END {
    if (!fb) { print "- 1 -1 -1"; exit }
    r = "- 1"
    if (fa && overlap(ay, ah, by, bh) && near(ax + aw, bx)) r = "h 1"
    else if (fa && overlap(ay, ah, by, bh) && near(bx + bw, ax)) r = "h 0"
    else if (fa && overlap(ax, aw, bx, bw) && near(ay + ah, by)) r = "v 1"
    else if (fa && overlap(ax, aw, bx, bw) && near(by + bh, ay)) r = "v 0"
    print r, bx - minx, by - miny
  }' "$MOVED")"
[ "$want" = "-" ] && want=""

# A mod+h / mod+v waiting on a window over there.
read -r spw _ 2>/dev/null < "$(split_file "$tgt")" || spw=""
case "$on_tgt" in *" ${spw:-none} "*) ;; *) spw="" ;; esac

"$AERO" move-node-to-workspace --window-id "$wid" "$tgt" 2>/dev/null || exit 0
sed -i '' "1s/.*/$wid $src $tgt/" "$MOVED"

# The orientation of the container the window is in says which way is "back".
parent() { "$AERO" list-windows --workspace "$tgt" --format '%{window-id} %{window-parent-container-layout}' 2>/dev/null | awk -v w="$wid" '$1==w{print substr($2, 1, 1)}'; }
back_of() { case "$1" in h) echo left ;; v) echo up ;; esac; }

if [ -n "$spw" ] && [ "$spw" != "$wid" ]; then
  place_after "$wid" "$spw" && apply_split "$wid" "$spw"
  log "move: $wid to $tgt, next to $spw as mod+h / mod+v said"
elif [ -n "$want" ]; then
  # Right behind the window moved before it, in whatever container that one
  # ended up in; then joined with it if that runs the other way.
  place_after "$wid" "$prev"
  have=$(parent)
  case "$have" in h|v) ;; *) exit 0 ;; esac   # floating
  [ "$have" = "$want" ] || "$AERO" join-with --window-id "$wid" "$(back_of "$have")" 2>/dev/null
  # It sat before the other one: one step back swaps them.
  [ "$after" = 1 ] || "$AERO" move --window-id "$wid" --boundaries-action fail "$(back_of "$want")" 2>/dev/null
  log "move: $wid to $tgt, $want $([ "$after" = 1 ] && echo after || echo before) $prev (landed in $have)"
else
  have=$(parent)
  case "$have" in h) edge=${dx:--1} ;; v) edge=${dy:--1} ;; *) exit 0 ;; esac
  if [ "$edge" -ge 0 ] && [ "$edge" -lt 40 ]; then
    # To the front. A step into a container goes inside it and the next one
    # comes out the other side, so keep stepping until the edge refuses.
    back=$(back_of "$have")
    for _ in $(seq 30); do "$AERO" move --window-id "$wid" --boundaries-action fail "$back" 2>/dev/null || break; done
    log "move: $wid to the front of $tgt"
  else
    log "move: $wid to the end of $tgt"
  fi
fi

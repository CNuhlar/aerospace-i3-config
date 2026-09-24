#!/bin/bash
# mod+f. If the window is in macOS' own fullscreen (green button), leave it and
# go back to tiling; otherwise toggle AeroSpace's fullscreen. '--fail-if-noop' is
# what makes the fallback work: it exits non-zero when there was nothing to turn
# off.
#
# Then make a terminal redraw once the size has settled. Going fullscreen hands
# the window its new frame in two steps: first a size barely different from the
# old one - macOS clamps the window at the screen edge while it still sits where
# it was - and the real one about 200 ms later. A program in the terminal redraws
# for the first, then again for the second, while iTerm rewraps what is already
# on screen underneath, and what is left is garbled. One more SIGWINCH once the
# size stops changing makes it draw a single time, at the size it will keep.
set -u
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

AERO=$(command -v aerospace || echo /opt/homebrew/bin/aerospace)

# Which terminal is being resized is found by looking, not by asking iTerm:
# AppleScript to iTerm needs an Automation grant AeroSpace does not have, and
# fails silently without it. Every terminal session hangs off a login process,
# so note each one's size before the toggle and signal the ones that changed.
ttys() { ps -axo tty=,comm= | awk '$2 == "/usr/bin/login" && $1 != "??" {print "/dev/" $1}'; }
sizes() { for t in $(ttys); do printf '%s %s\n' "$t" "$(stty -f "$t" size 2>/dev/null | tr ' ' x)"; done; }

before=$(sizes)

"$AERO" macos-native-fullscreen off --fail-if-noop 2>/dev/null || "$AERO" fullscreen

[ "$("$AERO" list-windows --focused --format '%{app-bundle-id}' 2>/dev/null)" = com.googlecode.iterm2 ] || exit 0

# Wait for the size to move and then hold still for a few readings, or give up
# after a second and go with what there is.
last=$before; same=0
for _ in $(seq 20); do
  sleep 0.05
  now=$(sizes)
  if [ "$now" = "$last" ] && [ "$now" != "$before" ]; then
    same=$((same + 1)); [ "$same" -ge 3 ] && break
  else
    same=0
  fi
  last=$now
done

# Only the sizes that changed. A width change makes most full-screen programs
# clear and redraw everything, so one more SIGWINCH at the settled size is all
# they need. A height-only change - fullscreen from a window stacked with
# another - is not enough for some of them: Claude Code only redraws its bottom
# part, and the rows gained stay empty at the top. For those, nudge the width by
# one column and back. The kernel sends SIGWINCH itself on each change, and the
# program sees a width change, so it redraws in full.
comm -13 <(printf '%s\n' "$before" | sort) <(printf '%s\n' "$now" | sort) | while read -r t size; do
  old=$(printf '%s\n' "$before" | awk -v t="$t" '$1==t{print $2}')
  rows=${size%x*}; cols=${size#*x}
  if [ -n "$old" ] && [ "${old#*x}" = "$cols" ] && [ "$cols" -gt 1 ]; then
    stty -f "$t" cols $((cols - 1)) 2>/dev/null
    sleep 0.1
    stty -f "$t" cols "$cols" 2>/dev/null
  else
    # pkill -t finds nothing on macOS; ps -t does.
    pids=$(ps -t "${t#/dev/}" -o pid= 2>/dev/null)
    [ -n "$pids" ] && kill -WINCH $pids 2>/dev/null
  fi
done
exit 0

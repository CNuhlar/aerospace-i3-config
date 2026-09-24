#!/usr/bin/env bash
# mod+enter: a new iTerm window, whether or not one is already open.
#
# Two things make this trickier than a one-liner:
#
#  1. With windows open, "open -a iTerm" only activates - no new window. With
#     *no* windows open, the Shell menu click is what does nothing, because
#     there is no window to hang a menu off. So neither method alone covers
#     both states; we pick by counting windows and keep the other as fallback.
#  2. AeroSpace inherits the environment it was launched with. If it was ever
#     started from inside a Claude Code session it carries CLAUDE_CODE_*, and
#     macOS' `open` hands that straight to iTerm, so every shell iTerm spawns
#     believes it is a nested session and turns transcript saving off. We drop
#     those here so anything we launch starts clean.
set -u

for v in $(env | sed -n 's/^\(CLAUDE_CODE_[A-Z_]*\)=.*/\1/p'); do unset "$v"; done

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

BUNDLE=com.googlecode.iterm2

have_window() {
  [ -n "$(aerospace list-windows --monitor all --app-bundle-id "$BUNDLE" 2>/dev/null)" ]
}

# Wait up to ~1.5s for the window count to go above what we started with.
grew() {  # $1 = count before
  local n=15
  while [ $n -gt 0 ]; do
    [ "$(aerospace list-windows --monitor all --app-bundle-id "$BUNDLE" 2>/dev/null | wc -l)" -gt "$1" ] && return 0
    sleep 0.1; n=$((n - 1))
  done
  return 1
}

before=$(aerospace list-windows --monitor all --app-bundle-id "$BUNDLE" 2>/dev/null | wc -l)

if have_window; then
  # Menu click first: it is the only method that adds a window to a running
  # iTerm instead of just raising the one that is there.
  new_window iTerm2
  grew "$before" && exit 0
  open -a iTerm
else
  # Nothing open (or not running at all): the reopen event Launch Services
  # sends is what makes iTerm build a window.
  open -a iTerm
  grew "$before" && exit 0
  new_window iTerm2
fi

grew "$before" && exit 0

# Last resort. Known to sometimes produce a window with no session in it, which
# is still better than no window.
osascript -e 'tell application "iTerm" to create window with default profile' >/dev/null 2>&1

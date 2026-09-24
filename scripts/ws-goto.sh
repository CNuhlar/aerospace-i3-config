#!/usr/bin/env bash
# Switch workspace / monitor and record the move as intentional, so that
# focus-guard.sh can tell a deliberate switch from an app-activation jump.
set -u
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

AERO=$(command -v aerospace || echo /opt/homebrew/bin/aerospace)
STATE="$HOME/.cache/aerospace-i3"
mkdir -p "$STATE"

record() { "$AERO" list-workspaces --focused > "$STATE/expected" 2>/dev/null; }

# When this key was last pressed. Pressed quickly in a row, the guard's focus
# callback for one switch runs after the next has already rewritten "expected",
# and would read its own switch as an app jump. The guard stands down for a
# moment after any of these.
touch "$STATE/switch-at"

case "${1:-}" in
  --back-and-forth)
    # Target is not known up front: '*' tells the guard to accept whatever comes.
    printf '*' > "$STATE/expected"
    "$AERO" workspace-back-and-forth
    record
    ;;
  --monitor)
    printf '*' > "$STATE/expected"
    "$AERO" focus-monitor "${2:-next}"
    record
    ;;
  --move-to-monitor)
    printf '*' > "$STATE/expected"
    "$AERO" move-node-to-monitor "${2:-next}"
    record
    ;;
  '')
    exit 0
    ;;
  *)
    # Write the expectation BEFORE switching, otherwise the focus callback can
    # fire first and the guard mistakes our own switch for an app jump.
    printf '%s' "$1" > "$STATE/expected"
    "$AERO" workspace "$1"
    ;;
esac

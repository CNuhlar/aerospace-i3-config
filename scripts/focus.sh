#!/bin/bash
# mod+arrow: i3's "focus left/down/up/right". If the keyboard is not where
# AeroSpace thinks it is, the press gives it back instead - see sync_focus in
# lib.sh. Otherwise it is plain 'aerospace focus'.
set -u
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

AERO=$(command -v aerospace || echo /opt/homebrew/bin/aerospace)
. "$(dirname "$0")/lib.sh"

sync_focus && exit 0
exec "$AERO" focus "$1"

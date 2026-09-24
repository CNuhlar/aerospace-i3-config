#!/usr/bin/env bash
# Symlink this repo's config to ~/.aerospace.toml and reload AeroSpace.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target="$HOME/.aerospace.toml"

if [ -e "$target" ] && [ ! -L "$target" ]; then
  backup="$target.backup.$(date +%Y%m%d%H%M%S)"
  mv "$target" "$backup"
  echo "Existing config backed up to $backup"
fi

ln -sfn "$repo/aerospace.toml" "$target"
echo "Linked $target -> $repo/aerospace.toml"

# The config calls these by a fixed path so it stays machine-independent.
scripts_dir="$HOME/.config/aerospace-i3"
mkdir -p "$scripts_dir"
for f in "$repo"/scripts/*.sh; do
  ln -sfn "$f" "$scripts_dir/$(basename "$f")"
done
echo "Linked scripts into $scripts_dir"

if command -v aerospace >/dev/null 2>&1; then
  aerospace reload-config && echo "Config reloaded."
else
  echo "AeroSpace CLI not found. Install it first:"
  echo "  brew install --cask nikitabobko/tap/aerospace"
fi

# Mission Control lays windows out where they actually are. AeroSpace parks the
# windows of every hidden workspace in an off-screen corner, so the layout has
# to span far beyond the display and every window shrinks to a speck. Grouping
# by application replaces that layout with per-app stacks, which is readable
# again. See README, "Three-finger swipe up shows only specks".
if [ "$(defaults read com.apple.dock expose-group-apps 2>/dev/null)" != "1" ]; then
  defaults write com.apple.dock expose-group-apps -bool true
  killall Dock 2>/dev/null || true
  echo "Mission Control set to group windows by application."
fi

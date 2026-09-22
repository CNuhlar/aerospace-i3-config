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

if command -v aerospace >/dev/null 2>&1; then
  aerospace reload-config && echo "Config reloaded."
else
  echo "AeroSpace CLI not found. Install it first:"
  echo "  brew install --cask nikitabobko/tap/aerospace"
fi

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

# Two small native helpers: cmd-space opens Spotlight at once for mod+d, and
# win-frames reads window positions so new windows can go to the end of their
# row. The scripts fall back or skip the step if they cannot be built.
if command -v clang >/dev/null 2>&1; then
  for src in "$repo"/scripts/*.c; do
    bin="$scripts_dir/$(basename "$src" .c)"
    if [ ! -x "$bin" ] || [ "$src" -nt "$bin" ]; then
      clang -O2 -framework ApplicationServices -o "$bin" "$src" && echo "Built $bin"
    fi
  done
else
  echo "clang not found (xcode-select --install): mod+d opens Spotlight a little slower,"
  echo "and new windows open next to the focused one instead of at the end."
fi

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
# again.
if [ "$(defaults read com.apple.dock expose-group-apps 2>/dev/null)" != "1" ]; then
  defaults write com.apple.dock expose-group-apps -bool true
  killall Dock 2>/dev/null || true
  echo "Mission Control set to group windows by application."
fi

# A link clicked in another app (iTerm, WhatsApp, ...) gets a Safari window of
# its own. Left on "Automatically", Safari adds it as a tab to the window it
# already has, and focus-guard then brings that whole window over, old tabs and
# all. A new window is placed like any other, so mod+h / mod+v decide the side.
# Safari Settings -> Tabs -> "Open pages in tabs instead of windows": Never.
if [ "$(defaults read com.apple.Safari TabCreationPolicy 2>/dev/null)" != "0" ]; then
  defaults write com.apple.Safari TabCreationPolicy -int 0 2>/dev/null \
    && echo "Safari: links from other apps open in a new window."
fi

# --- ctrl+left / ctrl+right jump a word in iTerm + zsh -----------------------
# Three pieces, and all three have to be there.

# 1. macOS' "Move left/right a space" (and the Mission Control / app windows
#    ones on ctrl+up/down) take ctrl+arrow before any app sees it. AeroSpace
#    replaces Spaces, so nothing is lost by turning them off.
hotkeys_changed=0
for k in 79 80 81 82; do
  state=$(/usr/libexec/PlistBuddy -c "Print :AppleSymbolicHotKeys:${k}:enabled" \
          "$HOME/Library/Preferences/com.apple.symbolichotkeys.plist" 2>/dev/null || echo missing)
  if [ "$state" != "false" ]; then
    defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys \
      -dict-add "$k" '<dict><key>enabled</key><false/></dict>'
    hotkeys_changed=1
  fi
done
if [ "$hotkeys_changed" = 1 ]; then
  /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u 2>/dev/null || true
  echo "Turned off macOS' ctrl+arrow Space shortcuts."
fi

# 2. Every iTerm profile sends the xterm sequences for ctrl+arrow. Edited on an
#    exported copy and imported back, so cfprefsd sees the change instead of
#    overwriting it with its cached copy.
iterm_plist="$HOME/Library/Preferences/com.googlecode.iterm2.plist"
if [ -e "$iterm_plist" ] && [ "$(defaults read com.googlecode.iterm2 LoadPrefsFromCustomFolder 2>/dev/null)" != "1" ]; then
  tmp=$(mktemp -t iterm2prefs).plist
  defaults export com.googlecode.iterm2 "$tmp"
  pb() { /usr/libexec/PlistBuddy -c "$1" "$tmp" >/dev/null 2>&1; }
  iterm_changed=0
  i=0
  while pb "Print ':New Bookmarks:$i:Guid'"; do
    pb "Print ':New Bookmarks:$i:Keyboard Map'" || pb "Add ':New Bookmarks:$i:Keyboard Map' dict"
    for pair in "0xf702-0x40000-0x7b [1;5D" "0xf703-0x40000-0x7c [1;5C"; do
      key=${pair%% *}; seq=${pair#* }
      m=":New Bookmarks:$i:Keyboard Map:$key"
      [ "$(/usr/libexec/PlistBuddy -c "Print '$m:Text'" "$tmp" 2>/dev/null)" = "$seq" ] && continue
      pb "Delete '$m'"
      pb "Add '$m' dict"
      pb "Add '$m:Action' integer 10"
      pb "Add '$m:Text' string $seq"
      pb "Add '$m:Version' integer 1"
      iterm_changed=1
    done
    i=$((i + 1))
  done
  if [ "$iterm_changed" = 1 ]; then
    defaults import com.googlecode.iterm2 "$tmp"
    echo "iTerm: ctrl+arrow now sends word-jump sequences. Quit and reopen iTerm to pick it up."
  fi
  rm -f "$tmp"
fi

# 3. zsh turns those sequences into word movement. Appended once.
zshrc="$HOME/.zshrc"
if ! grep -qF "'^[[1;5D' backward-word" "$zshrc" 2>/dev/null; then
  cat >> "$zshrc" <<'ZSH'

# ctrl+left / ctrl+right: jump a word (added by ~/i3/install.sh)
bindkey '^[[1;5D' backward-word
bindkey '^[[1;5C' forward-word
ZSH
  echo "Added ctrl+arrow word jump to $zshrc."
fi

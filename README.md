# aerospace-i3-config

An [AeroSpace](https://github.com/nikitabobko/AeroSpace) config that maps i3's keybindings onto macOS, as faithfully as AeroSpace allows.

This is **not a fork** — it is a drop-in `~/.aerospace.toml`. Install AeroSpace the normal way, symlink this config, done.

`mod` is **alt** (i3's Mod1). `cmd` is deliberately left untouched so macOS shortcuts (`cmd+w`, `cmd+f`, `cmd+s`, `cmd+tab`, copy/paste) keep working — see [Why not cmd?](#why-not-cmd).

## Install

```sh
brew install --cask nikitabobko/tap/aerospace

git clone https://github.com/CNuhlar/aerospace-i3-config.git
cd aerospace-i3-config
./install.sh
```

`install.sh` backs up any existing `~/.aerospace.toml`, symlinks this one in its place, and reloads AeroSpace.

Then grant AeroSpace **Accessibility** permission (System Settings → Privacy & Security → Accessibility). Without it the app runs but manages nothing.

## Keybindings

`mod` = `alt`

### Windows

| Key | Action |
|---|---|
| `mod+enter` | new terminal window |
| `mod+d` | Spotlight (i3's dmenu slot) |
| `mod+shift+q` | close window |
| `mod+f` | fullscreen |
| `mod+shift+space` | toggle floating |

### Focus and movement

i3's default finger layout — `j k l ;` rather than `h j k l`, because `h` is taken by split. Arrow keys work everywhere too.

| Key | Action |
|---|---|
| `mod+j` / `k` / `l` / `;` | focus left / down / up / right |
| `mod+shift+j` / `k` / `l` / `;` | move window left / down / up / right |
| `mod+ctrl+j` / `;` | focus monitor left / right |
| `mod+ctrl+shift+j` / `;` | move window to monitor left / right |

### Layout

| Key | Action |
|---|---|
| `mod+h` (or `mod+\`) | split horizontal |
| `mod+v` | split vertical |
| `mod+e` | tiling layout |
| `mod+w` | tabbed layout (accordion) |
| `mod+s` | stacking layout (accordion) |

### Workspaces

| Key | Action |
|---|---|
| `mod+1` … `mod+0` | switch to workspace 1–10 |
| `mod+shift+1` … `mod+shift+0` | move window to workspace 1–10 |
| `mod+tab` | back and forth |
| `mod+shift+tab` | move workspace to next monitor |

### Modes

| Key | Action |
|---|---|
| `mod+r` | resize mode |
| `mod+shift+e` | exit mode (`y` quits AeroSpace, `n` cancels) |
| `mod+shift+c` | reload config |

In resize mode: `j` / `k` / `l` / `;` and arrows resize, `shift` + those resize in smaller steps, `b` balances sizes, `enter` or `esc` returns to normal mode.

Horizontal resize is intentionally inverted relative to i3's default (`j`/← grows, `;`/→ shrinks). Flip the signs in `[mode.resize.binding]` if you prefer i3's direction. Note that either way it can feel backwards: `resize width` grows the **focused window**, not "push the divider this way", so the divider moves in opposite directions depending on which side of the split you are on. AeroSpace has no directional divider command.

## macOS gotchas this config works around

These cost real debugging time. They are documented in comments in `aerospace.toml` too.

### `split` silently does nothing

AeroSpace's normalizations flatten the container tree, which makes the `split` command a no-op — `mod+v` then a new window gives you nothing. Both must be off for i3-style splits:

```toml
enable-normalization-flatten-containers = false
enable-normalization-opposite-orientation-for-nested-containers = false
```

The tradeoff is i3's: closing windows can leave stale single-child containers behind. `balance-sizes` (`b` in resize mode) or `flatten-workspace-tree` cleans up.

### Opening a new terminal window

For iTerm2, two obvious approaches fail:

| Approach | Result |
|---|---|
| `open -na iTerm` | iTerm refuses a second instance — no window at all |
| `create window with default profile` | window opens with **no session in it** |

What works is clicking the menu item:

```
osascript -e 'tell application "iTerm" to activate' \
  -e 'tell application "System Events" to tell process "iTerm2" to click menu item "New Window with Current Profile" of menu 1 of menu bar item "Shell" of menu bar 1'
```

Using a different terminal? Ghostty, Alacritty and kitty all open a real window with plain `open -na <App>`, so you can replace that binding with a one-liner.

### `mod+d` opened a Finder search window

The binding simulates `cmd+space`. But if `alt` is still physically held when the keystroke fires, macOS sees `cmd+alt+space` — which is "Spotlight window", a Finder search. Hence the `delay 0.3` before the keystroke, which waits for `alt` to be released. Increase it if you hold `mod` for longer than that.

### Workspace indicator in the menu bar

No extra tool needed. AeroSpace ships one: its menu bar icon → **Experimental UI Settings → i3 style ordered** shows non-empty workspaces in ascending order with the active one highlighted, which is the i3bar behaviour most people want.

Worth knowing: `i3 style grouped` pulls the active workspace to the front behind a separator, `i3 style ordered` keeps strict numeric order. This setting is **not** part of the config file — it lives in AeroSpace's own preferences, so it has to be set again on each machine.

## Why not cmd?

`cmd` is the natural Super/Mod4 analogue, and this config used it briefly. It is not worth it. Binding `mod+1..9`, `mod+w`, `mod+f`, `mod+s`, `mod+h`, `mod+tab` on `cmd` takes away tab switching, close, find, save, hide and the app switcher in every application at once.

`alt` is barely used by macOS, which is also why it is AeroSpace's own default. To switch anyway, replace every `alt-` at the start of a line in `aerospace.toml` with `cmd-`.

## Customising

- **Terminal**: change the `alt-enter` binding.
- **Launcher**: `alt-d` simulates `cmd+space`; point it at Raycast or Alfred if you use one.
- **Gaps**: the `[gaps]` table, currently 8px everywhere.
- **Floating rules**: `[[on-window-detected]]` blocks at the bottom.

`auto-reload-config = true` is set, so saving the file applies it. `mod+shift+c` reloads manually.

## Credits

[AeroSpace](https://github.com/nikitabobko/AeroSpace) by Nikita Bobko — an i3-like tiling window manager for macOS that does not require disabling SIP. This repo is only a config for it.

## License

MIT

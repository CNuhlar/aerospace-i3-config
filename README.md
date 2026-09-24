# aerospace-i3-config

An [AeroSpace](https://github.com/nikitabobko/AeroSpace) config that maps i3's keybindings onto macOS, as faithfully as AeroSpace allows.

It is a drop-in `~/.aerospace.toml` plus a few helper scripts, not a fork. `mod` is **alt**; `cmd` is left alone so macOS shortcuts keep working.

![Three terminals tiled on macOS: one full-height column on the left, the right column split vertically](docs/screenshot.png)

## Install

```sh
brew install --cask nikitabobko/tap/aerospace

git clone https://github.com/CNuhlar/aerospace-i3-config.git
cd aerospace-i3-config
./install.sh
```

Then grant AeroSpace **Accessibility** permission (System Settings → Privacy & Security → Accessibility). Without it AeroSpace runs but manages nothing.

`install.sh` links the config and scripts, reloads AeroSpace, and sets up a few macOS details (see [What install.sh changes](#what-installsh-changes)). It is safe to run again.

## Keybindings

`mod` = `alt`

### Windows

| Key | Action |
|---|---|
| `mod+enter` | new terminal window (iTerm) |
| `mod+d` | Spotlight; picking an app that is already open gives a new window |
| `mod+shift+q` | close window |
| `mod+f` | fullscreen; also leaves macOS' green-button fullscreen |
| `mod+shift+space` | toggle floating |

### Focus and movement

i3's default finger layout: `j k l ;` (not `h j k l`, `h` is split). Arrow keys work too.

| Key | Action |
|---|---|
| `mod+j` / `k` / `l` / `;` | focus left / down / up / right |
| `mod+shift+j` / `k` / `l` / `;` | move window left / down / up / right |
| `mod+ctrl+j` / `;` | focus monitor left / right |
| `mod+ctrl+shift+j` / `;` | move window to monitor left / right |

### Layout

| Key | Action |
|---|---|
| `mod+h` (or `mod+\`) | next window opens beside this one |
| `mod+v` | next window opens below this one |
| `mod+e` | tiling; press again to toggle horizontal / vertical |
| `mod+w` | tabbed (horizontal accordion) |
| `mod+s` | stacking (vertical accordion) |

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

In resize mode: `j` / `k` / `l` / `;` or arrows resize, with `shift` for smaller steps; `b` balances sizes; `enter` or `esc` goes back. Horizontal is inverted compared to i3 (`j` grows, `;` shrinks); flip the signs in `[mode.resize.binding]` if you prefer i3's way.

## Behaviour to know about

- **Apps don't drag you to other workspaces.** Activating an app whose window is on another workspace (cmd+tab, a clicked link, a window picked in Mission Control) brings that window to you instead, placed as if newly opened, respecting `mod+h` / `mod+v`.
- **`mod+d` on an app that's already open gives a new window**, not the old one raised. Apps without a New Window menu item get their existing window brought over.
- **Closing a window never makes its app reopen one.**
- **Switch workspaces with the keys, not the CLI.** `aerospace workspace 3` from a shell looks like an app jump and you get pulled back. Use `~/.config/aerospace-i3/ws-goto.sh 3`.
- **macOS fullscreen (green button) windows** live in their own Space outside the tiling; `mod+f` inside one brings it back.

Turn the workspace guard off with `touch ~/.cache/aerospace-i3/disabled`. See what it does with `touch ~/.cache/aerospace-i3/debug` and `tail -f ~/.cache/aerospace-i3/log`; `rm` either file to undo.

## What install.sh changes

Besides linking the config into `~/.aerospace.toml` and the scripts into `~/.config/aerospace-i3/` (an existing config is backed up first):

- **Mission Control groups windows by application.** Otherwise AeroSpace's hidden windows shrink the three-finger-swipe view to specks. (System Settings → Desktop & Dock → Mission Control.)
- **ctrl+← / ctrl+→ jump words in iTerm + zsh:** turns off macOS' ctrl+arrow Space shortcuts, adds the key mappings to every iTerm profile, and appends two `bindkey` lines to `~/.zshrc`. Restart iTerm afterwards.

## Tips

- **Workspace indicator in the menu bar:** AeroSpace menu bar icon → Experimental UI Settings → *i3 style ordered*. Stored in AeroSpace's preferences, not this config, so set it on each machine.

  ![Menu bar indicator showing workspaces 1, 3 and 5, with 5 highlighted](docs/menubar.png)

- **Claude Code shows empty rows after `mod+f`:** switch it to the fullscreen renderer with `/tui fullscreen`.
- **`mod+d` opens a Finder search instead of Spotlight:** you are holding `alt` longer than 0.3s; raise the `delay` in `scripts/launcher.sh`.
- **Another terminal:** change the `alt-enter` binding. Ghostty, Alacritty and kitty open a window with plain `open -na <App>`.

## Customising

- **Launcher:** `alt-d` opens Spotlight; point it at Raycast or Alfred instead.
- **Gaps:** the `[gaps]` table, 8px everywhere.
- **Floating rules:** the `[[on-window-detected]]` blocks at the bottom.
- **Use cmd instead of alt:** replace every `alt-` at the start of a line with `cmd-`, at the cost of cmd+w, cmd+f, cmd+tab and friends in every app.

The config reloads on save; `mod+shift+c` reloads by hand.

## Credits

[AeroSpace](https://github.com/nikitabobko/AeroSpace) by Nikita Bobko, an i3-like tiling window manager for macOS that does not require disabling SIP. This repo is only a config for it.

## License

MIT

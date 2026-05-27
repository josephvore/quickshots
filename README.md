# QuickShots

Tiny Hammerspoon module for fast drag-area screenshots that auto-group and paste
into anything — Claude Code, Codex CLI, Slack, browsers, you name it.

## What it does

- **One hotkey** triggers macOS's native drag-area screenshot UI.
- Saves PNGs into `~/Pictures/QuickShots`.
- Screenshots taken within **20 seconds** of each other become an **auto-group**.
- A second hotkey **pastes the latest group** (or the last N) in whatever
  format the active app prefers — newline-separated paths, shell-quoted args,
  Markdown image links, file references, raw image objects, or a ready-to-run
  `codex resume --last --image '...'` command line.
- All actions are also exposed as `hammerspoon://` URL events so
  BetterTouchTool, Raycast, Alfred, or shell scripts can trigger them.

No daemons, no databases, no extra app — just Hammerspoon and `screencapture`.

## Install

You need [Hammerspoon](https://www.hammerspoon.org). Then from this directory:

```sh
./install.sh
```

The installer:

- creates `~/.hammerspoon/` if it does not exist;
- copies `quickshots.lua` to `~/.hammerspoon/quickshots.lua`
  (backing up any prior copy with a timestamped suffix);
- appends a small loader block to `~/.hammerspoon/init.lua`
  (backing up any prior `init.lua` first, and refusing to duplicate the loader).

After install, click the Hammerspoon menu-bar icon → **Reload Config**
(or `hs -c 'hs.reload'` if the CLI is installed).

## Default hotkeys

QuickShots ships with two binding systems. Use whichever suits your keyboard:

### 1. Caps Lock as a held modifier (default)

Caps Lock becomes a "QuickShots" modifier — hold it and tap a letter. Set up
once with `./caps-setup.sh` (it remaps Caps Lock to F18 via `hidutil` and
installs a launch agent so the remap survives reboots). Reverse with
`./caps-uninstall.sh`.

| Hotkey         | Action                                  |
| -------------- | --------------------------------------- |
| `Caps+A`       | Drag-area screenshot                    |
| `Caps+V`       | Paste the latest auto-group             |
| `Caps+N`       | Paste the last `defaultLastN` (4)       |
| `Caps+Shift+V` | Prompt for N, then paste the last N     |
| `Caps+O`       | Open `~/Pictures/QuickShots` in Finder  |

While Caps is held, mapped keys fire QuickShots actions and are consumed.
Unmapped keys type normally — holding Caps and typing `hello` still produces
`hello`. The host app never sees a `Caps` keypress on its own.

### 2. Standard Hammerspoon hotkeys (off by default)

If you'd rather not remap Caps Lock, edit the `hotkeys` table at the top of
`quickshots.lua` and assign each entry a `{ {modifiers}, key }` pair (e.g.
`capture = { { "ctrl", "alt" }, "s" }`). Standard hotkeys and Caps bindings
can coexist — set whichever you don't want to `nil`.

## Configuration

Edit the `config` table at the top of `~/.hammerspoon/quickshots.lua`, or
override fields from `init.lua` before calling `start()`:

```lua
local qs = require("quickshots")
qs.start({
  pasteMode = "codex",
  pasteAfterCopy = false,
  groupWindowSeconds = 30,
  hotkeys = { capture = { { "cmd", "shift" }, "2" } },  -- example override
})
```

| Key                  | Default                       | Notes                                                       |
| -------------------- | ----------------------------- | ----------------------------------------------------------- |
| `saveDir`            | `$HOME/Pictures/QuickShots`   | Created on demand.                                          |
| `groupWindowSeconds` | `20`                          | Window for auto-grouping.                                   |
| `maxHistory`         | `300`                         | History entries beyond this are dropped (oldest first).     |
| `defaultLastN`       | `4`                           | Used by `pasteLastN` and the URL event without `n`.         |
| `pasteMode`          | `"paths"`                     | See **Paste modes** below.                                  |
| `pasteAfterCopy`     | `true`                        | If `true`, send Cmd+V after copying.                        |
| `pasteDelay`         | `0.15`                        | Seconds between clipboard write and Cmd+V.                  |
| `codexCommandPrefix` | `"codex resume --last"`       | Used only by `pasteMode = "codex"`.                         |
| `hotkeys.*`          | see source                    | Each is `{ {modifiers...}, key }` or `nil`.                 |

## Paste modes

| Mode       | Clipboard payload                                                      | Best for                                                       |
| ---------- | ---------------------------------------------------------------------- | -------------------------------------------------------------- |
| `paths`    | Absolute paths, one per line (default).                                | Claude Code, Codex CLI, terminals, anything path-aware.        |
| `quoted`   | Shell-quoted paths, one line, space-separated.                         | Pasting straight into a shell command.                         |
| `markdown` | `![](path)` per line.                                                  | Markdown editors, GitHub issues, Notion-ish surfaces.          |
| `files`    | File references via AppleScript.                                       | Finder. Multi-file paste in non-Finder apps is app-dependent.  |
| `images`   | Raw image objects on the pasteboard.                                   | Slack, browser chat apps. Most apps only accept the first.     |
| `codex`    | `codex resume --last --image '/p/one' --image '/p/two'` (configurable) | Codex CLI image input.                                         |

## URL events (BetterTouchTool, Raycast, Alfred, shell scripts)

Hammerspoon registers itself as the handler for `hammerspoon://` URLs. Each
action is reachable that way, so any tool that can `open` a URL can trigger
QuickShots:

```sh
/usr/bin/open -g 'hammerspoon://quickshot-capture'
/usr/bin/open -g 'hammerspoon://quickshot-paste-group'
/usr/bin/open -g 'hammerspoon://quickshot-paste-last?n=5'
/usr/bin/open -g 'hammerspoon://quickshot-open-folder'
```

The `-g` flag matters: it stops macOS from raising Hammerspoon to the
foreground, so the pending Cmd+V lands in your current app.

In **BetterTouchTool**, set the trigger action to *Open URL / Launch URL* and
paste one of the URLs above. A common setup is a three-finger force-click or
tap mapped to `hammerspoon://quickshot-capture`, and a four-finger swipe-up
mapped to `hammerspoon://quickshot-paste-group`.

## How a typical session feels

1. `Caps+A` (or your BTT gesture). Drag the region you want.
2. Repeat 2–4 times — each shot within 20 s of the previous one extends
   the same group, no matter how long the burst runs in total.
3. Switch to Claude Code / Codex / Slack / your browser.
4. `Caps+V`. The whole group lands in the input — formatted per
   `pasteMode` — and Cmd+V fires automatically.

## Permissions

macOS will ask for these the first time things run:

- **Accessibility** — Hammerspoon needs this to send Cmd+V and watch hotkeys.
- **Screen Recording** — `screencapture` itself usually does not need this,
  but if your captures come back blank, granting it to Hammerspoon is the fix.

System Settings → Privacy & Security → Accessibility / Screen Recording →
toggle Hammerspoon on, then reload its config.

## Troubleshooting

- **Hotkey does nothing.** Open Hammerspoon's Console (menu-bar icon →
  Console) and look for errors. Run `hs.reload()` after any config change.
- **Screenshot is blank.** Grant Hammerspoon **Screen Recording** in
  System Settings, then reload.
- **Cmd+V fires in the wrong app.** Increase `pasteDelay` (e.g. `0.25`), or
  set `pasteAfterCopy = false` and press Cmd+V yourself.
- **`hammerspoon://` URLs are ignored.** Run Hammerspoon at least once so it
  registers as the URL handler. macOS may also prompt the first time you
  open one of these URLs.
- **Two screenshots within the same millisecond.** Filenames include a
  millisecond suffix, so genuine collisions essentially never happen, but
  if one ever does, the second `screencapture` will overwrite the first
  PNG; the duplicate history entry will resolve to that one file.
- **Old shots not showing up after editing config.** History lives in
  Hammerspoon's `hs.settings` store, keyed by `quickshots.history.v1`.
  Reloading config does not clear it; only `hs.settings.clear(...)` does.

## Uninstall

Delete `~/.hammerspoon/quickshots.lua` and remove the
`-- BEGIN QuickShots loader … -- END QuickShots loader` block from
`~/.hammerspoon/init.lua`. Backups (timestamped `*.backup-…`) are left
alone in case you want to roll back. Saved screenshots in
`~/Pictures/QuickShots` are never touched by the installer or the module.

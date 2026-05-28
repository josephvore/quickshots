# QuickShots

A tiny Hammerspoon module for fast drag-area screenshots that auto-group and
paste into anything — Claude Code, Codex CLI, Slack, Messages, browsers,
Markdown editors, you name it.

No daemons. No databases. No extra app to install. Just Hammerspoon, the
built-in `screencapture` binary, and a few hundred lines of Lua.

## Features

- **One keypress → drag-area screenshot.** Native macOS region picker; Space
  toggles window mode; Esc cancels.
- **Caps Lock as a held modifier.** Optional one-time remap turns Caps Lock
  into a QuickShots-only modifier so the bindings never collide with
  anything else on your system. Unmapped keys still type normally while
  Caps is held.
- **Burst mode.** Toggle on, drag as many regions as you want with no
  per-shot keypress, toggle off.
- **Dev capture → Codex.** `Caps+D` captures shots into a per-session dir,
  then opens a new iTerm window running the Codex CLI with the images
  attached and an auto-generated capture-context prompt pre-pasted.
- **Retention sweep.** PNGs older than `retentionDays` (default 30) are
  pruned from the screenshot dirs on start and once a day.
- **Auto-grouping.** Screenshots taken within a configurable time window
  (default 20 s) — or all shots from the same burst — become one paste
  group automatically.
- **Six paste modes.** Newline-separated paths, shell-quoted args, Markdown
  image links, file references (real Finder-style multi-file paste), raw
  image objects, or a ready-to-run `codex --image` command line.
- **URL events.** Every action is reachable via `hammerspoon://…` so
  BetterTouchTool, Raycast, Alfred, Stream Deck, or plain shell scripts
  can trigger captures and pastes.
- **Persistent history.** Last 300 shots are remembered across Hammerspoon
  reloads, so paste-last-N works even after a restart.

## Requirements

- macOS (uses `screencapture`, `hidutil`, NSPasteboard).
- [Hammerspoon](https://www.hammerspoon.org).

## Install

```sh
git clone https://github.com/josephvore/quickshots.git
cd quickshots
./install.sh
```

The installer:

- creates `~/.hammerspoon/` if it does not exist;
- copies `quickshots.lua` to `~/.hammerspoon/quickshots.lua` (backing up
  any prior copy with a timestamped suffix);
- appends a small loader block to `~/.hammerspoon/init.lua` (backing up
  any prior `init.lua` first, and refusing to duplicate the loader).

After install, click the Hammerspoon menu-bar icon → **Reload Config**
(or `hs -c 'hs.reload()'` if the CLI is installed). You should see a
**"QuickShots ready"** toast.

### Caps Lock as held modifier (recommended)

Run once:

```sh
./caps-setup.sh
```

This remaps Caps Lock → F18 via `hidutil` and installs a launch agent so
the remap survives reboots. Reverse it any time with `./caps-uninstall.sh`.

Prefer to leave Caps Lock alone? See **Standard Hammerspoon hotkeys**
below.

## Default bindings

| Hotkey         | Action                                         |
| -------------- | ---------------------------------------------- |
| `Caps+A`       | Drag-area screenshot                           |
| `Caps+Z`       | Toggle burst mode                              |
| `Caps+D`       | Dev capture session → Codex (see below)        |
| `Caps+V`       | Paste latest auto-group (current `pasteMode`)  |
| `Caps+F`       | Paste latest auto-group as files (Finder-style)|
| `Caps+N`       | Paste last `defaultLastN` (4)                  |
| `Caps+Shift+V` | Prompt for N, then paste the last N            |
| `Caps+O`       | Open `~/Pictures/QuickShots` in Finder         |

While Caps is held, mapped keys fire QuickShots actions and are consumed.
Unmapped keys type normally — holding Caps and typing `hello` still
produces `hello`. The host app never sees a `Caps` keypress on its own.

### Burst mode

`Caps+Z` toggles burst on/off. While burst is on:

- Each captured region is tagged with a shared burst id.
- The drag-area picker re-launches automatically after every shot.
- Pressing `Esc` during the picker exits burst cleanly.

`Caps+V` (or `Caps+F`) after a burst pastes the *entire burst*, no matter
how long the burst ran — the time-window grouping doesn't apply to bursts.

### Dev capture → Codex

`Caps+D` runs a self-contained capture-and-hand-off session aimed at the
[Codex CLI](https://github.com/openai/codex):

1. First `Caps+D` starts a session. Shots are saved into a fresh
   per-session dir under `~/Screenshots/dev/<timestamp>/`, and the
   drag-area picker re-launches after every shot (like burst).
2. `Caps+D` again — or `Esc` on an empty picker — finishes the session.
3. If at least one shot was taken, QuickShots:
   - resolves the target repo from the frontmost iTerm session's working
     directory (`git rev-parse --show-toplevel`), falling back to
     `devCapture.defaultRepo`;
   - builds an auto-generated **capture context** block (screenshot count
     + names + time, repo/branch/worktree, and a detected `node`/`next`
     dev-server port — lines are omitted when their data is unavailable);
   - opens a **new iTerm window**, `cd`s into the repo, and runs
     `codex -i <shot1> -i <shot2> …` so the images attach to the TUI;
   - after `devCapture.codexBootDelay` seconds, pastes a staging prompt
     into the TUI input and leaves the cursor on the `Task:` line.

It does **not** press Enter — dictate (or type) your task after the
`Task:` line and submit it yourself.

### Standard Hammerspoon hotkeys (off by default)

If you'd rather not remap Caps Lock, edit the `hotkeys` table at the top
of `quickshots.lua` and assign each entry a `{ {modifiers}, key }` pair
(e.g. `capture = { { "ctrl", "alt" }, "s" }`). Standard hotkeys and Caps
bindings can coexist — set whichever you don't want to `nil`.

## Paste modes

Set `config.pasteMode` to one of:

| Mode       | Clipboard payload                                                      | Best for                                                                  |
| ---------- | ---------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| `paths`    | Absolute paths, one per line (default).                                | Claude Code, Codex CLI, terminals, anything path-aware.                   |
| `quoted`   | Shell-quoted paths, one line, space-separated.                         | Pasting straight into a shell command.                                    |
| `markdown` | `![](path)` per line.                                                  | Markdown editors, GitHub issues, Notion-ish surfaces.                     |
| `files`    | Real `public.file-url` pasteboard items, one per file.                 | Messages, Mail, Notes, Slack, browser file inputs — same as Finder copy.  |
| `images`   | Raw image objects on the pasteboard.                                   | Apps that prefer inline image paste. Most apps only keep the first image. |
| `codex`    | `codex resume --last --image '/p/one' --image '/p/two'` (configurable) | Codex CLI image input.                                                    |

The `Caps+F` shortcut forces `files` mode for one paste, regardless of
your global `pasteMode`. Use `Caps+V` for whatever you've configured as
the default.

## Configuration

Either edit the `config` table at the top of `~/.hammerspoon/quickshots.lua`
directly, or override fields from `init.lua` before `start()`:

```lua
local qs = require("quickshots")
qs.start({
  pasteMode = "codex",
  pasteAfterCopy = false,
  groupWindowSeconds = 30,
  hotkeys = { capture = { { "cmd", "shift" }, "2" } },
})
```

| Key                  | Default                       | Notes                                                       |
| -------------------- | ----------------------------- | ----------------------------------------------------------- |
| `saveDir`            | `$HOME/Pictures/QuickShots`   | Created on demand.                                          |
| `groupWindowSeconds` | `20`                          | Time window for auto-grouping non-burst shots.              |
| `maxHistory`         | `300`                         | History entries beyond this are dropped (oldest first).     |
| `defaultLastN`       | `4`                           | Used by `pasteLastN` and the URL event without `n`.         |
| `pasteMode`          | `"paths"`                     | See **Paste modes** above.                                  |
| `pasteAfterCopy`     | `true`                        | If `true`, send Cmd+V after copying.                        |
| `pasteDelay`         | `0.15`                        | Seconds between clipboard write and Cmd+V.                  |
| `burstRelaunchDelay` | `0.15`                        | Seconds between burst shots (also reused by dev capture).   |
| `codexCommandPrefix` | `"codex resume --last"`       | Used only by `pasteMode = "codex"`.                         |
| `retentionDays`      | `30`                          | Delete `*.png` older than this from `saveDir` + `devCapture.saveDir` on start and daily. `0`/`nil` disables. |
| `devCapture.saveDir` | `$HOME/Screenshots/dev`       | Per-session subdirs (`<timestamp>/`) are created here.      |
| `devCapture.defaultRepo` | `/Volumes/Code/EquipFlow/equipflow` | Fallback repo when the iTerm cwd isn't a git repo.   |
| `devCapture.codexCmd`    | `"codex"`                 | Codex CLI binary; must support `-i/--image`.                |
| `devCapture.codexBootDelay` | `2.5`                  | Seconds to wait for the TUI to boot before pasting the staging prompt. |
| `devCapture.pasteStaging`   | `true`                 | If `true`, paste the staging prompt after boot (cursor on `Task:`). |
| `hotkeys.*`          | all `nil`                     | Each is `{ {modifiers...}, key }` or `nil`.                 |
| `capsBindings.*`     | see source                    | Same shape as `hotkeys`, but fired by the Caps-as-modifier eventtap. |

## URL events (BetterTouchTool, Raycast, Alfred, shell scripts)

Hammerspoon registers itself as the handler for `hammerspoon://` URLs.
Each action is reachable that way:

```sh
/usr/bin/open -g 'hammerspoon://quickshot-capture'
/usr/bin/open -g 'hammerspoon://quickshot-paste-group'
/usr/bin/open -g 'hammerspoon://quickshot-paste-last?n=5'
/usr/bin/open -g 'hammerspoon://quickshot-toggle-burst'
/usr/bin/open -g 'hammerspoon://quickshot-dev-capture'
/usr/bin/open -g 'hammerspoon://quickshot-open-folder'
```

The `-g` flag matters: it stops macOS from raising Hammerspoon to the
foreground, so the pending Cmd+V lands in your current app.

In **BetterTouchTool**, set the trigger action to *Open URL / Launch URL*
and paste one of the URLs above. A common setup is a three-finger
force-click mapped to `hammerspoon://quickshot-capture`, and a four-finger
swipe-up mapped to `hammerspoon://quickshot-paste-group`.

## A typical session

1. `Caps+A`. Drag the region you want.
2. Repeat 2–4 times within 20 s — each shot extends the same group.
   (Or `Caps+Z` once to start a burst, then drag as many as you want and
   `Caps+Z` / `Esc` to stop.)
3. Switch to Claude Code / Codex / Slack / Messages / your browser.
4. `Caps+V` (or `Caps+F` for file paste). The whole group lands in the
   input — formatted per `pasteMode` — and Cmd+V fires automatically.

## Permissions

macOS will prompt the first time things run:

- **Accessibility** — Hammerspoon needs this to send Cmd+V and watch
  hotkeys. Required.
- **Screen Recording** — `screencapture` itself usually does not need
  this, but if your captures come back blank, granting it to Hammerspoon
  is the fix.

System Settings → Privacy & Security → Accessibility / Screen Recording
→ toggle Hammerspoon on, then reload its config.

## Troubleshooting

- **Hotkey does nothing.** Open Hammerspoon's Console (menu-bar icon →
  Console) and look for errors. Run `hs -c 'hs.reload()'` after any
  config change.
- **Hotkey types the letter instead of firing.** The Caps→F18 remap is
  missing. Run `hidutil property --get UserKeyMapping`; if it's empty,
  re-run `./caps-setup.sh` and log out / back in.
- **Screenshot is blank.** Grant Hammerspoon **Screen Recording** in
  System Settings, then reload.
- **Cmd+V fires in the wrong app or before the target focuses.** Bump
  `pasteDelay` (e.g. `0.25`), or set `pasteAfterCopy = false` and press
  Cmd+V yourself.
- **Multi-file paste only delivers one image.** Some apps refuse multi-
  file paste regardless of clipboard format (chat web-apps especially).
  Try `pasteMode = "images"` for that workflow, or paste one at a time.
- **`hammerspoon://` URLs are ignored.** Run Hammerspoon at least once
  so it registers as the URL handler. macOS may also prompt the first
  time you open one of these URLs.
- **Old shots not showing up after editing config.** History lives in
  Hammerspoon's `hs.settings` store keyed by `quickshots.history.v1`.
  Reloading config does not clear it; only `hs.settings.clear(...)` does.

## Uninstall

```sh
./caps-uninstall.sh    # if you ran caps-setup.sh
rm ~/.hammerspoon/quickshots.lua
# Then remove the -- BEGIN QuickShots loader … -- END block from
# ~/.hammerspoon/init.lua and reload Hammerspoon.
```

Backups (timestamped `*.backup-…`) are left alone in case you want to
roll back. Saved screenshots in `~/Pictures/QuickShots` are never
touched by the installer or the module.

## Contributing

Issues and PRs are welcome.

- Keep it scrappy. No external dependencies beyond Hammerspoon. No build
  step. The whole thing should stay readable as a single Lua file.
- Behaviour changes that affect the default bindings or config keys need
  a README update in the same PR.
- Be explicit about what you tested — which apps you pasted into, which
  macOS version, which Hammerspoon version.

Pushing directly to `main` is owner-only. Fork the repo, push your
branch, open a PR from there.

## License

MIT. See [LICENSE](LICENSE).

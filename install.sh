#!/usr/bin/env bash
# Install/upgrade QuickShots into ~/.hammerspoon. Idempotent and non-destructive:
# - Creates ~/.hammerspoon if missing.
# - Backs up an existing init.lua before modifying it.
# - Appends a single loader block; refuses to add a duplicate.
set -euo pipefail

HAMMER_DIR="${HOME}/.hammerspoon"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SCRIPT_DIR}/quickshots.lua"
DEST="${HAMMER_DIR}/quickshots.lua"
INIT="${HAMMER_DIR}/init.lua"
LOADER_MARKER="BEGIN QuickShots loader"
LOADER_BLOCK='-- BEGIN QuickShots loader (managed by quickshots/install.sh)
require("quickshots").start()
-- END QuickShots loader'

if [[ ! -f "${SRC}" ]]; then
  echo "ERROR: cannot find ${SRC}" >&2
  exit 1
fi

mkdir -p "${HAMMER_DIR}"

# Copy/refresh quickshots.lua. If it already exists and differs, back up first.
if [[ -f "${DEST}" ]] && ! cmp -s "${SRC}" "${DEST}"; then
  BACKUP="${DEST}.backup-$(date +%Y%m%d-%H%M%S)"
  cp "${DEST}" "${BACKUP}"
  echo "Backed up existing quickshots.lua → ${BACKUP}"
fi
cp "${SRC}" "${DEST}"
echo "Installed: ${DEST}"

# Add (or skip) the loader in init.lua.
if [[ -f "${INIT}" ]]; then
  if grep -qF "${LOADER_MARKER}" "${INIT}"; then
    echo "Loader already present in ${INIT} — skipping."
  else
    BACKUP="${INIT}.backup-$(date +%Y%m%d-%H%M%S)"
    cp "${INIT}" "${BACKUP}"
    echo "Backed up existing init.lua → ${BACKUP}"
    printf '\n%s\n' "${LOADER_BLOCK}" >> "${INIT}"
    echo "Appended loader to ${INIT}"
  fi
else
  printf '%s\n' "${LOADER_BLOCK}" > "${INIT}"
  echo "Created ${INIT} with loader"
fi

cat <<'EOF'

Next steps:
  1. Install Hammerspoon if you don't have it: https://www.hammerspoon.org
  2. Open Hammerspoon, then click the menu-bar icon → Reload Config.
     (Or run: hs -c 'hs.reload'   if the CLI is installed.)
  3. Grant Accessibility permission when prompted (System Settings →
     Privacy & Security → Accessibility → Hammerspoon).
  4. If a screenshot ever comes back blank, also enable Screen Recording
     for Hammerspoon in the same panel.

Default hotkeys (Caps Lock as held modifier — see caps-setup.sh):
  Caps+A                drag-area screenshot
  Caps+V                paste latest auto-group
  Caps+N                paste last N (default 4)
  Caps+Shift+V          prompt for N, then paste
  Caps+O                open ~/Pictures/QuickShots

Caps-as-modifier requires running caps-setup.sh once to remap Caps Lock → F18.
If you'd rather use plain Hammerspoon hotkeys instead, edit the `hotkeys` table
near the top of ~/.hammerspoon/quickshots.lua and clear `capsBindings`.
EOF

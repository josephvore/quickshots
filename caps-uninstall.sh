#!/usr/bin/env bash
# Reverse caps-setup.sh: stop the launch agent and clear the hidutil remap.
# Caps Lock returns to its normal toggle behavior immediately.
set -euo pipefail

LABEL="com.quickshots.capslock-f18"
PLIST_PATH="${HOME}/Library/LaunchAgents/${LABEL}.plist"
GUI_DOMAIN="gui/$(id -u)"

# Stop the launch agent if it's loaded.
launchctl bootout "${GUI_DOMAIN}/${LABEL}" 2>/dev/null || true

# Remove the plist so it does not reload on next login.
if [[ -f "${PLIST_PATH}" ]]; then
  rm "${PLIST_PATH}"
  echo "Removed launch agent: ${PLIST_PATH}"
else
  echo "No launch agent at ${PLIST_PATH} (already absent)."
fi

# Clear the active hidutil remap for this session.
/usr/bin/hidutil property --set '{"UserKeyMapping":[]}' >/dev/null
echo "Cleared Caps Lock remap. Caps Lock now toggles caps lock normally again."

cat <<'EOF'

If you still want QuickShots, also remove or replace the capsBindings in
~/.hammerspoon/quickshots.lua and reload Hammerspoon's config.
EOF

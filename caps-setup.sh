#!/usr/bin/env bash
# Remap Caps Lock to F18 system-wide and make the remap persist across reboots.
# Caps Lock keystrokes will no longer toggle caps; Hammerspoon turns them into
# the QuickShots modifier instead. Reverse with caps-uninstall.sh.
set -euo pipefail

LABEL="com.quickshots.capslock-f18"
PLIST_DIR="${HOME}/Library/LaunchAgents"
PLIST_PATH="${PLIST_DIR}/${LABEL}.plist"

# HID usage IDs:
#   Caps Lock = 0x700000039
#   F18       = 0x70000006D
MAPPING_JSON='{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x70000006D}]}'

# Apply immediately for the current login session.
/usr/bin/hidutil property --set "${MAPPING_JSON}" >/dev/null
echo "Applied Caps Lock → F18 for the current session."

# Write the launch agent so the remap re-applies on every login.
mkdir -p "${PLIST_DIR}"
cat > "${PLIST_PATH}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/hidutil</string>
    <string>property</string>
    <string>--set</string>
    <string>${MAPPING_JSON}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
EOF
echo "Wrote launch agent: ${PLIST_PATH}"

# (Re)load it now so launchd knows about it. bootstrap fires RunAtLoad once.
GUI_DOMAIN="gui/$(id -u)"
launchctl bootout "${GUI_DOMAIN}/${LABEL}" 2>/dev/null || true
launchctl bootstrap "${GUI_DOMAIN}" "${PLIST_PATH}"
echo "Loaded launch agent. Caps Lock → F18 will persist across reboots."

cat <<'EOF'

Next:
  1. Reload Hammerspoon (menu-bar icon → Reload Config, or hs -c 'hs.reload()').
  2. Try Caps+A — the drag-area screenshot cursor should appear.

To revert this change later, run caps-uninstall.sh.
EOF

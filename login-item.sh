#!/bin/bash
# Start Quill automatically at login (LaunchAgent). Undo with:  ./login-item.sh --remove
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST="$HOME/Library/LaunchAgents/com.quill.dictation.plist"

if [[ "${1:-}" == "--remove" ]]; then
  launchctl unload "$PLIST" 2>/dev/null || true
  rm -f "$PLIST"
  echo "Quill removed from login items."; exit 0
fi

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.quill.dictation</string>
  <key>ProgramArguments</key>
  <array><string>$DIR/.venv/bin/python</string><string>-m</string><string>quill</string></array>
  <key>WorkingDirectory</key><string>$DIR</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><false/>
  <key>StandardOutPath</key><string>/tmp/quill.out</string>
  <key>StandardErrorPath</key><string>/tmp/quill.err</string>
</dict>
</plist>
EOF
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
echo "Quill will start at login. macOS will ask again for Microphone, Accessibility"
echo "and Input Monitoring permission for: $DIR/.venv/bin/python"

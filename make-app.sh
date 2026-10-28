#!/bin/bash
# Build Quill.app so you can start Quill (and open its Settings) by double-clicking,
# from Spotlight, Launchpad or the Dock. No Terminal needed afterwards.
#   ./make-app.sh            build into /Applications (or ~/Applications)
#   ./make-app.sh --login    also start Quill automatically when you log in
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
PY="$DIR/.venv/bin/python"
[[ -x "$PY" ]] || { echo "Run ./install.sh first." >&2; exit 1; }

if [[ -w /Applications ]]; then DEST=/Applications; else DEST="$HOME/Applications"; mkdir -p "$DEST"; fi
APP="$DEST/Quill.app"

echo "==> Building $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Launcher: make sure Quill is running in the menu bar, then show Settings.
# With --background (used at login) it only starts Quill.
{
  echo '#!/bin/bash'
  echo "cd \"$DIR\""
  echo 'if ! pgrep -f -- "-m quill$" >/dev/null; then'
  echo "  nohup \"$PY\" -m quill >/dev/null 2>&1 &"
  echo 'fi'
  echo '[[ "${1:-}" == "--background" ]] && exit 0'
  echo "exec \"$PY\" -m quill.settings"
} > "$APP/Contents/MacOS/Quill"
chmod +x "$APP/Contents/MacOS/Quill"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Quill</string>
  <key>CFBundleDisplayName</key><string>Quill</string>
  <key>CFBundleIdentifier</key><string>com.quill.dictation</string>
  <key>CFBundleVersion</key><string>0.2.0</string>
  <key>CFBundleShortVersionString</key><string>0.2.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>Quill</string>
  <key>CFBundleIconFile</key><string>Quill</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>NSMicrophoneUsageDescription</key><string>Quill listens while you hold the dictation key so it can type what you say.</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "==> Drawing icon"
TMP="$(mktemp -d)"
if "$PY" "$DIR/tools/make_icon.py" "$TMP/Quill.iconset" >/dev/null 2>&1 \
   && iconutil -c icns "$TMP/Quill.iconset" -o "$APP/Contents/Resources/Quill.icns"; then
  cp "$APP/Contents/Resources/Quill.icns" "$DIR/quill/Quill.icns"
  echo "    icon ok"
else
  echo "    (skipped icon; the app still works)"
fi
rm -rf "$TMP"

codesign --force --deep -s - "$APP" >/dev/null 2>&1 || true
touch "$APP"

if [[ "${1:-}" == "--login" ]]; then
  AGENT="$HOME/Library/LaunchAgents/com.quill.dictation.plist"
  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$AGENT" <<AGENTPLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.quill.dictation</string>
  <key>ProgramArguments</key><array><string>/usr/bin/open</string><string>-g</string><string>-a</string><string>$APP</string><string>--args</string><string>--background</string></array>
  <key>RunAtLoad</key><true/>
</dict></plist>
AGENTPLIST
  launchctl unload "$AGENT" 2>/dev/null || true
  launchctl load "$AGENT"
  echo "==> Quill will start when you log in (undo: rm $AGENT)"
fi

echo
echo "Done. Quill is in $DEST. Double-click it, or press ⌘Space and type Quill."
echo "Opening it starts Quill in the menu bar and shows the Settings window."

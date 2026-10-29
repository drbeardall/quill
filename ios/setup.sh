#!/bin/bash
# Creates Quill.xcodeproj and opens it in Xcode.   Run:  cd ~/quill/ios && ./setup.sh
set -euo pipefail
cd "$(dirname "$0")"

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "Xcode isn't set up yet. Open Xcode once (to finish installing), then run:"
  echo "  sudo xcode-select -s /Applications/Xcode.app"
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "==> Installing XcodeGen (builds the Xcode project from project.yml)"
  brew install xcodegen
fi

echo "==> Generating Quill.xcodeproj"
xcodegen generate --quiet

echo "==> Opening Xcode (it will download WhisperKit the first time, ~1 minute)"
open Quill.xcodeproj
echo
echo "Next: in Xcode, pick your Team under Signing & Capabilities for BOTH targets"
echo "(Quill and QuillKeyboard), choose your iPhone at the top, and press ▶ Run."

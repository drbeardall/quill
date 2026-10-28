#!/bin/bash
# Quill installer for macOS. Run from the quill folder:  ./install.sh
set -euo pipefail
cd "$(dirname "$0")"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "Quill runs on macOS only." >&2; exit 1
fi

PY="$(command -v python3 || true)"
if [[ -z "$PY" ]]; then
  echo "python3 not found. Install it with:  brew install python@3.12" >&2; exit 1
fi
if ! "$PY" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)'; then
  echo "Python 3.9+ is required (found $("$PY" --version)). Install with:  brew install python@3.12" >&2; exit 1
fi

echo "==> Creating virtual environment"
"$PY" -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip >/dev/null

echo "==> Installing dependencies"
pip install -r requirements.txt

if [[ "$(uname -m)" == "arm64" ]]; then
  echo "==> Apple Silicon detected: installing mlx-whisper (GPU)"
  if ! pip install mlx-whisper; then
    echo "==> mlx-whisper unavailable for this Python; using faster-whisper (CPU) instead"
    pip install faster-whisper
  fi
else
  echo "==> Intel Mac detected: installing faster-whisper (CPU)"
  pip install faster-whisper
fi

chmod +x run.sh
echo
echo "Done. Start Quill with:  ./run.sh"
echo "Optional, start at login:  ./install.sh --login   (or run ./login-item.sh)"

if [[ "${1:-}" == "--login" ]]; then
  ./login-item.sh
fi

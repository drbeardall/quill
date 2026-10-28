#!/bin/bash
# Quill installer for macOS. Run from the quill folder:  ./install.sh
set -euo pipefail
cd "$(dirname "$0")"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "Quill runs on macOS only." >&2; exit 1
fi

# Prefer a newer Python (e.g. Homebrew's python3.12) over macOS's built-in 3.9.
PY=""
for c in python3.13 python3.12 python3.11 python3.10 /opt/homebrew/bin/python3.12 /usr/local/bin/python3.12 python3; do
  if command -v "$c" >/dev/null 2>&1; then PY="$(command -v "$c")"; break; fi
done
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

chmod +x run.sh make-app.sh
./make-app.sh "$@"

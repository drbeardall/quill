# Quill: push-to-talk dictation for your Mac

Hold a key, talk, let go. Quill transcribes on your Mac with Whisper, has Claude clean it up
(no "um"s, real punctuation, your spellings, the right tone for the app you're in), and types
it wherever your cursor is: Mail, Messages, Chrome, Notes, your EHR, anything.

## Install (about 5 minutes)

Needs macOS 13+ and Python 3.10+ (`brew install python@3.12`).

```bash
cd ~/quill
./install.sh            # add --login to start Quill automatically when you log in
```

This puts **Quill** in your Applications folder. Open it like any app (double-click, or ⌘Space and
type Quill). Opening it starts Quill in the menu bar (🎙) and shows the **Settings window**, where you
can change everything: hotkey, sounds, Claude key, dictionary, snippets and per-app styles. Changes
save and apply instantly.

The first start downloads the speech model (~1.5 GB); the 🎙 shows ◌ until it's ready.

### Permissions

macOS asks the first time. In System Settings → Privacy & Security, allow **Quill** under
**Microphone**, **Input Monitoring** and **Accessibility** (the Settings window has buttons that
open each one), then click **Restart Quill** in the Settings window.

## Using it

| Do this | Get this |
|---|---|
| Hold **Right Option**, talk, release | Cleaned text typed at your cursor |
| Double-tap **Right Option** | Hands-free: keeps listening until you tap once more |
| **Esc** while recording | Cancel |
| Select text, hold **Shift + Right Option**, say an instruction | Command mode: the selection is rewritten ("make this more formal", "turn this into bullets", "translate to Spanish"). With nothing selected, it writes what you ask for. |
| Say a snippet trigger | Saved text inserted ("clinic signature", or mid-sentence: "…send it to my clinic address") |

Menu-bar icon: 🎙 ready · 🔴 dictating · 🟣 command · 🔒 hands-free · ⏳ working.

Spoken formatting works: "new line", "new paragraph", "bullet point", "numbered list", "comma", "question mark".

## Settings

Open the Quill app (or 🎙 → Settings…). Everything is stored in
`~/Library/Application Support/Quill/config.json` if you prefer editing the file.

- **Dictionary**: terms to always spell right; also steers Whisper so it hears them better.
  **Always replace** fixes, e.g. "safe corporation" → "SAIF Corporation".
- **Snippets**: say the trigger, get the text. Snippet text never leaves your Mac.
- **App styles**: tone per app (Formal, Casual, Clinical, or your own description).
  **Local only** keeps that app 100% on your Mac: no Claude cleanup.
- **General**: dictation key, sounds, Claude model, Whisper model, API key.

### Patient information

Audio and transcription always stay on your Mac. When AI cleanup is on, the transcribed
**text** is sent to Anthropic's API. For your charting software, turn on **Local only**, or confirm you have a BAA with Anthropic before sending PHI.
In Settings → App styles, add it and turn on **Local only**.

The log (`~/Library/Logs/Quill.log`) records timings and character counts only, never what you said.

## Troubleshooting

- **Nothing happens when I hold the key**: Input Monitoring isn't granted, or you're in a
  password field (macOS blocks key listening there). Restart Quill after granting.
- **Text is transcribed but not typed**: Accessibility isn't granted.
- **First dictation is slow**: the model is loading; later ones are fast.
- **Whisper invents text from silence**: very short or quiet clips are already ignored; hold the key a bit longer.

## How it's built

```
quill/core.py        config, styles, dictionary, snippets, Claude prompts  (tested: tests/test_core.py)
quill/transcribe.py  local Whisper: mlx-whisper (Apple Silicon) / faster-whisper (Intel)
quill/audio.py       16 kHz mic capture + silence guard
quill/mac.py         front app, clipboard paste, selection, Keychain, sounds
quill/app.py         menu bar + hotkey state machine
```

Run tests: `.venv/bin/pip install pytest && .venv/bin/python -m pytest tests`

# Quill: push-to-talk dictation for your Mac

Hold a key, talk, let go. Quill transcribes on your Mac with Whisper, has Claude clean it up
(no "um"s, real punctuation, your spellings, the right tone for the app you're in), and types
it wherever your cursor is: Mail, Messages, Chrome, Notes, your EHR, anything.

## Install (about 5 minutes)

Needs macOS 13+ and Python 3.10+ (`brew install python@3.12` if you don't have it).

```bash
cd ~/Downloads/quill        # wherever you unzipped it
./install.sh
./run.sh
```

A ◌ appears in the menu bar while the speech model downloads (first run only, ~1.5 GB on
Apple Silicon). It turns into 🎙 when ready.

Then, from the 🎙 menu, choose **Set Claude API key…** and paste a key from
console.anthropic.com. It's stored in your Keychain. Without a key Quill still works, it just
types the raw transcript.

### Permissions (macOS will ask the first time)

Grant all three to **Terminal** (or whichever app runs `./run.sh`) in
System Settings → Privacy & Security:

| Permission | Why |
|---|---|
| Microphone | record your voice |
| Input Monitoring | notice when you hold the hotkey |
| Accessibility | press ⌘V / ⌘C to insert text and read your selection |

Quit and restart Quill after granting them.

To start Quill at login: `./login-item.sh` (undo with `./login-item.sh --remove`).

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

Menu → **Edit settings…** opens `~/Library/Application Support/Quill/config.json`. Save, then
menu → **Reload settings**.

- **dictionary.words**: terms to always spell right (SAIF, subluxation, patient-facing names…).
  These also steer Whisper, so accuracy goes up, not just spelling.
- **dictionary.replacements**: hard fixes applied every time, e.g. `"safe corporation": "SAIF Corporation"`.
- **snippets**: `"trigger phrase": "text to insert"`. Snippet text is expanded on your Mac and never sent to Claude.
- **styles.apps**: per-app tone, keyed by bundle id or app name. Presets: `clean`, `formal`,
  `casual`, `very_casual`, `clinical`, or write your own instruction as the value.
  Add `"cleanup": false` to keep an app **100% local**: nothing leaves your Mac for that app.
- **hotkeys.dictate**: `alt_r` (Right Option) by default. Others: `cmd_r`, `ctrl_r`, `f13`…
- **whisper.model**: `auto` (large-v3-turbo on Apple Silicon, small.en on Intel), or `small.en` for speed.
- **cleanup.model**: `claude-haiku-5-5` (fast, cheap) by default; `claude-sonnet-5-5` for heavier rewriting.

Finding a bundle id: `osascript -e 'id of app "Mail"'`

### Patient information

Audio and transcription always stay on your Mac. When AI cleanup is on, the transcribed
**text** is sent to Anthropic's API. For your charting software, add it with
`"cleanup": false` (fully local), or confirm you have a BAA with Anthropic before sending PHI.
Example:

```json
"Your EHR App Name": { "style": "clinical", "cleanup": false }
```

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

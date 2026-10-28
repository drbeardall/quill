"""Quill menu-bar app: push-to-talk dictation into any Mac app."""
from __future__ import annotations

import copy
import subprocess
import threading
import time
import traceback
from datetime import datetime
from pathlib import Path

import rumps
from pynput import keyboard
from pynput.keyboard import Key

from . import core, mac
from .audio import Recorder, is_speech
from .transcribe import Transcriber

LOG_PATH = Path.home() / "Library" / "Logs" / "Quill.log"

TITLES = {"loading": "◌", "idle": "🎙", "rec": "🔴", "cmd": "🟣", "locked": "🔒", "busy": "⏳"}

KEY_NAMES = {
    "alt_r": "Right Option", "alt_l": "Left Option", "alt": "Option",
    "cmd_r": "Right Command", "ctrl_r": "Right Control", "ctrl": "Control", "f13": "F13",
}

SHIFT = {Key.shift, Key.shift_l, Key.shift_r}
CMD = {Key.cmd, Key.cmd_l, Key.cmd_r}
CTRL = {Key.ctrl, Key.ctrl_l, Key.ctrl_r}
ALT = {Key.alt, Key.alt_l, Key.alt_r}
MODIFIERS = SHIFT | CMD | CTRL | ALT
MOD_GROUPS = {"shift": SHIFT, "cmd": CMD, "ctrl": CTRL, "alt": ALT}

DOUBLE_TAP_WINDOW = 0.5


def log(msg: str) -> None:
    line = f"{datetime.now():%Y-%m-%d %H:%M:%S} {msg}"
    print(line, flush=True)
    try:
        LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
        with LOG_PATH.open("a") as f:
            f.write(line + "\n")
    except OSError:
        pass


class QuillApp(rumps.App):
    def __init__(self) -> None:
        super().__init__(core.APP_NAME, title=TITLES["loading"], quit_button=None)
        self.state = "loading"
        self.status_text = "Loading speech model… (first run downloads it)"
        self.last_text = ""
        self.recorder = Recorder()
        self.transcriber: Transcriber | None = None
        self.engine: core.Engine | None = None
        self.busy = False
        self.recording = False
        self.locked = False
        self.mode = "dictate"
        self.press_time = 0.0
        self.prev_tap = 0.0
        self.front: tuple = (None, None)
        self.held: set = set()

        self.status_item = rumps.MenuItem(self.status_text)
        self.cleanup_item = rumps.MenuItem("AI cleanup (Claude)", callback=self.toggle_cleanup)
        self.menu = [
            self.status_item,
            None,
            rumps.MenuItem("Copy last dictation", callback=self.copy_last),
            self.cleanup_item,
            None,
            rumps.MenuItem("Edit settings…", callback=self.edit_config),
            rumps.MenuItem("Reload settings", callback=self.reload_config),
            rumps.MenuItem("Set Claude API key…", callback=self.set_key),
            rumps.MenuItem("Open log", callback=self.open_log),
            None,
            rumps.MenuItem("Quit Quill", callback=rumps.quit_application),
        ]

        try:
            self.cfg = core.load_config()
        except Exception as e:  # bad JSON: fall back so the app still runs
            log(f"Settings error, using defaults: {e}")
            self.cfg = copy.deepcopy(core.DEFAULT_CONFIG)
            self.status_text = f"Settings file has an error, using defaults: {e}"
        self._apply_config()

        self.timer = rumps.Timer(self._tick, 0.1)
        self.timer.start()
        threading.Thread(target=self._load_model, daemon=True).start()
        self.listener = keyboard.Listener(on_press=self._on_press, on_release=self._on_release)
        self.listener.start()

    # ------------------------------------------------------------------ setup
    def _apply_config(self) -> None:
        hk = self.cfg.get("hotkeys", {})
        self.dictate_key_name = hk.get("dictate", "alt_r")
        self.dictate_key = getattr(Key, self.dictate_key_name, Key.alt_r)
        self.command_mods = MOD_GROUPS.get(hk.get("command_modifier", "shift"), SHIFT)
        self.min_hold = float(hk.get("min_hold_seconds", 0.25))
        api_key = mac.get_api_key()
        llm = core.make_anthropic_llm(api_key, self.cfg) if api_key else None
        self.engine = core.Engine(self.cfg, llm, log=log)
        if not api_key:
            log("No Claude API key set; dictation will insert raw transcripts.")

    def _ready_text(self) -> str:
        k = KEY_NAMES.get(self.dictate_key_name, self.dictate_key_name)
        extra = "" if self.engine and self.engine.llm else "  (no API key: raw text only)"
        return f"Ready: hold {k} to dictate{extra}"

    def _load_model(self) -> None:
        w = self.cfg.get("whisper", {})
        try:
            t = Transcriber(w.get("model", "auto"), w.get("language", "en"), log=log)
            t.warm_up()
            self.transcriber = t
            self.state = "idle"
            self.status_text = self._ready_text()
        except Exception as e:
            log(traceback.format_exc())
            self.status_text = f"Speech model failed to load: {e}"

    # ------------------------------------------------------------- main thread
    def _tick(self, _timer) -> None:
        state = "locked" if (self.recording and self.locked) else self.state
        if self.title != TITLES[state]:
            self.title = TITLES[state]
        if self.status_item.title != self.status_text:
            self.status_item.title = self.status_text
        self.cleanup_item.state = int(bool(self.cfg.get("cleanup", {}).get("enabled", True)))

    def toggle_cleanup(self, _sender) -> None:
        c = self.cfg.setdefault("cleanup", {})
        c["enabled"] = not c.get("enabled", True)
        core.save_config(self.cfg)

    def copy_last(self, _sender) -> None:
        if self.last_text:
            mac.set_clipboard(self.last_text)

    def edit_config(self, _sender) -> None:
        core.load_config()  # make sure the file exists
        subprocess.run(["open", "-t", str(core.CONFIG_PATH)])

    def open_log(self, _sender) -> None:
        LOG_PATH.touch(exist_ok=True)
        subprocess.run(["open", "-a", "Console", str(LOG_PATH)])

    def reload_config(self, _sender) -> None:
        try:
            self.cfg = core.load_config()
            self._apply_config()
            self.status_text = "Settings reloaded. " + self._ready_text()
        except Exception as e:
            self.status_text = f"Settings file has an error: {e}"

    def set_key(self, _sender) -> None:
        w = rumps.Window(
            message="Paste your Anthropic API key (from console.anthropic.com). It is stored in your macOS Keychain.",
            title="Claude API key",
            default_text="",
            ok="Save",
            cancel="Cancel",
            dimensions=(360, 24),
        )
        resp = w.run()
        key = (resp.text or "").strip()
        if resp.clicked and key:
            mac.set_api_key(key)
            self._apply_config()
            self.status_text = self._ready_text()

    # ---------------------------------------------------------- hotkey thread
    def _on_press(self, key) -> None:
        self.held.add(key)
        if key == Key.esc and self.recording:
            self._cancel()
            return
        if key != self.dictate_key:
            return
        if self.recording:
            if self.locked:  # tap again to end hands-free dictation
                self.locked = False
                self._finish()
            return
        if self.busy or self.transcriber is None:
            mac.play("Funk")
            return
        self.mode = "command" if (self.held & self.command_mods) else "dictate"
        self.front = mac.frontmost_app()
        try:
            self.recorder.start()
        except Exception as e:
            log(f"Microphone error: {e}")
            self.status_text = f"Microphone error: {e}"
            return
        self.recording = True
        self.press_time = time.time()
        self.state = "cmd" if self.mode == "command" else "rec"
        if self.cfg.get("sounds", True):
            mac.play("Tink")

    def _on_release(self, key) -> None:
        self.held.discard(key)
        if key != self.dictate_key or not self.recording or self.locked:
            return
        now = time.time()
        if now - self.press_time < self.min_hold:
            if self.press_time - self.prev_tap < DOUBLE_TAP_WINDOW:
                self.locked = True  # double-tap: hands-free until the next tap
                self.prev_tap = 0.0
                return
            self._cancel()
            self.prev_tap = now
            return
        self._finish()

    def _cancel(self) -> None:
        self.recorder.stop()
        self.recording = False
        self.locked = False
        self.state = "idle"

    def _finish(self) -> None:
        audio = self.recorder.stop()
        self.recording = False
        self.busy = True
        self.state = "busy"
        if self.cfg.get("sounds", True):
            mac.play("Pop")
        threading.Thread(target=self._process, args=(audio, self.mode, self.front), daemon=True).start()

    def _wait_mods_released(self, timeout: float = 2.0) -> None:
        deadline = time.time() + timeout
        while (self.held & MODIFIERS) and time.time() < deadline:
            time.sleep(0.02)

    # -------------------------------------------------------- worker thread
    def _process(self, audio, mode: str, front: tuple) -> None:
        t0 = time.time()
        try:
            if not is_speech(audio):
                return
            raw = self.transcriber.transcribe(audio, core.whisper_prompt(self.cfg))
            t1 = time.time()
            style = core.resolve_style(self.cfg, *front)
            if mode == "command":
                if not style["cleanup"]:
                    self.status_text = "Command mode is off in this app (set to local-only)."
                    mac.play("Funk")
                    return
                self._wait_mods_released()
                selection = mac.copy_selection()
                out = self.engine.command(raw, selection, style)
                if out is None:
                    self.status_text = "Command failed. See log."
                    mac.play("Funk")
                    return
            else:
                out = self.engine.dictate(raw, style)
            if out:
                self._wait_mods_released()
                mac.paste_text(out)
                self.last_text = out
            # Log timings and sizes only, never the text itself (may contain patient info).
            log(
                f"{mode} app={front[0]} style={style['name']} cleanup={style['cleanup']} "
                f"audio={len(audio) / 16000:.1f}s stt={t1 - t0:.2f}s total={time.time() - t0:.2f}s chars={len(out or '')}"
            )
            self.status_text = self._ready_text()
        except Exception as e:
            log(traceback.format_exc())
            self.status_text = f"Error: {e}"
            mac.play("Funk")
        finally:
            self.busy = False
            self.state = "idle" if self.transcriber else "loading"


def main() -> None:
    from AppKit import NSApplication

    # Menu-bar only: no Dock icon.
    NSApplication.sharedApplication().setActivationPolicy_(1)
    QuillApp().run()

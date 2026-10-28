"""macOS glue: front app, clipboard paste, reading the selection, Keychain, sounds."""
from __future__ import annotations

import time
from typing import Optional

from AppKit import NSPasteboard, NSPasteboardTypeString, NSSound, NSWorkspace
from pynput.keyboard import Controller, Key

_kb = Controller()


def frontmost_app() -> tuple[Optional[str], Optional[str]]:
    app = NSWorkspace.sharedWorkspace().frontmostApplication()
    if app is None:
        return None, None
    return app.bundleIdentifier(), app.localizedName()


def _pb():
    return NSPasteboard.generalPasteboard()


def _get_clipboard() -> Optional[str]:
    return _pb().stringForType_(NSPasteboardTypeString)


def _set_clipboard(text: str) -> None:
    pb = _pb()
    pb.clearContents()
    pb.setString_forType_(text, NSPasteboardTypeString)


def _cmd(letter: str) -> None:
    with _kb.pressed(Key.cmd):
        _kb.press(letter)
        _kb.release(letter)


def paste_text(text: str, restore: bool = True) -> None:
    """Type text into the front app by pasting, then restore the old clipboard."""
    if not text:
        return
    previous = _get_clipboard()
    _set_clipboard(text)
    time.sleep(0.03)
    _cmd("v")
    if restore:
        time.sleep(0.25)  # let the target app read the pasteboard first
        if previous is not None:
            _set_clipboard(previous)


def copy_selection(timeout: float = 0.4) -> str:
    """Return the selected text in the front app ('' if none), leaving the clipboard as it was."""
    pb = _pb()
    previous = _get_clipboard()
    before = pb.changeCount()
    _cmd("c")
    deadline = time.time() + timeout
    while time.time() < deadline and pb.changeCount() == before:
        time.sleep(0.02)
    if pb.changeCount() == before:
        return ""
    selected = _get_clipboard() or ""
    if previous is not None:
        _set_clipboard(previous)
    return selected


def set_clipboard(text: str) -> None:
    _set_clipboard(text)


def play(name: str) -> None:
    s = NSSound.soundNamed_(name)
    if s is not None:
        s.play()


from .keystore import get_api_key, set_api_key  # noqa: E402,F401

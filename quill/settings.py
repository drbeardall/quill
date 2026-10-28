"""Quill Settings window: a small native window (WebKit) for editing config.json.

Run with:  python -m quill.settings
Every change is saved immediately; the running Quill reloads it within a second.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

from . import core

HTML_PATH = Path(__file__).with_name("settings.html")
LOG_PATH = Path.home() / "Library" / "Logs" / "Quill.log"
QUILL_DIR = Path(__file__).resolve().parent.parent


def _quill_pids() -> list[int]:
    try:
        out = subprocess.run(["pgrep", "-f", "--", "-m quill$"], capture_output=True, text=True).stdout
        return [int(p) for p in out.split()]
    except Exception:
        return []


def _touch_config() -> None:
    try:
        os.utime(core.CONFIG_PATH, None)
    except OSError:
        pass


class Api:
    # ---------------------------------------------------------------- config
    def get_state(self) -> dict:
        cfg = core.load_config()
        return {
            "config": cfg,
            "presets": core.STYLE_PRESETS,
            "key": self.key_status(),
            "running": bool(_quill_pids()),
            "apps": self._installed_names(list(cfg.get("styles", {}).get("apps", {}))),
            "configPath": str(core.CONFIG_PATH),
        }

    def save_config(self, cfg: dict) -> dict:
        try:
            core.save_config(cfg)
            return {"ok": True}
        except Exception as e:
            return {"ok": False, "error": str(e)}

    # --------------------------------------------------------------- API key
    def key_status(self) -> dict:
        from .keystore import get_api_key

        k = get_api_key()
        if not k:
            return {"set": False, "masked": ""}
        return {"set": True, "masked": k[:7] + "…" + k[-4:]}

    def set_key(self, key: str) -> dict:
        from .keystore import set_api_key

        key = (key or "").strip()
        if not key.startswith("sk-"):
            return {"ok": False, "error": "That doesn't look like an Anthropic API key (it should start with sk-ant-)."}
        try:
            set_api_key(key)
            _touch_config()  # tells running Quill to pick up the new key
            return {"ok": True, "key": self.key_status()}
        except Exception as e:
            return {"ok": False, "error": str(e)}

    def clear_key(self) -> dict:
        from .keystore import delete_api_key

        delete_api_key()
        _touch_config()
        return {"ok": True, "key": self.key_status()}

    def test_key(self) -> dict:
        from .keystore import get_api_key

        k = get_api_key()
        if not k:
            return {"ok": False, "error": "No key saved yet."}
        try:
            import anthropic

            cfg = core.load_config()
            client = anthropic.Anthropic(api_key=k, timeout=15, max_retries=0)
            client.messages.create(
                model=cfg.get("cleanup", {}).get("model", "claude-haiku-5-5"),
                max_tokens=5,
                messages=[{"role": "user", "content": "Say OK"}],
            )
            return {"ok": True}
        except Exception as e:
            return {"ok": False, "error": str(e)[:300]}

    # ------------------------------------------------------------------ apps
    def _installed_names(self, bundle_ids: list[str]) -> dict:
        names = {}
        try:
            from AppKit import NSWorkspace
            from Foundation import NSFileManager

            ws = NSWorkspace.sharedWorkspace()
            fm = NSFileManager.defaultManager()
            for bid in bundle_ids:
                url = ws.URLForApplicationWithBundleIdentifier_(bid)
                if url is not None:
                    names[bid] = str(fm.displayNameAtPath_(url.path())).removesuffix(".app")
        except Exception:
            pass
        return names

    def running_apps(self) -> list[dict]:
        apps = []
        try:
            from AppKit import NSWorkspace

            for a in NSWorkspace.sharedWorkspace().runningApplications():
                bid = a.bundleIdentifier()
                if a.activationPolicy() == 0 and bid and not bid.startswith("org.python"):
                    apps.append({"id": str(bid), "name": str(a.localizedName() or bid)})
        except Exception:
            pass
        return sorted(apps, key=lambda x: x["name"].lower())

    # ---------------------------------------------------------- quill process
    def quill_running(self) -> bool:
        return bool(_quill_pids())

    def start_quill(self) -> dict:
        if not _quill_pids():
            subprocess.Popen(
                [sys.executable, "-m", "quill"], cwd=str(QUILL_DIR), start_new_session=True,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
        return {"ok": True}

    def restart_quill(self) -> dict:
        import time

        for pid in _quill_pids():
            try:
                os.kill(pid, 15)
            except OSError:
                pass
        for _ in range(30):
            if not _quill_pids():
                break
            time.sleep(0.1)
        return self.start_quill()

    def open_log(self) -> None:
        LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
        LOG_PATH.touch(exist_ok=True)
        subprocess.run(["open", "-a", "Console", str(LOG_PATH)])

    def open_privacy(self, pane: str) -> None:
        panes = {
            "accessibility": "Privacy_Accessibility",
            "input": "Privacy_ListenEvent",
            "microphone": "Privacy_Microphone",
        }
        subprocess.run(["open", f"x-apple.systempreferences:com.apple.preference.security?{panes.get(pane, '')}"])

    def open_url(self, url: str) -> None:
        if url.startswith("https://"):
            subprocess.run(["open", url])


def _brand_process() -> None:
    """Show 'Quill' and its icon in the Dock and menu bar instead of 'Python'."""
    try:
        from AppKit import NSApplication, NSImage
        from Foundation import NSBundle

        info = NSBundle.mainBundle().infoDictionary()
        if info is not None:
            info["CFBundleName"] = "Quill"
        icon = Path(__file__).with_name("Quill.icns")
        if icon.exists():
            NSApplication.sharedApplication().setApplicationIconImage_(
                NSImage.alloc().initWithContentsOfFile_(str(icon))
            )
    except Exception:
        pass


def main() -> None:
    import webview

    _brand_process()
    webview.create_window(
        "Quill Settings",
        url=str(HTML_PATH),
        js_api=Api(),
        width=860,
        height=640,
        min_size=(720, 520),
    )
    webview.start()


if __name__ == "__main__":
    main()

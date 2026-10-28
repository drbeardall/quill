"""Claude API key storage in the macOS Keychain (env var ANTHROPIC_API_KEY overrides)."""
from __future__ import annotations

import os
from typing import Optional

SERVICE = "Quill"
USER = "anthropic_api_key"


def get_api_key() -> Optional[str]:
    if os.environ.get("ANTHROPIC_API_KEY"):
        return os.environ["ANTHROPIC_API_KEY"]
    try:
        import keyring

        return keyring.get_password(SERVICE, USER)
    except Exception:
        return None


def set_api_key(key: str) -> None:
    import keyring

    keyring.set_password(SERVICE, USER, key)


def delete_api_key() -> None:
    try:
        import keyring

        keyring.delete_password(SERVICE, USER)
    except Exception:
        pass

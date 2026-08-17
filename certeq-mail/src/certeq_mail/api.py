"""Certeq portal API client.

Replaces the VBA MSXML2.ServerXMLHTTP calls and the registry-based token
storage (GetSetting/SaveSetting "Certeq"/"Portal_API"). Credentials and the
bearer token live in the macOS Keychain via `keyring`; non-secret state
(username, token expiry) lives in ~/.config/certeq-mail/config.json.
"""

import getpass
import json
import time
from pathlib import Path

import httpx
import keyring

BASE = "https://api.certeq.com.au"
SERVICE = "certeq-portal"
CONFIG_DIR = Path.home() / ".config" / "certeq-mail"
CONFIG_FILE = CONFIG_DIR / "config.json"


def _load_config() -> dict:
    if CONFIG_FILE.exists():
        return json.loads(CONFIG_FILE.read_text())
    return {}


def _save_config(cfg: dict) -> None:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    CONFIG_FILE.write_text(json.dumps(cfg, indent=2))


def login(username: str | None = None, password: str | None = None) -> dict:
    cfg = _load_config()
    if not username:
        default = cfg.get("username", "")
        prompt = f"Certeq username [{default}]: " if default else "Certeq username: "
        username = input(prompt).strip() or default
    if not username:
        raise SystemExit("A username is required.")
    if not password:
        password = getpass.getpass("Certeq password: ")

    resp = httpx.post(
        f"{BASE}/oauth/token",
        json={"username": username, "password": password, "grant_type": "password"},
        timeout=30,
    )
    resp.raise_for_status()
    data = resp.json()

    keyring.set_password(SERVICE, "token", data["access_token"])
    keyring.set_password(SERVICE, username, password)
    cfg.update(
        username=username,
        display_name=data.get("display_name", ""),
        token_expiry=time.time() + int(data.get("expires_in", 3600)),
    )
    _save_config(cfg)
    return data


def get_token() -> str:
    cfg = _load_config()
    token = keyring.get_password(SERVICE, "token")
    if token and time.time() < cfg.get("token_expiry", 0):
        return token

    # Token missing or expired — re-login silently with the stored password.
    username = cfg.get("username")
    if username:
        password = keyring.get_password(SERVICE, username)
        if password:
            login(username, password)
            return keyring.get_password(SERVICE, "token")

    raise SystemExit("Not logged in — run: uv run certeq login")


def query(report_id: int, **params) -> object:
    resp = httpx.get(
        f"{BASE}/custom-reports/queries/{report_id}",
        params=params or None,
        headers={
            "Authorization": f"Bearer {get_token()}",
            "Accept": "application/json",
        },
        timeout=60,
    )
    resp.raise_for_status()
    return resp.json()


def rows(payload: object) -> list[dict]:
    """Normalise a report payload to a list of row dicts."""
    if isinstance(payload, list):
        return [r for r in payload if isinstance(r, dict)]
    if isinstance(payload, dict):
        for key in ("data", "rows", "results", "items"):
            if isinstance(payload.get(key), list):
                return [r for r in payload[key] if isinstance(r, dict)]
        return [payload]
    return []


def first_row(payload: object, *required: str) -> dict:
    """First row containing all the required column names."""
    for row in rows(payload):
        if all(k in row for k in required):
            return row
    raise SystemExit(
        f"API response has no row with columns {list(required)}.\n"
        f"Response was:\n{json.dumps(payload, indent=2)[:2000]}"
    )

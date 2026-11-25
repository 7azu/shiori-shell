#!/usr/bin/env python3
"""Fetch the Claude plan limits (5 h / 7 days) directly from Anthropic -> ~/.cache/quickshell/claude-limits.json.

The limits apply to the whole account: usage on another machine counts here too. claude_statusline.sh
writes the same file, but only while Claude Code runs on THIS machine. This script queries
the same endpoint as Claude Code's /usage, with its OAuth token (~/.claude/.credentials.json).

The token only goes to api.anthropic.com (limits) and platform.claude.com (refresh). The access token
is valid for 8 h, so after a night it has expired. Then this script refreshes it itself - but ONLY
when no Claude Code is running: on refresh the server also replaces the refresh token, a
running Claude Code would then have an invalid one in memory and would be logged out. If one is running,
it refreshes the token itself and we read it on the next try. The new token is written back to
.credentials.json the way Claude Code stores it (same fields, the rest unchanged).

Output (stdout, one JSON line): {"ok": true} or {"ok": false, "error": "..."}
"""
import fcntl
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

CREDENTIALS = Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude") / ".credentials.json"
OUT = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "quickshell" / "claude-limits.json"
URL = "https://api.anthropic.com/api/oauth/usage"
# As in Claude Code (production config: TOKEN_URL / CLIENT_ID)
TOKEN_URL = "https://platform.claude.com/v1/oauth/token"
CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
LOCK = OUT.parent / "claude-token.lock"


def result(ok, error="", retry_after=0):
    print(json.dumps({"ok": ok, "error": error, "retryAfter": retry_after}))
    return 0


def read_oauth():
    return json.loads(CREDENTIALS.read_text())["claudeAiOauth"]


def expired(oauth):
    # 1 min buffer
    return oauth.get("expiresAt", 0) / 1000 < time.time() + 60


def claude_running():
    """Is any Claude Code of this user running? (process name "claude")"""
    uid = os.getuid()
    for pid in os.listdir("/proc"):
        if not pid.isdecimal():
            continue
        try:
            if os.stat(f"/proc/{pid}").st_uid != uid:
                continue
            if Path(f"/proc/{pid}/comm").read_text().strip() == "claude":
                return True
        except OSError:
            continue
    return False


def write_credentials(update):
    """Write the new token to .credentials.json: atomic, 0600, all other fields stay."""
    data = json.loads(CREDENTIALS.read_text())
    data["claudeAiOauth"].update(update)
    tmp = CREDENTIALS.with_name(CREDENTIALS.name + ".quickshell-tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(data, f)
    tmp.replace(CREDENTIALS)


def refresh(oauth):
    """Refresh the access token. Returns (oauth, error)."""
    if claude_running():
        return None, "login expired - Claude Code is running and refreshes it"
    if not oauth.get("refreshToken"):
        return None, "login expired - run /login in Claude Code"
    LOCK.parent.mkdir(parents=True, exist_ok=True)
    with open(LOCK, "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        # Has someone else (a second Quickshell, Claude Code) refreshed meanwhile?
        try:
            oauth = read_oauth()
        except (OSError, ValueError, KeyError):
            return None, "not logged in to Claude Code"
        if not expired(oauth):
            return oauth, ""
        body = {"grant_type": "refresh_token", "refresh_token": oauth["refreshToken"], "client_id": CLIENT_ID}
        if oauth.get("scopes"):
            body["scope"] = " ".join(oauth["scopes"])
        req = urllib.request.Request(TOKEN_URL, data=json.dumps(body).encode(), headers={
            "Content-Type": "application/json",
            "User-Agent": "quickshell-claude-limits",
        })
        try:
            with urllib.request.urlopen(req, timeout=15) as r:
                d = json.load(r)
        except urllib.error.HTTPError as e:
            if e.code in (400, 401):
                # invalid_grant: the refresh token itself expired/was revoked -> a real new login
                return None, "login expired - run /login in Claude Code"
            return None, f"token refresh HTTP {e.code}"
        except (OSError, ValueError) as e:
            return None, f"offline ({e.__class__.__name__})"
        if not d.get("access_token") or not isinstance(d.get("expires_in"), (int, float)):
            return None, "token refresh: bad response"
        now = time.time()
        update = {
            "accessToken": d["access_token"],
            "refreshToken": d.get("refresh_token") or oauth["refreshToken"],
            "expiresAt": int((now + d["expires_in"]) * 1000),
        }
        if isinstance(d.get("refresh_token_expires_in"), (int, float)):
            update["refreshTokenExpiresAt"] = int((now + d["refresh_token_expires_in"]) * 1000)
        if isinstance(d.get("scope"), str) and d["scope"].strip():
            update["scopes"] = d["scope"].split()
        try:
            write_credentials(update)
        except (OSError, ValueError, KeyError) as e:
            return None, f"token refresh: cannot save ({e.__class__.__name__})"
        oauth.update(update)
        return oauth, ""


def main():
    try:
        oauth = read_oauth()
    except (OSError, ValueError, KeyError):
        return result(False, "not logged in to Claude Code")
    if expired(oauth):
        oauth, error = refresh(oauth)
        if error:
            return result(False, error)
    token = oauth.get("accessToken")
    if not token:
        return result(False, "not logged in to Claude Code")

    req = urllib.request.Request(URL, headers={
        "Authorization": "Bearer " + token,
        "anthropic-beta": "oauth-2025-04-20",
        "User-Agent": "quickshell-claude-limits",
    })
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            data = json.load(r)
    except urllib.error.HTTPError as e:
        retry_after = e.headers.get("Retry-After", "")
        return result(False, f"HTTP {e.code}", int(retry_after) if retry_after.isdecimal() else 0)
    except (OSError, ValueError) as e:
        return result(False, f"offline ({e.__class__.__name__})")

    # Only the two windows the bar shows; same format as claude_statusline.sh
    limits = {k: data[k] for k in ("five_hour", "seven_day") if isinstance(data.get(k), dict)}
    if not limits:
        return result(False, "no limits in response")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    tmp = OUT.with_suffix(".tmp")
    tmp.write_text(json.dumps({"updated": int(time.time()), "source": "api", "rate_limits": limits}))
    tmp.replace(OUT)
    return result(True)


if __name__ == "__main__":
    sys.exit(main())

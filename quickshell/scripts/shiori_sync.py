#!/usr/bin/env python3
"""Sync entries of the bar's sync dropdown (services/SyncState.qml), from "sync" in the settings.

Each entry has an id, a name, an icon (Nerd Font glyph) and a type:

  {"id": "notes", "name": "Notes", "icon": "", "type": "git", "path": "~/Documents/Notes"}
  {"id": "drive", "name": "Drive", "icon": "", "type": "rclone", "remote": "gdrive:",
   "folders": [["~/Music", "Music"], ["~/Pictures", "Pictures"]]}
  {"id": "dots", "name": "Dotfiles", "icon": "", "type": "command",
   "check": ["~/bin/dots", "--check"], "run": ["~/bin/dots"], "input": ["~/bin/dots", "--code"]}

Optional for every entry: "sshKey": true (unlock the SSH key in the agent before syncing, scripts in hypr/scripts)
or "sshKey": "<path>" (use this key for the sync, e.g. one without a passphrase only for syncing),
"kind": "git" | "rclone" (how the dropdown shows progress), "rcSocket" (rclone remote-control socket).

  shiori_sync.py list            entries as JSON
  shiori_sync.py check <id>      pending changes, no network -> JSON {pending, files, subtitle, state, message, prompt}
  shiori_sync.py run <id>        sync (the shell starts this as systemd unit shiori-sync-<id>)
  shiori_sync.py input <id>      pass a value on stdin to the entry (e.g. a 2FA code), exit 0 = accepted

Protocol for "command" entries: check prints JSON as above (or just a number = pending). run reports
progress itself via sync_progress.py <id> ... or not at all; exit 0 = ok, 75 = offline,
77 = needs input (shows a field with "prompt"), anything else = error.
"""
import json
import os
import shutil
import subprocess
import sys
import time

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import shiori_settings  # noqa: E402
import sync_progress  # noqa: E402

HOME = os.path.expanduser("~")
RUNTIME = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
HYPR_SCRIPTS = os.path.join(HOME, ".config", "hypr", "scripts")
EXIT_STATES = {0: "ok", 75: "offline", 77: "input"}


def expand(value):
    if isinstance(value, str):
        return shiori_settings.expand(value.replace("$XDG_RUNTIME_DIR", RUNTIME))
    return value


def entries():
    out = []
    for raw in shiori_settings.load().get("sync", []) or []:
        if not isinstance(raw, dict) or not raw.get("id"):
            continue
        e = dict(raw)
        kind = e.get("type", "command")
        if kind == "git":
            path = expand(e.get("path", ""))
            base = [sys.executable, os.path.join(HERE, "git_sync.py"), "--path", path, "--id", e["id"]]
            e.setdefault("check", base + ["--check"])
            e.setdefault("run", base)
            e.setdefault("subtitle", shiori_settings.expand(e.get("path", "")).replace(HOME, "~", 1))
            e.setdefault("kind", "git")
        elif kind == "rclone":
            e.setdefault("run", [sys.executable, os.path.abspath(__file__), "rclone-run", e["id"]])
            e.setdefault("rcSocket", os.path.join(RUNTIME, "shiori-sync", e["id"] + ".sock"))
            e.setdefault("subtitle", " · ".join(f[1] for f in e.get("folders", []) if len(f) == 2))
            e.setdefault("kind", "rclone")
        e.setdefault("kind", "git")
        for key in ("check", "run", "input"):
            if isinstance(e.get(key), list):
                e[key] = [expand(a) for a in e[key]]
        if e.get("rcSocket"):
            e["rcSocket"] = expand(e["rcSocket"])
        out.append(e)
    return out


def find(entry_id):
    for e in entries():
        if e["id"] == entry_id:
            return e
    print(f"no sync entry '{entry_id}'", file=sys.stderr)
    sys.exit(64)


def cmd_list():
    keys = ("id", "name", "icon", "kind", "subtitle", "rcSocket", "prompt", "sshKey")
    print(json.dumps([{**{k: e.get(k) for k in keys if e.get(k) is not None},
                       "hasCheck": bool(e.get("check")), "hasInput": bool(e.get("input"))} for e in entries()]))


def cmd_check(entry_id):
    e = find(entry_id)
    result = {"pending": 0}
    if e.get("check"):
        try:
            out = subprocess.run(e["check"], capture_output=True, text=True, timeout=60).stdout.strip()
            data = json.loads(out) if out else {}
            if isinstance(data, (int, float)):
                data = {"pending": int(data)}
            if isinstance(data, dict):
                result.update(data)
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            result.update(state="error", message=str(error))
    if result.get("state") == "input" and "prompt" not in result:
        result["prompt"] = e.get("prompt", "Code")
    print(json.dumps(result))


# ---------- run ----------

def vpn_ready():
    """With the VPN killswitch of the shell on, wait for the tunnel (otherwise nothing gets out)."""
    blocked = subprocess.run(["sudo", "-n", "nft", "list", "table", "inet", "killswitch"],
                             capture_output=True).returncode == 0
    if not blocked:
        return True
    return bool(subprocess.run(["ip", "link", "show", "type", "wireguard", "up"],
                               capture_output=True, text=True).stdout.strip())


def wait_for_network():
    with open("/proc/uptime") as f:
        wait = 120 if float(f.read().split()[0]) < 300 else 10
    while not vpn_ready() and wait > 0:
        time.sleep(5)
        wait -= 5
    return vpn_ready()


def unlock_ssh_key(env, key=True):
    unlock = os.path.join(HYPR_SCRIPTS, "ssh-unlock.sh")
    if not os.access(unlock, os.X_OK):
        return True
    # "sshKey": "<path>" -> that key (ssh-unlock.sh reads it from SSH_UNLOCK_KEY); true -> the agent's keys
    if isinstance(key, str) and key:
        env["SSH_UNLOCK_KEY"] = shiori_settings.expand(key)
    identity = subprocess.run([unlock, "--identity"], capture_output=True, text=True, env=env).stdout.strip()
    ssh = "ssh -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=3 -o BatchMode=yes"
    if identity:
        ssh += f' -o IdentitiesOnly=yes -o IdentityAgent=none -i "{identity}"'
    env["GIT_SSH_COMMAND"] = ssh
    env.setdefault("SSH_AUTH_SOCK", os.path.join(RUNTIME, "ssh-agent.socket"))
    return subprocess.run([unlock], env=env).returncode == 0


def cmd_run(entry_id):
    e = find(entry_id)
    if not e.get("run"):
        return 64
    started = time.time()
    env = dict(os.environ)
    if e.get("sshKey") and not unlock_ssh_key(env, e["sshKey"]):
        sync_progress.start(entry_id)
        sync_progress.done(entry_id, "locked", "SSH key locked")
        return 1
    if not wait_for_network():
        sync_progress.start(entry_id)
        sync_progress.done(entry_id, "offline", "VPN not connected")
        return 75
    try:
        proc = subprocess.run(e["run"], env=env, stdout=subprocess.PIPE, text=True)
        code, out = proc.returncode, proc.stdout.strip()
    except OSError as error:
        code, out = 127, str(error)
    if out:
        print(out)
    # Commands that do not report progress themselves (or stopped without a result): write it here
    data = sync_progress._load(entry_id)
    reported = data.get("run", 0) >= started - 1
    if not reported or data.get("state") == "running":
        if not reported:
            sync_progress.start(entry_id)
        state = EXIT_STATES.get(code, "error")
        summary = out.splitlines()[-1] if out else ("Synced" if state == "ok" else "Sync failed")
        sync_progress.done(entry_id, state, summary)
    return code


def cmd_input(entry_id):
    e = find(entry_id)
    if not e.get("input"):
        return 64
    value = sys.stdin.read()
    try:
        return subprocess.run(e["input"], input=value, text=True).returncode
    except OSError:
        return 127


# ---------- built-in rclone ----------

def cmd_rclone_run(entry_id):
    """rclone bisync for every folder pair; live values over the remote-control socket."""
    e = find(entry_id)
    if not shutil.which("rclone"):
        sync_progress.start(entry_id)
        sync_progress.done(entry_id, "error", "rclone is not installed")
        return 1
    remote = e.get("remote", "")
    folders = [f for f in e.get("folders", []) if isinstance(f, list) and len(f) == 2]
    state_dir = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.join(HOME, ".local", "state"),
                             "shiori-sync", entry_id)
    os.makedirs(state_dir, exist_ok=True)
    sock = e["rcSocket"]
    os.makedirs(os.path.dirname(sock), exist_ok=True)
    sync_progress.start(entry_id, len(folders))
    failed = []
    for n, (local, path) in enumerate(folders, 1):
        local = expand(local)
        sync_progress.step(entry_id, n, path)
        marker = os.path.join(state_dir, path.replace("/", "_") + ".done")
        cmd = ["rclone", "bisync", local, remote + path, "--rc", "--rc-addr", "unix://" + sock,
               "--create-empty-src-dirs", "--resilient", "--recover", "--max-lock", "2m"]
        if not os.path.exists(marker):
            cmd.append("--resync")  # first run: build the listings both sides
        if subprocess.run(cmd).returncode == 0:
            open(marker, "w").close()
        else:
            failed.append(path)
    if failed:
        sync_progress.done(entry_id, "error", "Failed: " + ", ".join(failed))
        return 1
    sync_progress.done(entry_id, "ok", "Synced")
    return 0


def main(argv):
    if not argv:
        print((__doc__ or "").strip(), file=sys.stderr)
        return 64
    command = argv[0]
    if command == "list":
        cmd_list()
        return 0
    if len(argv) < 2:
        return 64
    handler = {"check": cmd_check, "run": cmd_run, "input": cmd_input, "rclone-run": cmd_rclone_run}.get(command)
    if not handler:
        return 64
    return handler(argv[1]) or 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

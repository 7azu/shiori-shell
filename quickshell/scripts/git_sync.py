#!/usr/bin/env python3
"""Two-way sync of a Git folder (notes, vault ...) for the sync dropdown, built-in type "git".

  git_sync.py --path <folder> --id <entry>          commit local changes, fetch, merge, push
  git_sync.py --path <folder> --id <entry> --check  count pending changes (no network) -> JSON

The folder needs a branch with a remote tracking branch. Files over GitHub's 100 MiB limit stay
local and are added to .gitignore. Progress goes to sync_progress.py under the entry id.
"""

import argparse
import json
import os
from pathlib import Path
import re
import socket
import stat
import subprocess
import sys

try:
    # Progress for the sync dropdown (same folder); without the helper the sync runs anyway.
    # No __pycache__ next to the scripts
    sys.dont_write_bytecode = True
    import sync_progress as progress
except ImportError:
    progress = None


GITHUB_FILE_LIMIT = 100 * 1024**2
HOME = Path.home()
PART = "git"  # progress id, set from --id


class SyncError(Exception):
    pass


def git(vault, *args, data=None, check=True, probe=False, timeout=None):
    return subprocess.run(
        ["git", "-C", vault, *args], input=data, stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL if probe else None, check=check, timeout=timeout,
    )


def repo_path(path):
    vault = Path(path).expanduser()
    result = git(vault, "rev-parse", "--show-toplevel", check=False, probe=True)
    if result.returncode or Path(os.fsdecode(result.stdout.rstrip(b"\n"))).resolve() != vault.resolve():
        raise SyncError(f"{path} is not the top folder of a Git repo")
    return vault


def nul_join(paths):
    return b"".join(path + b"\0" for path in paths)


def working_changes(vault):
    unstaged = git(vault, "ls-files", "-z", "--modified", "--others", "--exclude-standard")
    return set(unstaged.stdout.split(b"\0")) - {b""}


def changed_paths(vault):
    staged = git(vault, "diff", "--cached", "--name-only", "--no-renames", "-z")
    return working_changes(vault) | (set(staged.stdout.split(b"\0")) - {b""})


def oversized_files(vault, paths):
    oversized = set()
    for path in paths:
        try:
            info = (vault / os.fsdecode(path)).lstat()
        except (FileNotFoundError, NotADirectoryError):
            continue
        if stat.S_ISREG(info.st_mode) and info.st_size > GITHUB_FILE_LIMIT:
            oversized.add(path)
    return oversized


def ignored_paths(vault, paths):
    if not paths:
        return set()
    result = git(vault, "check-ignore", "--no-index", "-z", "--stdin", data=nul_join(paths), check=False)
    if result.returncode > 1:
        raise SyncError("Could not read Git ignore rules")
    return set(result.stdout.split(b"\0")) - {b""}


def add_ignore_rules(vault, paths):
    # Git ignore patterns are line based. Filenames containing a newline are excluded
    # explicitly from staging, since no exact .gitignore rule can name them.
    paths = sorted(path for path in paths if b"\n" not in path)
    if not paths:
        return False
    ignore = vault / ".gitignore"
    if ignore.is_symlink() or b".gitignore" in paths:
        raise SyncError("Cannot update the .gitignore")

    rules = []
    for path in paths:
        literal = re.sub(rb"([\\*?\[\] ])", rb"\\\1", path)
        # The slash anchors the rule to the vault root and makes initial # and ! literal.
        rules.append(b"/" + literal.replace(b"\r", b"[\r]"))
    existing = ignore.read_bytes() if ignore.exists() else b""
    with ignore.open("ab") as output:
        if existing and not existing.endswith(b"\n"):
            output.write(b"\n")
        if b"# Files over GitHub's 100 MiB limit\n" not in existing:
            output.write(b"\n# Files over GitHub's 100 MiB limit\n")
        output.write(b"\n".join(rules) + b"\n")
    return True


def oversized_blobs(vault, object_ids):
    objects = git(vault, "cat-file", "--batch-check=%(objectname) %(objecttype) %(objectsize)", data=object_ids)
    return {oid for oid, kind, size in (line.split() for line in objects.stdout.splitlines())
            if kind == b"blob" and int(size) > GITHUB_FILE_LIMIT}


def staged_oversized(vault):
    raw = git(vault, "diff", "--cached", "--raw", "--no-abbrev", "--no-renames", "-z",
              "--diff-filter=AMT").stdout.rstrip(b"\0").split(b"\0")
    entries = [(meta.split()[3], path) for meta, path in zip(raw[::2], raw[1::2])
               if meta.split()[1] != b"160000"]
    big = oversized_blobs(vault, b"".join(oid + b"\n" for oid, _ in entries))
    return {path for oid, path in entries if oid in big}


def stage_changes(vault, oversized):
    if oversized:
        # Restore the staged version from HEAD. Keep the working copy and the last
        # synchronizable version of an already tracked attachment on other devices.
        git(vault, "--literal-pathspecs", "reset", "-q", "HEAD", "--pathspec-from-file=-",
            "--pathspec-file-nul", data=nul_join(oversized))
    paths = working_changes(vault) - oversized
    if paths:
        git(vault, "--literal-pathspecs", "add", "-A", "--pathspec-from-file=-", "--pathspec-file-nul",
            data=nul_join(paths))


def report(name, *args, **kwargs):
    if progress:
        getattr(progress, name)(PART, *args, **kwargs)


def report_files(vault, direction, *diff_args):
    if progress:
        out = git(vault, "-c", "core.quotePath=false", "diff", "--name-status", *diff_args, check=False, probe=True)
        progress.files(PART, direction, progress.parse_name_status(os.fsdecode(out.stdout)))


def git_progress(vault, *args, timeout=None):
    # fetch/push with a percentage in the dropdown; without a helper silent as before.
    # timeout = seconds without output (stalled connection), not for the whole transfer: a large push may
    # take minutes. Only the silent fallback has to limit the whole call.
    if not progress:
        return git(vault, *args, "-q", timeout=timeout)
    cmd = ["git", "-C", os.fsdecode(vault), *(os.fsdecode(a) for a in args[:1]), "--progress",
           *(os.fsdecode(a) for a in args[1:])]
    code = progress.run(PART, cmd, timeout=timeout)
    if code:
        raise subprocess.CalledProcessError(code, cmd)


def git_path(vault, name):
    return Path(os.fsdecode(git(vault, "rev-parse", "--path-format=absolute", "--git-path", name).stdout.rstrip(b"\n")))


def sync(vault):
    for operation in ("MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "rebase-apply", "rebase-merge", "sequencer"):
        if git_path(vault, operation).exists():
            raise SyncError("Finish the Git operation that is still running in the folder")

    branch = git(vault, "symbolic-ref", "--quiet", "--short", "HEAD", check=False, probe=True).stdout.strip()
    local_branch = os.fsdecode(branch)
    remote = git(vault, "config", "--get", f"branch.{local_branch}.remote", check=False).stdout.strip()
    ref = git(vault, "config", "--get", f"branch.{local_branch}.merge", check=False).stdout.strip()
    if not branch or not remote or remote == b"." or not ref.startswith(b"refs/heads/"):
        raise SyncError("Set a remote tracking branch for the folder")

    report("step", 1, "Checking changes")
    oversized = oversized_files(vault, changed_paths(vault))
    report("step", 2, "Committing")
    stage_changes(vault, oversized)
    # Check the actual staged blobs too, in case a file changed while being staged.
    newly_oversized = staged_oversized(vault)
    if newly_oversized:
        oversized.update(newly_oversized)
        stage_changes(vault, oversized)
        if staged_oversized(vault):
            raise SyncError("Attachments changed during staging. Sync again after saving them")
    staged = git(vault, "diff", "--cached", "--quiet", check=False).returncode
    if staged == 1:
        git(vault, "commit", "-q", "-m", f"Sync from {socket.gethostname()}")
    elif staged:
        raise SyncError("Could not read the staged vault changes")

    # Fetch exactly the configured upstream branch. Do not overwrite ignored local
    # attachments if the other computer has since added a file at the same path.
    report("step", 3, "Fetching")
    git_progress(vault, "fetch", "--no-tags", "--", remote, ref, timeout=60)
    # What goes up and what comes down (each since the common base)
    report_files(vault, "up", "FETCH_HEAD...HEAD")
    report_files(vault, "down", "HEAD...FETCH_HEAD")
    objects = git(vault, "rev-list", "--objects", "--no-object-names", "FETCH_HEAD..HEAD").stdout
    if oversized_blobs(vault, objects):
        raise SyncError("History already has an unpushed file over 100 MiB")
    report("step", 4, "Merging")
    merge = git(vault, "merge", "-q", "--ff", "--no-edit", "--no-autostash", "--no-overwrite-ignore", "FETCH_HEAD", check=False)
    if merge.returncode:
        sys.stderr.buffer.write(merge.stdout)
        if git_path(vault, "MERGE_HEAD").exists():
            git(vault, "merge", "--abort")
        raise SyncError("Merge blocked. Local changes were kept")

    # Append to the fetched .gitignore so PCs that add different large files
    # before syncing do not create competing edits to the same lines.
    if add_ignore_rules(vault, oversized - ignored_paths(vault, oversized)):
        git(vault, "add", "--", ".gitignore")
        if staged_oversized(vault):
            raise SyncError("Check the staged changes before syncing again")
        git(vault, "commit", "-q", "-m", "Ignore files over 100 MiB")
    if git(vault, "rev-list", "--count", "FETCH_HEAD..HEAD").stdout.strip() != b"0":
        report("step", 5, "Pushing")
        git_progress(vault, "push", "--", remote, b"HEAD:" + ref, timeout=60)

    suffix = f" ({len(oversized)} large file(s) kept locally)" if oversized else ""
    return "Synced" + suffix


def pending(vault):
    """Pending changes without network: changed files (minus oversized ones) plus unpushed commits."""
    paths = changed_paths(vault)
    oversized = oversized_files(vault, paths)
    counted = paths - ignored_paths(vault, oversized) - {path for path in oversized if b"\n" in path}
    ahead = git(vault, "rev-list", "--count", "@{upstream}..HEAD", check=False, probe=True)
    unpushed = int(ahead.stdout) if ahead.returncode == 0 else 0
    status = git(vault, "-c", "core.quotePath=false", "status", "--porcelain", "-z", check=False, probe=True)
    files = []
    for entry in status.stdout.split(b"\0"):
        if len(entry) > 3 and len(files) < 8:
            code = entry[:2].decode(errors="replace")
            kind = "+" if "?" in code or "A" in code else "-" if "D" in code else "~"
            files.append({"k": kind, "p": os.fsdecode(entry[3:])})
    return {"pending": len(counted) + unpushed, "changed": len(counted), "unpushed": unpushed, "files": files}


def main():
    global PART
    parser = argparse.ArgumentParser()
    parser.add_argument("--path", required=True)
    parser.add_argument("--id", default="git")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    PART = args.id
    try:
        vault = repo_path(args.path)
        if args.check:
            print(json.dumps(pending(vault)))
            return 0
        report("start", 5)
        result = sync(vault)
        report("done", "ok", result)
        print(result)
        return 0
    except (OSError, SyncError, subprocess.SubprocessError) as error:
        if args.check:
            print(json.dumps({"pending": 0, "state": "error", "message": str(error)}))
        else:
            message = error if isinstance(error, SyncError) else "Sync failed, see the journal of the sync unit"
            print(error, file=sys.stderr)
            print(message)
            report("done", "error", str(message))
        return 1


if __name__ == "__main__":
    sys.exit(main())

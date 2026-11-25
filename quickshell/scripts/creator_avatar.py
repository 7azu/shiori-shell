#!/usr/bin/env python3
# Profile picture of the YouTube channel of a video, for the spinning cover in the audio dropdown
# (services/AudioState.qml). Prints the path to the cached image, otherwise nothing.
#   creator_avatar.py <youtube-url>
# 1. oEmbed (official, fast) -> channel URL
# 2. yt-dlp with the Zen cookies -> channel profile picture (fetching the video page directly
#    often fails over VPN with "429 Too Many Requests")
# Cache per channel in ~/.cache/quickshell/creator-avatars, so only one network call per channel.

import hashlib
import json
import os
import re
import subprocess
import sys
import urllib.parse
import urllib.request

CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "quickshell", "creator-avatars")
UA = "Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0"
COOKIES = os.path.expanduser("~/.config/quickshell/scripts/zen_cookies.sh")


def fetch(url, timeout=8):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def channel_url(video_url):
    data = json.loads(fetch("https://www.youtube.com/oembed?format=json&url=" + urllib.parse.quote(video_url, safe="")))
    return data.get("author_url") or ""


def avatar_url(channel):
    env = dict(os.environ)
    env["PATH"] = env.get("PATH", "") + ":" + ":".join(os.path.expanduser(p) for p in ("~/.cargo/bin", "~/.deno/bin", "~/.local/bin", "/usr/local/bin"))
    args = ["yt-dlp", "--flat-playlist", "-J", "--playlist-items", "0", "--no-warnings"]
    try:
        spec = subprocess.run([COOKIES], capture_output=True, text=True, timeout=10).stdout.strip()
        if spec:
            args += ["--cookies-from-browser", spec]
    except (OSError, subprocess.SubprocessError):
        pass
    out = subprocess.run(args + [channel], capture_output=True, text=True, timeout=60, env=env).stdout
    thumbs = json.loads(out).get("thumbnails") or []
    for t in thumbs:
        if t.get("id") == "avatar_uncropped" and t.get("url"):
            return t["url"]
    return ""


def main():
    if len(sys.argv) < 2:
        return
    video = sys.argv[1]
    channel = channel_url(video)
    if not channel:
        return
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, "yt-" + hashlib.sha1(channel.encode()).hexdigest()[:16] + ".jpg")
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        url = avatar_url(channel)
        if not url:
            return
        # Request the big variant (=s900 instead of the default size), 240 px is enough for the cover
        url = re.sub(r"=s\d+", "=s240", url)
        data = fetch(url, timeout=15)
        tmp = path + ".tmp"
        with open(tmp, "wb") as f:
            f.write(data)
        os.replace(tmp, path)
    print(path)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # network gone, rate limit ... -> no image, the website icon stays
        print(f"creator_avatar: {e}", file=sys.stderr)

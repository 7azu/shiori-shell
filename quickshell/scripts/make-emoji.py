#!/usr/bin/env python3
"""Builds resources/emoji/emoji.json, the list behind the launcher's emoji search (":" in the search).

  make-emoji.py <emoji-test.txt> <cldr-annotations-en.xml> [output]

Not run by the shell: only when the list should follow a newer Unicode version. The two inputs:
- https://unicode.org/Public/emoji/latest/emoji-test.txt        (which emoji exist, in keyboard order)
- https://raw.githubusercontent.com/unicode-org/cldr/main/common/annotations/en.xml   (names and keywords)
Both are data of the Unicode Consortium (license: THIRD_PARTY.md).

Output: {"version": "16.0", "groups": ["Smileys & Emotion", ...],
         "emoji": [["😀", "grinning face", "cheerful cheery happy laugh nice smile", 0], ...]}
Each entry: the emoji, its name, further search words, index of its group. Skin tone variants are left
out (five extra tiles per person and hand), and so is everything newer than MAX_VERSION, so the list also
fits an emoji font that is a year or two old.
"""

import json
import os
import re
import sys
import xml.etree.ElementTree as ET

MAX_VERSION = 16.0
# Parts other emoji are built from (skin tones, hair), not for typing
SKIP_GROUPS = {"Component"}
LINE = re.compile(r"^([0-9A-F ]+?)\s*;\s*fully-qualified\s*#\s*(\S+)\s+E(\d+\.\d+)\s+(.*)$")


def plain(text):
    """Without the variation selector: CLDR writes its keys that way."""
    return text.replace("️", "")


def annotations(path):
    names, words = {}, {}
    for node in ET.parse(path).getroot().iter("annotation"):
        key = plain(node.get("cp") or "")
        text = (node.text or "").strip()
        if node.get("type") == "tts":
            names[key] = text
        else:
            words[key] = [w.strip().lower() for w in text.split("|") if w.strip()]
    return names, words


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    here = os.path.dirname(os.path.abspath(__file__))
    out = sys.argv[3] if len(sys.argv) > 3 else os.path.join(here, "..", "resources", "emoji", "emoji.json")
    names, words = annotations(sys.argv[2])
    groups, entries, group = [], [], None
    with open(sys.argv[1], encoding="utf-8") as fh:
        for line in fh:
            if line.startswith("# group:"):
                group = line.split(":", 1)[1].strip()
                if group not in SKIP_GROUPS:
                    groups.append(group)
                continue
            found = LINE.match(line)
            if not found or group in SKIP_GROUPS:
                continue
            emoji, version, test_name = found.group(2), float(found.group(3)), found.group(4)
            if version > MAX_VERSION or "skin tone" in test_name:
                continue
            key = plain(emoji)
            name = (names.get(key) or test_name).lower()
            # Words that the name already has add nothing to the search
            in_name = set(re.split(r"[^a-z0-9]+", name))
            extra = [w for w in words.get(key, []) if w not in in_name and w != name]
            entries.append([emoji, name, " ".join(dict.fromkeys(extra)), groups.index(group)])
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as fh:
        json.dump({"version": str(MAX_VERSION), "groups": groups, "emoji": entries}, fh, ensure_ascii=False,
                  separators=(",", ":"))
        fh.write("\n")
    print(f"{len(entries)} emoji in {len(groups)} groups -> {os.path.normpath(out)}")


if __name__ == "__main__":
    main()

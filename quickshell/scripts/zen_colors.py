#!/usr/bin/env python3
"""Bring Zen to the new palette already at the start of the wallpaper wave.

wal writes colors-zen.txt (background of the transparent Zen mod) and zen-youtube.css only after the
wave; zen-live (~/.config/wal/zen-live/zen-live.cfg) reads both every 200 ms and fades itself with a
CSS transition. Here the same files are made in advance from the palette (16 colors as a JSON list in argv[1]),
rendered like wal (str.format, background = color0, foreground/cursor = color15). wal later writes
the same content; then zen-live changes nothing anymore. Plus zen-sites.css for more sites
(~/.config/wal/zen/zen-sites.py build).
"""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

HEX = re.compile(r'#[0-9a-fA-F]{6}')


def write_atomic(path, text):
    # zen-live reads by path: never show a half-written file
    tmp = path.with_name(path.name + '.qs-tmp')
    tmp.write_text(text)
    os.replace(tmp, path)


def main():
    palette = json.loads(sys.argv[1])
    if not (isinstance(palette, list) and len(palette) == 16
            and all(isinstance(c, str) and HEX.fullmatch(c) for c in palette)):
        return
    cache = Path(os.environ.get('XDG_CACHE_HOME', str(Path.home() / '.cache'))) / 'wal'
    config = Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config')))
    if not cache.is_dir():
        return
    values = {f'color{i}': c for i, c in enumerate(palette)}
    values.update(background=palette[0], foreground=palette[15], cursor=palette[15])
    write_atomic(cache / 'colors-zen.txt', palette[0] + '\n')
    template = config / 'wal/templates/zen-youtube.css'
    if template.is_file():
        try:
            write_atomic(cache / 'zen-youtube.css', template.read_text().format(**values))
        except (KeyError, IndexError, ValueError) as error:
            print(f'zen_colors: {error}', file=sys.stderr)
    # More sites (GitHub, Reddit ...): own generator with the site data read in
    sites = config / 'wal/zen/zen-sites.py'
    if sites.is_file():
        subprocess.run([sys.executable, '-I', '-B', str(sites), 'build', json.dumps(palette)], check=False)


if __name__ == '__main__':
    main()

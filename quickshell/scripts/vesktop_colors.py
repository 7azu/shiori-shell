#!/usr/bin/env python3
"""Follow Quickshell's palette through Vencord QuickCSS (50 ms file debounce).
One target message starts a native CSS animation; no per-frame stylesheet reloads.
Keeps user QuickCSS outside the managed block and retains the watched inode.
"""
import os
import re
import sys
import json
import time
from pathlib import Path

BEGIN = '/* BEGIN QUICKSHELL WAL FADE */'
END = '/* END QUICKSHELL WAL FADE */'
HEX = re.compile(r'#[0-9a-fA-F]{6}')
ROLES = {'background': 0, 'foreground': 15, 'color8': 8, 'color5': 5, 'color4': 4}


def render(colors, template, start=None, duration=0):
    start = start or colors
    values = {key: f'var(--qs-wal-{key})' for key in ROLES}
    css = template.format(**values)
    css = css[css.index(':root {'):].replace(':root {', ':root, body {')
    css = re.sub(r'(--[\w-]+: [^;]+);', r'\1 !important;', css)
    properties = '\n'.join(
        f'@property --qs-wal-{key} {{ syntax: "<color>"; inherits: true; initial-value: {"#ffffff" if key == "foreground" else "#000000"}; }}'
        for key in ROLES)
    def assignments(palette):
        return '\n'.join(f'  --qs-wal-{key}: {palette[index]};' for key, index in ROLES.items())
    # One explicit from/to animation: no stylesheet changes during the fade.
    name = f'qs-wal-{time.monotonic_ns()}'
    animation = (f'@keyframes {name} {{ from {{ {assignments(start)} }} to {{ {assignments(colors)} }} }}\n'
                 if duration else '')
    rule = f'animation: {name} {duration}ms cubic-bezier(0.455, 0.03, 0.515, 0.955);' if duration else ''
    return f'{BEGIN}\n{properties}\n{animation}:root {{\n{assignments(colors)}\n  {rule}\n}}\n{css}\n{END}'


def write_palette(path, colors, template, start=None, duration=0):
    original = path.read_text() if path.exists() else ''
    block = render(colors, template, start, duration)
    pattern = re.compile(re.escape(BEGIN) + r'.*?' + re.escape(END), re.S)
    if BEGIN in original:
        if END not in original:
            raise ValueError('Incomplete managed QuickCSS block')
        result = pattern.sub(lambda _: block, original, count=1)
    else:
        result = original.rstrip() + '\n\n' + block + '\n'
    if result != original:
        # Vencord watches this inode: replacing the file would detach its watcher.
        with path.open('w') as stream:
            stream.write(result)


def main():
    root = Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config')))
    path = root / 'vesktop/settings/quickCss.css'
    template_path = root / 'wal/templates/colors-discord.css'
    if not path.parent.is_dir() or not template_path.is_file():
        return
    template = template_path.read_text()
    last_target = None
    for line in sys.stdin:
        try:
            request = json.loads(line)
            colors, start = request['to'], request['from']
            if not all(isinstance(palette, list) and len(palette) == 16
                       and all(isinstance(c, str) and HEX.fullmatch(c) for c in palette)
                       for palette in (colors, start)):
                continue
            duration = max(0, min(10000, int(request['duration'])))
            if colors == last_target:
                continue
            write_palette(path, colors, template, start, duration)
            last_target = colors
        except (OSError, ValueError, KeyError, TypeError) as error:
            print(f'Vesktop palette: {error}', file=sys.stderr)


if __name__ == '__main__':
    main()

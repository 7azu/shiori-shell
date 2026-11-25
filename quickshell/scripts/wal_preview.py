#!/usr/bin/env python3
"""Compute the pywal palette of a wallpaper without applying it (for services/WallpaperTransition.qml).

  wal_preview.py <wallpaper>   -> JSON {"color0": "#...", ..., "color15": "#..."}

Why: the shell's colors should fade in sync with the ink transition. wal itself only runs
later (apply-wallpaper.sh); pywal.colors.get uses the same cache and the same defaults as
`wal -n -i <image>`, so the palette is exactly the one wal sets afterwards. Nothing is colored here.
The image for the colors is chosen by the same rule as in apply-wallpaper.sh (wallpaper-theme-image.sh).
"""
import json
import logging
import os
import subprocess
import sys

logging.disable(logging.CRITICAL)  # otherwise pywal writes progress to stderr


def main():
    helper = os.path.expanduser('~/.config/hypr/scripts/wallpaper-theme-image.sh')
    image = subprocess.run([helper, sys.argv[1]], capture_output=True, text=True, check=True).stdout.strip()
    import pywal.colors
    colors = pywal.colors.get(image)['colors']
    print(json.dumps({f'color{i}': colors[f'color{i}'] for i in range(16)}))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:  # the transition then runs without precomputed colors
        print(f'No palette preview: {error}', file=sys.stderr)
        sys.exit(1)

#!/usr/bin/env python3
"""Local wallpapers plus downloaded Steam Workshop video projects; no file copies."""
import json
import re
import sys
from pathlib import Path
from urllib.parse import quote

VIDEO = {'.mp4', '.webm', '.mkv', '.mov', '.m4v'}
IMAGE = {'.png', '.jpg', '.jpeg', '.gif'}

def url(path):
    return 'file://' + quote(str(path))

def entries(local, steam_root=None):
    local = Path(local)
    result = []
    if local.is_dir():
        for p in sorted(local.iterdir(), key=lambda p: p.name.casefold()):
            ext = p.suffix.lower()
            if not p.name.startswith('.') and p.is_file() and ext in VIDEO | IMAGE:
                result.append(dict(key=p.name, name=p.name, url=url(p),
                                   animated=ext in VIDEO or ext == '.gif', video=ext in VIDEO,
                                   workshop=False, thumbSource=str(p)))
    steam = Path(steam_root) if steam_root else Path.home() / '.local/share/Steam'
    libraries = [steam]
    try:
        for path in re.findall(r'"path"\s+"([^"]+)"', (steam / 'steamapps/libraryfolders.vdf').read_text()):
            library = Path(path.replace('\\\\', '\\'))
            if library not in libraries:
                libraries.append(library)
    except OSError:
        pass
    seen = set()
    for library in libraries:
        root = library / 'steamapps/workshop/content/431960'
        if not root.is_dir():
            continue
        for folder in sorted(root.iterdir()):
            try:
                data = json.loads((folder / 'project.json').read_text())
                if not isinstance(data, dict) or str(data.get('type', '')).lower() not in {'video', 'scene'}:
                    continue
                scene = str(data['type']).lower() == 'scene'
                video = (folder / ('project.json' if scene else data['file'])).resolve()
                if not video.is_relative_to(folder.resolve()) or not video.is_file():
                    continue
                if scene:
                    if not (folder / 'scene.pkg').is_file() and not (folder / 'scene.json').is_file():
                        continue
                elif video.suffix.lower() not in VIDEO:
                    continue
                if video in seen:
                    continue
                seen.add(video)
                preview = (folder / str(data.get('preview', 'preview.jpg'))).resolve()
                if not preview.is_relative_to(folder.resolve()) or not preview.is_file() or preview.suffix.lower() not in IMAGE:
                    if scene:
                        continue
                    preview = video
                # The workshop preview is square and often tiny (from 192 px) or a 256-color GIF
                # -> pixelated in the 16:9 tile. Videos give a sharp image themselves, scenes are rendered by
                # wallpaper_thumbs.sh (project.json as the source, preview stays the fallback there).
                # The thumbKey version forces new previews once instead of the old ones from the cache
                # (v4: scene renders with color correction, before e.g. black instead of white).
                result.append(dict(key='workshop:' + str(video), name=str(data.get('title') or folder.name),
                                   url=url(video), animated=True, video=not scene, scene=scene, workshop=True,
                                   thumbKey='v4:workshop:' + str(video), thumbSource=str(video)))
            except (OSError, ValueError, KeyError, TypeError):
                continue  # Downloads that are still incomplete appear on the next refresh.
    return result

if __name__ == '__main__':
    print(json.dumps(entries(sys.argv[1]), ensure_ascii=False))

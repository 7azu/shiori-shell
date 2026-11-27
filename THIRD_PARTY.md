# Third-party parts

shiori-shell itself is licensed under GPL-3.0 (see `LICENSE`). These parts come from other projects and keep
their own licenses. The full texts are in `licenses/`.

| Part | Where | Source | License |
|---|---|---|---|
| Space Grotesk font | `quickshell/resources/fonts/SpaceGrotesk.ttf`, `docs/fonts/SpaceGrotesk.woff2` | github.com/floriankarsten/space-grotesk | SIL OFL 1.1 (`licenses/SpaceGrotesk-OFL.txt`) |
| Fraunces font | `quickshell/resources/fonts/Fraunces.ttf`, `docs/fonts/Fraunces*.woff2` | github.com/undercasetype/Fraunces | SIL OFL 1.1 (`licenses/Fraunces-OFL.txt`) |
| Country flags | `quickshell/resources/flags/*.svg` | github.com/lipis/flag-icons | MIT (`licenses/flag-icons-MIT.txt`) |
| World map data | `quickshell/resources/globe/` (made by `scripts/make-globe-map.py`) | Natural Earth, naturalearthdata.com | Public domain |
| Power menu icons | `quickshell/resources/icons/*.png` | Material Design Icons (pictogrammers.com), rendered from the Nerd Font | Apache 2.0 |
| Default wallpaper | `wallpapers/default.jpg` (installed as `~/Pictures/Wallpaper/shiori-default.jpg`) | Fan art of a character from Neon Genesis Evangelion; the artist's signature is in the image | Included with the artist's permission. Not covered by the GPL-3.0: all rights to the artwork stay with the artist, the character belongs to its rights holders. Do not reuse it outside shiori-shell without asking the artist. |
| Weather symbols | `quickshell/bar/WeatherGlyph.qml` (outlines redrawn from the icon paths) | Lucide, lucide.dev | ISC (`licenses/Lucide-ISC.txt`) |
| system24 Discord theme (pywal edition) | `wal/templates/discord-system24.theme.css` | github.com/refact0r/system24, adapted for pywal | MIT (`licenses/system24-MIT.txt`) |

Not included, only used when installed: adw-gtk3 (GTK theme base), the Steam theme "Minimal Dark" for
Millennium (`wal/steam/patch-theme.py` only patches an installed copy), Nerd Fonts, pywal.

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ███████╗███╗   ██╗██╗   ██╗██╗██████╗  ██████╗ ███╗   ██╗███╗   ███╗███████╗███╗   ██╗████████╗
-- ██╔════╝████╗  ██║██║   ██║██║██╔══██╗██╔═══██╗████╗  ██║████╗ ████║██╔════╝████╗  ██║╚══██╔══╝
-- █████╗  ██╔██╗ ██║██║   ██║██║██████╔╝██║   ██║██╔██╗ ██║██╔████╔██║█████╗  ██╔██╗ ██║   ██║
-- ██╔══╝  ██║╚██╗██║╚██╗ ██╔╝██║██╔══██╗██║   ██║██║╚██╗██║██║╚██╔╝██║██╔══╝  ██║╚██╗██║   ██║
-- ███████╗██║ ╚████║ ╚████╔╝ ██║██║  ██║╚██████╔╝██║ ╚████║██║ ╚═╝ ██║███████╗██║ ╚████║   ██║
-- ╚══════╝╚═╝  ╚═══╝  ╚═══╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═══╝   ╚═╝
--
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--   ~/.config/hypr/modules/environment.lua
--   Environment variables: cursor, paths, Qt theme, input method, ssh-agent
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ┌────────────────────────────────────────────────────────────┐
-- │  CURSOR                                                    │
-- └────────────────────────────────────────────────────────────┘
-- "Kitty": Kuro Kitty (Windows pack, full set of 15 shapes), converted from .ani/.cur with
-- scripts/ani2xcursor.py into ~/.local/share/icons/Kitty (originals in Kitty/src/). The grey fur
-- follows the pywal accent: wal/cursor/gen-cursor.sh with Kitty/gen-cursor.conf (tint=grey,
-- text_cursor=no). Not part of the dotfiles. Native size: 32 only (a downscaled 28 px version via
-- gen-cursor.conf "size=" was tried and looked bad for the pixel art).
-- Previous: "BongoCat" (Pixel Bongo Cat by Sweezy Cursors, ~/.local/share/icons/BongoCat,
-- default + pointer + text only, tinted with the pywal accent by wal/cursor/gen-cursor.sh).
-- No hyprcursor version: Hyprland falls back to the Xcursor theme.
hl.env("XCURSOR_THEME",   "Kitty")
hl.env("XCURSOR_SIZE",    "32")
hl.env("HYPRCURSOR_SIZE", "32")

-- ┌────────────────────────────────────────────────────────────┐
-- │  PATHS                                                     │
-- └────────────────────────────────────────────────────────────┘
-- prepend ~/.local/share to XDG_DATA_DIRS (own .desktop files, icons)
local data_dirs = os.getenv("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"
hl.env("XDG_DATA_DIRS", os.getenv("HOME") .. "/.local/share:" .. data_dirs)

-- ┌────────────────────────────────────────────────────────────┐
-- │  QT THEME                                                  │
-- └────────────────────────────────────────────────────────────┘
-- Qt apps use the wal colors via qt6ct (scheme from ~/.config/wal/qt/gen-qt6ct-colors.sh);
-- Quickshell is excluded there via ignored_applications
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")

-- ┌────────────────────────────────────────────────────────────┐
-- │  INPUT METHOD (FCITX5 / JAPANESE)                          │
-- └────────────────────────────────────────────────────────────┘
hl.env("QT_IM_MODULE",  "fcitx")
hl.env("XMODIFIERS",    "@im=fcitx")
hl.env("SDL_IM_MODULE", "fcitx")
-- GLFW apps (e.g. kitty) only know ibus; fcitx5 speaks the ibus protocol too
hl.env("GLFW_IM_MODULE", "ibus")

-- ┌────────────────────────────────────────────────────────────┐
-- │  SSH AGENT                                                 │
-- └────────────────────────────────────────────────────────────┘
-- systemd socket, started in autostart.lua: keeps the SSH key after it is unlocked at login,
-- so git/ssh (dotfiles sync, push) don't ask for the passphrase every time
local runtime = os.getenv("XDG_RUNTIME_DIR") or ("/run/user/" .. (os.getenv("UID") or "1000"))
hl.env("SSH_AUTH_SOCK", runtime .. "/ssh-agent.socket")
-- passphrase prompt as a window (pinentry-qt) instead of in the terminal
hl.env("SSH_ASKPASS", os.getenv("HOME") .. "/.config/hypr/scripts/ssh-askpass")

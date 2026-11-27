-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
--           █████╗ ██╗   ██╗████████╗ ██████╗ ███████╗████████╗ █████╗ ██████╗ ████████╗
--          ██╔══██╗██║   ██║╚══██╔══╝██╔═══██╗██╔════╝╚══██╔══╝██╔══██╗██╔══██╗╚══██╔══╝
--          ███████║██║   ██║   ██║   ██║   ██║███████╗   ██║   ███████║██████╔╝   ██║
--          ██╔══██║██║   ██║   ██║   ██║   ██║╚════██║   ██║   ██╔══██║██╔══██╗   ██║
--          ██║  ██║╚██████╔╝   ██║   ╚██████╔╝███████║   ██║   ██║  ██║██║  ██║   ██║
--          ╚═╝  ╚═╝ ╚═════╝    ╚═╝    ╚═════╝ ╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝
--
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--   ~/.config/hypr/modules/autostart.lua
--   Programs started with Hyprland (does not run on `hyprctl reload`)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

local home = os.getenv("HOME")

hl.on("hyprland.start", function()
  -- ┌────────────────────────────────────────────────────────────┐
  -- │  DESKTOP                                                   │
  -- └────────────────────────────────────────────────────────────┘
  -- wallpaper, colors, terminal layout, fcitx5, MPD
  hl.exec_cmd(home .. "/.config/hypr/scripts/start.sh")
  hl.exec_cmd(home .. "/.config/hypr/scripts/vpn-state.sh restore")
  -- via wrapper: limits jemalloc arenas (Quickshell RAM) and puts the bar monitor first for Qt
  -- (monitor-order.sh: Qt times all animations by the first monitor, otherwise 75 Hz on the 240 Hz screen)
  hl.exec_cmd(home .. "/.config/hypr/scripts/quickshell.sh -n")


  -- clipboard history (the script lives with Quickshell)
  local clip = home .. "/.config/quickshell/scripts/clip_store.sh"
  hl.exec_cmd("wl-paste --type text --watch " .. clip .. " text")
  hl.exec_cmd("wl-paste --type image --watch " .. clip .. " image")

  -- ┌────────────────────────────────────────────────────────────┐
  -- │  SECURITY                                                  │
  -- └────────────────────────────────────────────────────────────┘
  -- while you are away: darker, lock, monitors off, standby (steps in the shell settings, "idle";
  -- scripts/idle.sh writes hypridle's file from them). Started directly instead of via a systemd unit,
  -- because graphical-session.target isn't active here and the unit would never start.
  hl.exec_cmd(home .. "/.config/hypr/scripts/idle.sh")

  -- Start the SSH agent without opening a passphrase dialog.
  hl.exec_cmd("systemctl --user start ssh-agent.socket")
  -- Own apps at login: in ~/.config/shiori-shell/hypr.lua (hl.on("hyprland.start", ...))
end)

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
--                             ██╗███╗   ██╗██████╗ ██╗   ██╗████████╗
--                             ██║████╗  ██║██╔══██╗██║   ██║╚══██╔══╝
--                             ██║██╔██╗ ██║██████╔╝██║   ██║   ██║
--                             ██║██║╚██╗██║██╔═══╝ ██║   ██║   ██║
--                             ██║██║ ╚████║██║     ╚██████╔╝   ██║
--                             ╚═╝╚═╝  ╚═══╝╚═╝      ╚═════╝    ╚═╝
--
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--   ~/.config/hypr/modules/input.lua
--   Keyboard, mouse and drawing tablet
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ┌────────────────────────────────────────────────────────────┐
-- │  KEYBOARD & MOUSE (GLOBAL)                                 │
-- └────────────────────────────────────────────────────────────┘
-- Neutral defaults. Put your own layout and mouse settings into ~/.config/shiori-shell/hypr.lua
-- (loaded last, so it overrides these), for example:
--   hl.config({ input = { kb_layout = "de", kb_options = "caps:escape", sensitivity = 0.3 } })
hl.config({
  input = {
    kb_layout    = "us",
    follow_mouse = 1,
  },
})

-- ┌────────────────────────────────────────────────────────────┐
-- │  PER DEVICE                                                │
-- └────────────────────────────────────────────────────────────┘
-- Also best kept in ~/.config/shiori-shell/hypr.lua; names come from `hyprctl devices`.
-- Devices that aren't plugged in are simply ignored. Examples:
--   hl.device({ name = "my-mouse", sensitivity = -0.5 })
--   hl.device({ name = "my-tablet-pen", output = "HDMI-A-1" }) -- map a drawing tablet to one screen

-- OpenTabletDriver (Artist Mode) sizes its virtual pen device from the monitor layout when it
-- starts. If a monitor (e.g. the tablet) comes up later, the device stays too small and the pen
-- is dead everywhere. So restart OTD whenever the layout changes (only where OTD is installed
-- and enabled). The delay lets XWayland catch up.
local function restart_otd()
  hl.exec_cmd("sh -c 'systemctl --user -q is-enabled opentabletdriver.service || exit 0; "
    .. "sleep 3; systemctl --user restart opentabletdriver.service'")
end
hl.on("monitor.added", restart_otd)
hl.on("monitor.removed", restart_otd)

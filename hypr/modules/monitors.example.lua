-- Monitors of this machine. Copy to modules/monitors.lua (ignored by git, so every machine keeps its own).
-- Names and modes: hyprctl monitors all
--
-- transform: 0 normal, 1 = 90°, 2 = 180°, 3 = 270° (portrait)
hl.monitor({ output = "DP-1",     mode = "2560x1440@144", position = "0x0",    scale = 1, transform = 0 })
hl.monitor({ output = "HDMI-A-1", mode = "1920x1080@60",  position = "2560x0", scale = 1, transform = 0 })

-- Optional: fixed workspaces per monitor
-- for ws = 1, 5 do hl.workspace_rule({ workspace = tostring(ws), monitor = "DP-1" }) end
-- for ws = 6, 10 do hl.workspace_rule({ workspace = tostring(ws), monitor = "HDMI-A-1" }) end

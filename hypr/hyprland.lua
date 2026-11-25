-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
--               ██╗  ██╗██╗   ██╗██████╗ ██████╗ ██╗      █████╗ ███╗   ██╗██████╗
--               ██║  ██║╚██╗ ██╔╝██╔══██╗██╔══██╗██║     ██╔══██╗████╗  ██║██╔══██╗
--               ███████║ ╚████╔╝ ██████╔╝██████╔╝██║     ███████║██╔██╗ ██║██║  ██║
--               ██╔══██║  ╚██╔╝  ██╔═══╝ ██╔══██╗██║     ██╔══██║██║╚██╗██║██║  ██║
--               ██║  ██║   ██║   ██║     ██║  ██║███████╗██║  ██║██║ ╚████║██████╔╝
--               ╚═╝  ╚═╝   ╚═╝   ╚═╝     ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═════╝
--
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--   ~/.config/hypr/hyprland.lua
--   Entry point: loads the modules from modules/ in the right order
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- let require() find the modules in modules/
package.path = package.path .. ";" .. os.getenv("HOME") .. "/.config/hypr/modules/?.lua"

require("environment") -- first, so the variables apply to everything below
-- per machine, not in the repo (copy modules/monitors.example.lua); without it every monitor is used
-- with its preferred mode, placed automatically
local monitorsFile = io.open(os.getenv("HOME") .. "/.config/hypr/modules/monitors.lua", "r")
if monitorsFile then
  monitorsFile:close()
  require("monitors") -- errors in the file still show up
else
  hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })
end
require("input")       -- keyboard, mouse, drawing tablet
require("looks")       -- gaps, borders, blur, opacity
require("animations")  -- curves and animations
require("windows")     -- workspace, window and layer rules
require("home")        -- workspace 1: floating terminal stage
require("keybindings") -- keybindings
require("autostart")   -- programs started at login

-- Personal additions that are not part of shiori-shell (rules for your own apps, private add-ons).
-- Loaded last, so they can add to or override everything above.
local userConfig = os.getenv("HOME") .. "/.config/shiori-shell/hypr.lua"
local userFile = io.open(userConfig, "r")
if userFile then
  userFile:close()
  dofile(userConfig)
end

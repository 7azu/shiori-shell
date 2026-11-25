-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
--      ██╗  ██╗███████╗██╗   ██╗██████╗ ██╗███╗   ██╗██████╗ ██╗███╗   ██╗ ██████╗ ███████╗
--      ██║ ██╔╝██╔════╝╚██╗ ██╔╝██╔══██╗██║████╗  ██║██╔══██╗██║████╗  ██║██╔════╝ ██╔════╝
--      █████╔╝ █████╗   ╚████╔╝ ██████╔╝██║██╔██╗ ██║██║  ██║██║██╔██╗ ██║██║  ███╗███████╗
--      ██╔═██╗ ██╔══╝    ╚██╔╝  ██╔══██╗██║██║╚██╗██║██║  ██║██║██║╚██╗██║██║   ██║╚════██║
--      ██║  ██╗███████╗   ██║   ██████╔╝██║██║ ╚████║██████╔╝██║██║ ╚████║╚██████╔╝███████║
--      ╚═╝  ╚═╝╚══════╝   ╚═╝   ╚═════╝ ╚═╝╚═╝  ╚═══╝╚═════╝ ╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚══════╝
--
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--   ~/.config/hypr/modules/keybindings.lua
--   Keybindings: apps, Quickshell, windows, workspaces, media
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- Bindings made with keys.bind can be changed in the settings window (Shortcuts page, or by hand under
-- "keys" in ~/.config/shiori-shell/settings.json); the keys here are the defaults. "MOD" stands for the
-- main modifier, SUPER unless the settings say otherwise. See keys.lua.
local keys = require("keys")

local mainMod = keys.mod

local scripts = os.getenv("HOME") .. "/.config/hypr/scripts/"

-- ┌────────────────────────────────────────────────────────────┐
-- │  APPS & SCRIPTS                                            │
-- └────────────────────────────────────────────────────────────┘
-- Always in the home folder: otherwise kitty takes Hyprland's working directory, which is the folder
-- start-hyprland was run from (e.g. the repo right after install.sh)
keys.bind("terminal",        "MOD + Q",         hl.dsp.exec_cmd("kitty --directory " .. os.getenv("HOME")), "Apps: Open terminal")
keys.bind("files",           "MOD + E",         hl.dsp.exec_cmd(scripts .. "filemanager.sh"), "Apps: Open file manager")
keys.bind("screenshot",      "MOD + S",         hl.dsp.exec_cmd(scripts .. "screenshot.sh"), "Apps: Take screenshot")
-- open in the editor instead of saving directly
keys.bind("screenshot_edit", "MOD + SHIFT + S", hl.dsp.global("quickshell:screenshot_edit"), "Quickshell: Edit screenshot")
keys.bind("neovim",          "MOD + SHIFT + N", hl.dsp.exec_cmd(scripts .. "nvim.sh"), "Apps: Open Neovim")

-- restart Quickshell: kill the old instance, wait, then start exactly one new one
-- (via wrapper: limits jemalloc arenas -> much less RAM, see scripts/quickshell.sh)
keys.bind("restart_shell",   "MOD + SHIFT + Q", hl.dsp.exec_cmd("pkill -x qs; while pgrep -x qs >/dev/null; do sleep 0.1; done; " .. scripts .. "quickshell.sh -n -d"), "Quickshell: Restart Quickshell")

-- ┌────────────────────────────────────────────────────────────┐
-- │  QUICKSHELL                                                │
-- └────────────────────────────────────────────────────────────┘
keys.bind("launcher",      "MOD + SPACE", hl.dsp.global("quickshell:toggle_launcher"), "Quickshell: Open app launcher")
keys.bind("music",         "MOD + M",     hl.dsp.global("quickshell:toggle_music_picker"), "Quickshell: Open music picker")
keys.bind("wallpaper",     "MOD + W",     hl.dsp.global("quickshell:toggle_wallpaper"), "Quickshell: Pick wallpaper")
keys.bind("clipboard",     "MOD + G",     hl.dsp.global("quickshell:toggle_clipboard"), "Quickshell: Open clipboard history")
keys.bind("trash",         "MOD + X",     hl.dsp.global("quickshell:toggle_trash"), "Quickshell: Open trash")
keys.bind("vpn",           "MOD + V",     hl.dsp.global("quickshell:toggle_vpn"), "Quickshell: Open VPN picker")
keys.bind("notifications", "MOD + N",     hl.dsp.global("quickshell:toggle_notifications"), "Quickshell: Open notification center")
keys.bind("calendar",      "MOD + K",     hl.dsp.global("quickshell:toggle_calendar"), "Quickshell: Open calendar")
keys.bind("tasks",         "MOD + T",     hl.dsp.global("quickshell:toggle_task_manager"), "Quickshell: Open task manager")
keys.bind("language",      "MOD + J",     hl.dsp.global("quickshell:toggle_language"), "Quickshell: Open language picker")
keys.bind("power",         "MOD + P",     hl.dsp.global("quickshell:toggle_power_menu"), "Quickshell: Open power menu")
keys.bind("settings",      "MOD + comma", hl.dsp.global("quickshell:toggle_settings"), "Quickshell: Open settings")
-- lock screen directly (MOD + L is focus right); lock.sh itself makes sure only one runs (flock)
keys.bind("lock",          "MOD + CTRL + L", hl.dsp.exec_cmd(scripts .. "lock.sh"), "Quickshell: Lock screen")

-- ┌────────────────────────────────────────────────────────────┐
-- │  WINDOWS                                                   │
-- └────────────────────────────────────────────────────────────┘
keys.bind("close",       "MOD + C",         hl.dsp.window.close(), "Windows: Close window")
keys.bind("float",       "MOD + B",         hl.dsp.window.float({ action = "toggle" }), "Windows: Toggle floating window")
-- workspace 1: floating terminal stage <-> tiling (modules/home.lua)
keys.bind("home_layout", "MOD + D",         require("home").toggle, "Workspaces: Toggle home workspace layout")
-- MOD + F: real fullscreen, MOD + SHIFT + F: maximized (bar and gaps stay visible)
keys.bind("fullscreen",  "MOD + F",         hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }), "Windows: Toggle fullscreen")
keys.bind("maximize",    "MOD + SHIFT + F", hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }), "Windows: Toggle maximized window")
-- MOD + P is the power menu (see above)
keys.bind("pseudo",      "MOD + SHIFT + P", hl.dsp.window.pseudo(), "Windows: Toggle pseudo tiling")

-- The bindings from here on are groups and special keys. They follow the main modifier but are not
-- changed one by one; keys.note only lists them for the settings page.

-- Focus (vim keys) and move windows (SHIFT + vim keys).
-- MOD + K is the calendar, MOD + J the language tool (see above);
-- focus up/down works via MOD + arrow up/down
local vim = { H = "l", J = "d", K = "u", L = "r" }
local directions = { l = "left", d = "down", u = "up", r = "right" }
for key, dir in pairs(vim) do
  if key ~= "K" and key ~= "J" then
    hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ direction = dir }), { description = "Windows: Focus " .. directions[dir] })
  end
  hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ direction = dir }), { description = "Windows: Move window " .. directions[dir] })
end
keys.note("MOD + H / L", "Windows: Focus left or right")
keys.note("MOD + SHIFT + H J K L", "Windows: Move window")

-- focus with the arrow keys too
local arrows = { left = "l", down = "d", up = "u", right = "r" }
for key, dir in pairs(arrows) do
  hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ direction = dir }), { description = "Windows: Focus " .. directions[dir] })
end
keys.note("MOD + Arrows", "Windows: Focus in a direction")

-- mouse: MOD + left click moves, MOD + right click resizes
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true, description = "Windows: Drag window" })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true, description = "Windows: Resize window" })
keys.note("MOD + Left Click", "Windows: Drag window")
keys.note("MOD + Right Click", "Windows: Resize window")

-- ┌────────────────────────────────────────────────────────────┐
-- │  WORKSPACES 1-10                                           │
-- └────────────────────────────────────────────────────────────┘
-- MOD + number switches, MOD + SHIFT + number moves the active window (key 0 = workspace 10)
for i = 1, 10 do
  local key = tostring(i % 10)
  hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i }), { description = "Workspaces: Switch to workspace " .. i })
  hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }), { description = "Workspaces: Move window to workspace " .. i })
end
keys.note("MOD + 1 … 0", "Workspaces: Switch to workspace 1 to 10")
keys.note("MOD + SHIFT + 1 … 0", "Workspaces: Move window to workspace 1 to 10")

-- ┌────────────────────────────────────────────────────────────┐
-- │  MEDIA & VOLUME                                            │
-- └────────────────────────────────────────────────────────────┘
-- locked: also works on the lock screen; repeating: repeats while held
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true, description = "Media: Next track" })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true, description = "Media: Previous track" })
-- some keyboards send XF86AudioPause instead of Play, so bind both
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true, description = "Media: Play or pause" })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true, description = "Media: Play or pause" })

hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true, description = "Media: Toggle mute" })
-- volume up/down goes through Quickshell: shows the volume slider popup and caps at 100 %
hl.bind("XF86AudioRaiseVolume", hl.dsp.global("quickshell:volume_up"),   { repeating = true, description = "Media: Raise volume" })
hl.bind("XF86AudioLowerVolume", hl.dsp.global("quickshell:volume_down"), { repeating = true, description = "Media: Lower volume" })

-- laptop brightness keys and the calculator key, also through Quickshell (no brightnessctl needed)
hl.bind("XF86MonBrightnessUp",   hl.dsp.global("quickshell:brightness_up"),   { repeating = true, description = "Display: Raise brightness" })
hl.bind("XF86MonBrightnessDown", hl.dsp.global("quickshell:brightness_down"), { repeating = true, description = "Display: Lower brightness" })
hl.bind("XF86Calculator",        hl.dsp.global("quickshell:toggle_calculator"), { description = "Quickshell: Open calculator" })

keys.note("Media keys", "Media: Next, previous, play or pause, mute, volume")
keys.note("Brightness keys", "Display: Raise or lower brightness")
keys.note("Calculator key", "Quickshell: Open calculator")

-- Optional machine-specific keys outside the synced folders.
local localKeys = os.getenv("HOME") .. "/.config/dotfiles-local/hypr-keybindings.lua"
local localFile = io.open(localKeys, "r")
if localFile then
  localFile:close()
  dofile(localKeys)
end

-- The list for the settings window (see keys.lua)
keys.export()

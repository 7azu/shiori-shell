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

local mainMod = "SUPER"

local scripts = os.getenv("HOME") .. "/.config/hypr/scripts/"

-- ┌────────────────────────────────────────────────────────────┐
-- │  APPS & SCRIPTS                                            │
-- └────────────────────────────────────────────────────────────┘
-- Always in the home folder: otherwise kitty takes Hyprland's working directory, which is the folder
-- start-hyprland was run from (e.g. the repo right after install.sh)
hl.bind(mainMod .. " + Q",         hl.dsp.exec_cmd("kitty --directory " .. os.getenv("HOME")), { description = "Apps: Open terminal" })
hl.bind(mainMod .. " + E",         hl.dsp.exec_cmd(scripts .. "filemanager.sh"), { description = "Apps: Open file manager" })
hl.bind(mainMod .. " + S",         hl.dsp.exec_cmd(scripts .. "screenshot.sh"), { description = "Apps: Take screenshot" })
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.global("quickshell:screenshot_edit"), { description = "Quickshell: Edit screenshot" }) -- open in the editor instead of saving directly
hl.bind(mainMod .. " + SHIFT + N", hl.dsp.exec_cmd(scripts .. "nvim.sh"), { description = "Apps: Open Neovim" })

-- restart Quickshell: kill the old instance, wait, then start exactly one new one
-- (via wrapper: limits jemalloc arenas -> much less RAM, see scripts/quickshell.sh)
hl.bind(mainMod .. " + SHIFT + Q", hl.dsp.exec_cmd("pkill -x qs; while pgrep -x qs >/dev/null; do sleep 0.1; done; " .. scripts .. "quickshell.sh -n -d"), { description = "Quickshell: Restart Quickshell" })

-- ┌────────────────────────────────────────────────────────────┐
-- │  QUICKSHELL                                                │
-- └────────────────────────────────────────────────────────────┘
hl.bind(mainMod .. " + SPACE", hl.dsp.global("quickshell:toggle_launcher"), { description = "Quickshell: Open app launcher" })
hl.bind(mainMod .. " + M",     hl.dsp.global("quickshell:toggle_music_picker"), { description = "Quickshell: Open music picker" })
hl.bind(mainMod .. " + W",     hl.dsp.global("quickshell:toggle_wallpaper"), { description = "Quickshell: Pick wallpaper" })
hl.bind(mainMod .. " + G",     hl.dsp.global("quickshell:toggle_clipboard"), { description = "Quickshell: Open clipboard history" })
hl.bind(mainMod .. " + X",     hl.dsp.global("quickshell:toggle_trash"), { description = "Quickshell: Open trash" })
hl.bind(mainMod .. " + V",     hl.dsp.global("quickshell:toggle_vpn"), { description = "Quickshell: Open VPN picker" })
hl.bind(mainMod .. " + N",     hl.dsp.global("quickshell:toggle_notifications"), { description = "Quickshell: Open notification center" })
hl.bind(mainMod .. " + K",     hl.dsp.global("quickshell:toggle_calendar"), { description = "Quickshell: Open calendar" })
hl.bind(mainMod .. " + T",     hl.dsp.global("quickshell:toggle_task_manager"), { description = "Quickshell: Open task manager" })
hl.bind(mainMod .. " + J",     hl.dsp.global("quickshell:toggle_language"), { description = "Quickshell: Open language picker" })
hl.bind(mainMod .. " + P",     hl.dsp.global("quickshell:toggle_power_menu"), { description = "Quickshell: Open power menu" })
hl.bind(mainMod .. " + comma", hl.dsp.global("quickshell:toggle_settings"), { description = "Quickshell: Open settings" })
-- lock screen directly (SUPER + L is focus right); lock.sh itself makes sure only one runs (flock)
hl.bind(mainMod .. " + CTRL + L", hl.dsp.exec_cmd(scripts .. "lock.sh"), { description = "Quickshell: Lock screen" })

-- ┌────────────────────────────────────────────────────────────┐
-- │  WINDOWS                                                   │
-- └────────────────────────────────────────────────────────────┘
hl.bind(mainMod .. " + C",         hl.dsp.window.close(), { description = "Windows: Close window" })
hl.bind(mainMod .. " + B",         hl.dsp.window.float({ action = "toggle" }), { description = "Windows: Toggle floating window" })
-- workspace 1: floating terminal stage <-> tiling (modules/home.lua)
hl.bind(mainMod .. " + D",         require("home").toggle, { description = "Workspaces: Toggle home workspace layout" })
-- SUPER + F: real fullscreen, SUPER + SHIFT + F: maximized (bar and gaps stay visible)
hl.bind(mainMod .. " + F",         hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }), { description = "Windows: Toggle fullscreen" })
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }), { description = "Windows: Toggle maximized window" })
-- SUPER + P is the power menu (see above)
hl.bind(mainMod .. " + SHIFT + P", hl.dsp.window.pseudo(), { description = "Windows: Toggle pseudo tiling" })

-- Focus (vim keys) and move windows (SHIFT + vim keys).
-- SUPER + K is the calendar, SUPER + J the language tool (see above);
-- focus up/down works via SUPER + arrow up/down
local vim = { H = "l", J = "d", K = "u", L = "r" }
local directions = { l = "left", d = "down", u = "up", r = "right" }
for key, dir in pairs(vim) do
  if key ~= "K" and key ~= "J" then
    hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ direction = dir }), { description = "Windows: Focus " .. directions[dir] })
  end
  hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ direction = dir }), { description = "Windows: Move window " .. directions[dir] })
end

-- focus with the arrow keys too
local arrows = { left = "l", down = "d", up = "u", right = "r" }
for key, dir in pairs(arrows) do
  hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ direction = dir }), { description = "Windows: Focus " .. directions[dir] })
end

-- mouse: SUPER + left click moves, SUPER + right click resizes
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true, description = "Windows: Drag window" })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true, description = "Windows: Resize window" })

-- ┌────────────────────────────────────────────────────────────┐
-- │  WORKSPACES 1-10                                           │
-- └────────────────────────────────────────────────────────────┘
-- SUPER + number switches, SUPER + SHIFT + number moves the active window (key 0 = workspace 10)
for i = 1, 10 do
  local key = tostring(i % 10)
  hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i }), { description = "Workspaces: Switch to workspace " .. i })
  hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }), { description = "Workspaces: Move window to workspace " .. i })
end

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

-- Optional machine-specific keys outside the synced folders.
local localKeys = os.getenv("HOME") .. "/.config/dotfiles-local/hypr-keybindings.lua"
local localFile = io.open(localKeys, "r")
if localFile then
  localFile:close()
  dofile(localKeys)
end

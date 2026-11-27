-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
--                   ██╗    ██╗██╗███╗   ██╗██████╗  ██████╗ ██╗    ██╗███████╗
--                   ██║    ██║██║████╗  ██║██╔══██╗██╔═══██╗██║    ██║██╔════╝
--                   ██║ █╗ ██║██║██╔██╗ ██║██║  ██║██║   ██║██║ █╗ ██║███████╗
--                   ██║███╗██║██║██║╚██╗██║██║  ██║██║   ██║██║███╗██║╚════██║
--                   ╚███╔███╔╝██║██║ ╚████║██████╔╝╚██████╔╝╚███╔███╔╝███████║
--                    ╚══╝╚══╝ ╚═╝╚═╝  ╚═══╝╚═════╝  ╚═════╝  ╚══╝╚══╝ ╚══════╝
--
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--   ~/.config/hypr/modules/windows.lua
--   Workspace, window and layer rules
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ┌────────────────────────────────────────────────────────────┐
-- │  WORKSPACES -> MONITORS                                    │
-- └────────────────────────────────────────────────────────────┘
-- Which workspace goes to which monitor depends on the machine: put hl.workspace_rule({ workspace = "1",
-- monitor = "DP-1" }) lines into modules/monitors.lua (not synced, see monitors.example.lua).

-- games (7) without border and rounding
hl.workspace_rule({ workspace = "7",  no_border = true, no_rounding = true })

-- ┌────────────────────────────────────────────────────────────┐
-- │  APPS -> WORKSPACES                                        │
-- └────────────────────────────────────────────────────────────┘
--  field    pattern                  workspace
local placement = {
  { "class", "zen",                   "2" },
  { "title", "tmux_nvim",             "3" },
  { "class", "nvim-reload",           "3" },
  { "class", "vesktop",               "4" },
  { "class", "steam",                 "5" },
  { "class", "ModrinthApp",           "5" },
  { "class", "com.obsproject.Studio", "6" },
  { "class", "org.openrgb.OpenRGB",   "6" },
}
-- keep the handles by class/title so per-machine modules can disable single rules
local placement_rules = {}
for _, p in ipairs(placement) do
  placement_rules[p[2]] = hl.window_rule({ match = { [p[1]] = p[2] }, workspace = p[3] })
end

-- ┌────────────────────────────────────────────────────────────┐
-- │  GAMES                                                     │
-- └────────────────────────────────────────────────────────────┘
-- Steam games and gamescope: fullscreen on workspace 7 without stealing focus
for _, class in ipairs({ "gamescope", "steam_app_\\d+" }) do
  hl.window_rule({ match = { class = class }, fullscreen = true, workspace = "7 silent" })
end
hl.window_rule({ match = { class = "Minecraft\\*.*" },   workspace = "7 silent" })
hl.window_rule({ match = { class = "steam_app_\\d+" }, no_blur = true })

-- ┌────────────────────────────────────────────────────────────┐
-- │  WALLPAPER PICKER: SCENE PREVIEW RENDERS                   │
-- └────────────────────────────────────────────────────────────┘
-- quickshell/scripts/wallpaper_thumbs.sh renders Wallpaper Engine scenes with
-- `linux-wallpaperengine --window … --screenshot` (title "wallpaperengine", no class) for sharp
-- previews. It must stay on a visible workspace (hidden = no
-- frames, no screenshot), so it is just made invisible and never gets focus.
hl.window_rule({
  match            = { class = "^$", title = "^wallpaperengine$" },
  float            = true,
  opacity          = "0.0 override 0.0 override",
  no_initial_focus = true,
  no_focus         = true,
  no_shadow        = true,
  no_blur          = true,
  no_anim          = true,
  border_size      = 0,
})

-- ┌────────────────────────────────────────────────────────────┐
-- │  FLOATING WINDOWS                                          │
-- └────────────────────────────────────────────────────────────┘
--  class                  size
local floating = {
  { "^fzfwindows$",        "1400 880" },  -- Yazi (SUPER + E)
  { "^termfilechooser$",   "1400 880" },  -- Yazi as file picker (browser etc., xdg-desktop-portal-termfilechooser)
  { "^avatarchooser$",     "1400 880" },  -- Yazi for the profile picture (notification center, Quickshell)
  { "^com.gabm.satty$",    "800 600" },   -- screenshot editor
  { "^swayimg$",           "1600 1200" },
  { "^mpv$",               "1600 1200" },
}
for _, f in ipairs(floating) do
  hl.window_rule({ match = { class = f[1] }, float = true, size = f[2], center = true })
end

-- Fit the Yazi file picker (Discord, browser …) to its monitor: the fixed size above sticks out
-- of the portrait monitor. Landscape stays up to 1400x880, portrait gets narrower and taller.
-- Monitor width/height are reported unrotated -> swap them at 90/270 degrees.
hl.on("window.open", function(w)
  if w.class ~= "termfilechooser" or not w.monitor then
    return
  end
  local m = w.monitor
  local mw, mh = m.width / m.scale, m.height / m.scale
  if m.transform % 2 == 1 then
    mw, mh = mh, mw
  end
  local cw = math.floor(math.min(1400, mw * 0.9))
  local ch = math.floor(math.min(mw > mh and 880 or 1300, mh * 0.85))
  -- move takes global coordinates (monitor position + offset)
  hl.dispatch(hl.dsp.window.resize({ window = w, x = cw, y = ch, relative = false }))
  hl.dispatch(hl.dsp.window.move({
    window   = w,
    x        = math.floor(m.x + (mw - cw) / 2),
    y        = math.floor(m.y + (mh - ch) / 2),
    relative = false,
  }))
end)

-- ┌────────────────────────────────────────────────────────────┐
-- │  IMAGE PREVIEW (UEBERZUGPP)                                │
-- └────────────────────────────────────────────────────────────┘
-- Yazi's image preview inside nvim: on Wayland a separate window placed over the preview.
-- Without these rules it gets tiled, steals focus and animates ->
-- Yazi redraws, the preview restarts, the window flickers open and closed.
hl.window_rule({
  match       = { class = "^ueberzugpp_.*" },
  float       = true,
  no_focus    = true,
  no_anim     = true,
  no_shadow   = true,
  no_blur     = true,
  border_size = 0,
  opacity     = "1.0 override 1.0 override",
})

-- ┌────────────────────────────────────────────────────────────┐
-- │  GENERAL                                                   │
-- └────────────────────────────────────────────────────────────┘
-- Zen (and Helium, same look) stay opaque (ignores the alpha channel of the transparency mod)
hl.window_rule({ name = "zen-opacity", match = { class = "^(zen|helium)$" }, opaque = true })

-- apps may not maximize themselves
hl.window_rule({ match = { class = ".*" }, suppress_event = "maximize" })

-- empty, tiled XWayland helper windows (e.g. from Electron/Wine) get no focus
hl.window_rule({
  match = {
    class      = "^$",
    title      = "^$",
    xwayland   = true,
    float      = false,
    fullscreen = false,
    pin        = false,
  },
  no_focus = true,
})

-- ┌────────────────────────────────────────────────────────────┐
-- │  QUICKSHELL LAYERS: BLUR                                   │
-- └────────────────────────────────────────────────────────────┘
-- animation = "fade" instead of no_anim: Hyprland fades out the dimming + blur smoothly
-- after the Quickshell outro (curve/duration: fadeLayersOut in animations.lua)
--  rule name                  namespace                       alpha  animation
local blurred_layers = {
  { "calculator-blur",        "quickshell:calculator",        0.1, "fade" },
  { "settings-blur",          "quickshell:settings",          0.1, "fade" },
  { "polkit-blur",            "quickshell:polkit",            0.1, "fade" },
  { "powermenu-blur",         "quickshell:powermenu",         0.3, "fade" },
  { "pickers-blur",           "quickshell:pickers",           0.1, "fade" },
  { "screenshot-editor-blur", "quickshell:screenshot-editor", 0.1, "fade" },
  { "video-editor-blur",      "quickshell:video-editor",      0.1, "fade" },
}
for _, l in ipairs(blurred_layers) do
  hl.layer_rule({
    name         = l[1],
    match        = { namespace = l[2] },
    blur         = true,
    ignore_alpha = l[3],
    animation    = l[4],
    no_anim      = (l[4] == nil) or nil,
  })
end

-- Cards of the modal windows ("quickshell:<name>-card": settings, calculator, pickers ...) play their
-- own opening and closing (quickshell/common/Evaporate.qml); their backdrop is the blurred namespace
-- above on a lower layer (quickshell/common/ModalBackdrop.qml).
hl.layer_rule({
  name    = "modal-cards",
  match   = { namespace = "quickshell:.*-card" },
  no_anim = true,
})

-- The dark veil of the first idle step (quickshell/windows/IdleDim.qml) fades itself.
hl.layer_rule({
  name    = "idle-dim",
  match   = { namespace = "quickshell:idle-dim" },
  no_anim = true,
})

-- Quickshell owns the backdrop fade and keeps this surface mapped through a workspace switch.
hl.layer_rule({
  name      = "workspaceoverview",
  match     = { namespace = "quickshell:workspaceoverview" },
  no_anim   = true,
})

-- ┌────────────────────────────────────────────────────────────┐
-- │  ANIMATED WALLPAPERS: NO LAYER ANIMATION                   │
-- └────────────────────────────────────────────────────────────┘
-- On a wallpaper switch Quickshell keeps the old video/scene until the new one draws, then closes
-- it. Hyprland draws a closing layer's fade-out *above* everything -> the old wallpaper flashed
-- up again for a moment. Without animation it just disappears behind the new one.
-- The ink-bloom transition overlay freezes the old wallpaper while the new one starts below it:
-- a fade-in would let the new one shine through before the transition begins.
--  rule name                   namespace
local wallpaper_layers = {
  { "animated-wallpaper-noanim", "quickshell:animated-wallpaper" },
  { "wallpaperengine-noanim",    "linux-wallpaperengine" },
  { "ink-bloom-noanim",          "quickshell:ink-bloom" },
  -- still image Quickshell fades over the wallpaper animation when the bar moves to another monitor
  { "anim-move-fade-noanim",     "quickshell:anim-move-fade" },
  -- lock transition on the other monitors (Power menu -> Lock): its first frame is a screenshot of
  -- the monitor, a fade-in would make it flicker instead of starting seamlessly
  { "lock-transition-noanim",    "quickshell:lock-transition" },
  -- video player of the language tool: lies over the open language picker (which dims + blurs) and
  -- morphs out of / back into its panel itself; a layer fade would show both at once
  { "language-video-noanim",     "quickshell:language-video" },
  -- audio visualizer on workspace 1 (Top layer, see quickshell/windows/DesktopVisualizer.qml):
  -- it fades in/out with the sound and when a window reaches into its strip, a layer animation
  -- on top of that would only pop
  { "desktop-visualizer-noanim", "quickshell:desktop-visualizer" },
  -- volume slider popup: slides up from the bottom edge itself (VolumeSliderPopup.qml); the layer
  -- popin/fade on map would sit on top of that slide
  { "volume-slider-noanim",      "quickshell:volume-slider" },
  -- still image over Vesktop/OBS while they switch colors (quickshell/windows/AppColorFade.qml):
  -- its first frame must match the screen exactly, a layer fade-in would flicker
  { "app-color-fade-noanim",     "quickshell:app-color-fade" },
}
for _, l in ipairs(wallpaper_layers) do
  hl.layer_rule({ name = l[1], match = { namespace = l[2] }, no_anim = true })
end

return { placement = placement_rules }

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
--                           ██╗      ██████╗  ██████╗ ██╗  ██╗███████╗
--                           ██║     ██╔═══██╗██╔═══██╗██║ ██╔╝██╔════╝
--                           ██║     ██║   ██║██║   ██║█████╔╝ ███████╗
--                           ██║     ██║   ██║██║   ██║██╔═██╗ ╚════██║
--                           ███████╗╚██████╔╝╚██████╔╝██║  ██╗███████║
--                           ╚══════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚══════╝
--
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--   ~/.config/hypr/modules/looks.lua
--   Look: gaps, borders, shadows, blur, per-app opacity (pywal colors)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ┌────────────────────────────────────────────────────────────┐
-- │  GAPS, BORDERS & DECORATION                                │
-- └────────────────────────────────────────────────────────────┘
-- Gaps, border size and colors, corners, opacity, shadow, blur: set on the "Windows" page of the
-- settings window, see style.lua (pywal colors come from there too). Border + shadow colors fade live
-- on a wallpaper switch: quickshell/services/HyprlandColorFade.qml sends every fade step via hyprctl eval.
local style = require("style")
hl.config(style.config())

-- What the settings page does not change
hl.config({
  general = {
    resize_on_border = false,
    allow_tearing    = false,
  },

  decoration = {
    -- the shadow falls slightly downwards (most visible on the floating stage on workspace 1, home.lua)
    shadow = {
      render_power = 2,
      offset       = "0 8",
    },

    blur   = {
      variant  = "haze",
      vibrancy = 0.1696,
    },
  },

  -- new windows become the master in the master layout
  master = {
    new_status = "master",
  },

  -- lets a restarted Quickshell lock screen take over the session lock if the first one crashes
  -- (fallback in scripts/lock.sh, or run lock.sh again from a TTY)
  misc = {
    allow_session_lock_restore = true,
  },

  -- Color changes of the night light (hyprsunset) apply at once. Hyprland's own fade takes 1.5 s per
  -- change and stalled the compositor for about 0.6 s of that (measured), one direct change about 40 ms.
  render = {
    ctm_animation = 0,
  },
})

-- ┌────────────────────────────────────────────────────────────┐
-- │  PER-APP OPACITY                                           │
-- └────────────────────────────────────────────────────────────┘
-- { match field, pattern, focused, [unfocused] }
-- "override" replaces the global opacity instead of multiplying it. Without its own
-- unfocused value the global inactive_opacity (0.78) applies.
local opacity = {
  { "class", "^(code-oss|[Cc]ode)$",                                                                    0.95 },
  { "class", "^kitty$",                                                                                 0.95, 0.9 },

  -- opaque when focused, only a hint of transparency when unfocused
  { "class", "^(discord|vesktop)$",                                                                     1.0, 0.95 },
  { "class", "^md\\.obsidian\\.Obsidian$",                                                              1.0, 0.95 },
  { "class", "^steam$",                                                                                 1.0, 0.95 }, -- only the client, not the games (steam_app_*)
  { "class", "^com\\.obsproject\\.Studio$",                                                             1.0, 0.95 },

  -- fully opaque
  { "class", "^(zen|helium)$",                                                                          1.0 },
  { "class", "^krita$",                                                                                 1.0 },
  { "class", "^mpv$",                                                                                   1.0 },
  { "class", "^org\\.quickshell$",                                                                      1.0 },
}

for _, o in ipairs(opacity) do
  local inactive = o[4] and (o[4] .. " override") or "1.0"
  hl.window_rule({
    match   = { [o[1]] = o[2] },
    opacity = o[3] .. " override " .. inactive,
  })
end

-- tmux_nvim: uniform opacity for text + background, with blur.
-- No force_rgbx (it marks the window opaque -> Hyprland skips the blur). Instead the window is
-- started with kitty background_opacity=1 + dynamic_background_opacity=yes (scripts/nvim.sh,
-- scripts/start.sh): fully opaque content, but still an alpha framebuffer so the blur stays.
hl.window_rule({
  match   = { title = "^tmux_nvim$" },
  opacity = "0.95 override 0.9 override",
})

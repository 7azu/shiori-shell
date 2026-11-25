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
-- │  PYWAL COLORS                                              │
-- └────────────────────────────────────────────────────────────┘
-- wal rewrites this file on every wallpaper change,
-- the wallpaper picker then runs `hyprctl reload`
-- Before the first wallpaper (fresh install) the file does not exist yet: the default palette of the
-- repo (wal/colorschemes/dark/shiori.json) instead of an error
local ok, wal = pcall(dofile, os.getenv("HOME") .. "/.cache/wal/colors.lua")
if not ok or type(wal) ~= "table" then
  wal = {
    background = "#16161e", foreground = "#c0caf5", cursor = "#c0caf5",
    color0 = "#16161e", color1 = "#f7768e", color2 = "#9ece6a", color3 = "#e0af68",
    color4 = "#7aa2f7", color5 = "#bb9af7", color6 = "#7dcfff", color7 = "#c0caf5",
    color8 = "#414868", color9 = "#f7768e", color10 = "#9ece6a", color11 = "#e0af68",
    color12 = "#7aa2f7", color13 = "#bb9af7", color14 = "#7dcfff", color15 = "#c0caf5",
  }
end

-- "#rrggbb" -> "rrggbb" for rgba() strings
local function rgb(c) return (c:gsub("^#", "")) end

-- ┌────────────────────────────────────────────────────────────┐
-- │  GAPS, BORDERS & DECORATION                                │
-- └────────────────────────────────────────────────────────────┘
hl.config({
  -- border + shadow colors fade live on a wallpaper switch: quickshell/services/HyprlandColorFade.qml
  -- sends every fade step via hyprctl eval (same mapping as here: keep both in sync)
  general = {
    gaps_in          = 6,
    gaps_out         = 15,
    border_size      = 1,
    col              = {
      active_border   = wal.color5,
      inactive_border = wal.color0,
    },
    resize_on_border = false,
    allow_tearing    = false,
  },

  decoration = {
    rounding         = 1,
    rounding_power   = 3,
    active_opacity   = 0.9,
    inactive_opacity = 0.78,

    -- large, soft shadow slightly downwards: windows look like floating cards
    -- (most visible on the floating stage on workspace 1, modules/home.lua).
    -- Unfocused windows get a weaker one, so the focused window stands out.
    shadow           = {
      enabled        = true,
      range          = 28,
      render_power   = 2,
      offset         = "0 8",
      color          = "rgba(" .. rgb(wal.color0) .. "cc)",
      color_inactive = "rgba(" .. rgb(wal.color0) .. "88)",
    },

    blur             = {
      enabled  = true,
      variant  = "haze",
      size     = 7,
      passes   = 2,
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

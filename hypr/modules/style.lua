-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--   ~/.config/hypr/modules/style.lua
--   Window look that can be changed in the settings window (page "Windows")
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Gaps, borders, corners, opacity, shadow, blur and animation speed come from
-- ~/.config/shiori-shell/settings.json, key "windows"; the defaults from the shell's
-- quickshell/defaults/settings.json (same key), and if that is missing from the table below.
--
-- Border colors are either a color of the wallpaper palette ("wal:color5") or a fixed one ("#rrggbb").
--
-- looks.lua and animations.lua use this module when the config loads. The settings window sends every
-- change live (quickshell/services/WindowStyle.qml):
--   hyprctl eval 'hl.config(dofile(".../style.lua").config())'
-- so nothing here may do more than read files and return values.

local json = require("json")

local M = {}

local home = os.getenv("HOME")
local config = os.getenv("XDG_CONFIG_HOME") or (home .. "/.config")

local fallback = {
  gapsIn = 6, gapsOut = 15, borderSize = 1, rounding = 1, roundingPower = 3,
  activeBorder = "wal:color5", inactiveBorder = "wal:color0",
  activeOpacity = 90, inactiveOpacity = 78, -- percent
  shadow = true, shadowRange = 28,
  blur = true, blurSize = 7, blurPasses = 2,
  animations = true, animSpeed = 1,
}

local function section(path)
  local t = json.read(path)
  return type(t) == "table" and type(t.windows) == "table" and t.windows or {}
end

local base = section(config .. "/quickshell/defaults/settings.json")
local own = section(config .. "/shiori-shell/settings.json")

-- The value of a key, of the same type as its fallback
local function get(key)
  for _, t in ipairs({ own, base }) do
    local v = t[key]
    if v ~= nil and type(v) == type(fallback[key]) then
      return v
    end
  end
  return fallback[key]
end

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

-- ┌────────────────────────────────────────────────────────────┐
-- │  PYWAL COLORS                                              │
-- └────────────────────────────────────────────────────────────┘
-- wal rewrites this file on every wallpaper change, the wallpaper picker then runs `hyprctl reload`.
-- Before the first wallpaper (fresh install) it does not exist yet: the default palette of the repo
-- (wal/colorschemes/dark/shiori.json) instead of an error
local ok, wal = pcall(dofile, home .. "/.cache/wal/colors.lua")
if not ok or type(wal) ~= "table" then
  wal = {
    background = "#16161e", foreground = "#c0caf5", cursor = "#c0caf5",
    color0 = "#16161e", color1 = "#f7768e", color2 = "#9ece6a", color3 = "#e0af68",
    color4 = "#7aa2f7", color5 = "#bb9af7", color6 = "#7dcfff", color7 = "#c0caf5",
    color8 = "#414868", color9 = "#f7768e", color10 = "#9ece6a", color11 = "#e0af68",
    color12 = "#7aa2f7", color13 = "#bb9af7", color14 = "#7dcfff", color15 = "#c0caf5",
  }
end
M.wal = wal

-- "wal:color5" -> that palette color, "#rrggbb" -> itself, anything else -> the fallback's color
local function color(key)
  local v = get(key)
  local slot = v:match("^wal:(color%d+)$")
  if slot and wal[slot] then
    return wal[slot]
  end
  if v:match("^#%x%x%x%x%x%x$") then
    return v
  end
  return wal[fallback[key]:sub(5)]
end

-- "#rrggbb" -> "rrggbb" for rgba() strings
local function rgb(c) return (c:gsub("^#", "")) end

M.activeBorder = color("activeBorder")
M.inactiveBorder = color("inactiveBorder")
-- Factor for every animation speed in animations.lua (larger = slower)
M.animSpeed = clamp(get("animSpeed"), 0.25, 4)

-- What hl.config gets (looks.lua adds what cannot be changed in the settings)
function M.config()
  return {
    general = {
      gaps_in     = clamp(math.floor(get("gapsIn")), 0, 60),
      gaps_out    = clamp(math.floor(get("gapsOut")), 0, 120),
      border_size = clamp(math.floor(get("borderSize")), 0, 12),
      col         = {
        active_border   = M.activeBorder,
        inactive_border = M.inactiveBorder,
      },
    },
    decoration = {
      rounding         = clamp(math.floor(get("rounding")), 0, 40),
      rounding_power   = clamp(get("roundingPower"), 1, 10),
      active_opacity   = clamp(get("activeOpacity"), 10, 100) / 100,
      inactive_opacity = clamp(get("inactiveOpacity"), 10, 100) / 100,
      -- large, soft shadow slightly downwards: windows look like floating cards. Unfocused windows get
      -- a weaker one, so the focused window stands out.
      shadow           = {
        enabled        = get("shadow"),
        range          = clamp(math.floor(get("shadowRange")), 0, 120),
        color          = "rgba(" .. rgb(wal.color0) .. "cc)",
        color_inactive = "rgba(" .. rgb(wal.color0) .. "88)",
      },
      blur             = {
        enabled = get("blur"),
        size    = clamp(math.floor(get("blurSize")), 1, 20),
        passes  = clamp(math.floor(get("blurPasses")), 1, 6),
      },
    },
    animations = {
      enabled = get("animations"),
    },
  }
end

return M

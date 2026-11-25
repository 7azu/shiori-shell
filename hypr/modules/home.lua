-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--   ~/.config/hypr/modules/home.lua
--   Workspace 1 "stage": the two terminals from scripts/start.sh float at fixed positions
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
--   ┌──────────────────────────── Bar ─────────────────────────────┐
--   │     ┌──────────────────────┐                                 │
--   │     │                      │                                 │
--   │     │  shell               │  ┌──────────────────────┐       │
--   │     │                      │  │                      │       │
--   │     └──────────────────────┘  │  music (rmpc)        │       │
--   │                               │                      │       │
--   │                               └──────────────────────┘       │
--   │~~~~~~~~~ audio visualizer (Quickshell, not a window) ~~~~~~~~│
--   └──────────────────────────────────────────────────────────────┘
--
-- The windows are recognized by their own class (kitty --class kitty-stage-…), not by title:
-- programs inside (zsh, Claude Code …) change the title, sometimes even before the window maps.
-- Other kitty windows (SUPER + Q) keep the class "kitty" and stay normal tiled windows.
-- The visualizer at the bottom is drawn by Quickshell (windows/DesktopVisualizer.qml) on the
-- top layer, so the windows leave room for it (lowest 300 px, about 21 %).
-- SUPER + D switches between this stage and normal tiling (see keybindings.lua).
-- Bar icon for these classes: quickshell/bar/Workspaces.qml (classMap).

local M = {}

local SHELL = "kitty-stage-shell"
local MUSIC = "kitty-stage-music"

-- position and size as fractions of the usable monitor area (without the bar),
-- so the layout also fits other machines/resolutions
--  class      x      y      w     h     slides in from
-- (measured from the layout arranged by hand on 2026-11-17, DP-2 2560x1440 with the 40 px bar)
local stage = {
-- rmpc's bottom edge must stay above the visualizer strip (lowest 300 px = ~21 % of the usable height),
-- otherwise the visualizer hides itself for good (on DP-2: y + h must end at or above pixel 1140)
  [SHELL] = { 0.0403, 0.1165, 0.3899, 0.4801, "left" },   -- shell top left,
  [MUSIC] = { 0.5559, 0.2979, 0.3981, 0.4879, "right" },  -- rmpc lower right, ends exactly at the strip
}

-- optional per-machine overrides outside the synced dirs (e.g. laptop: rmpc higher, the 300 px
-- visualizer strip takes a bigger share of a 1200 px screen). The file returns { [class] = {x, y, w, h} }.
local localStage = os.getenv("HOME") .. "/.config/dotfiles-local/hypr-stage.lua"
local lf = io.open(localStage, "r")
if lf then
  lf:close()
  for class, g in pairs(dofile(localStage)) do
    if stage[class] then
      for i = 1, 4 do
        stage[class][i] = g[i] or stage[class][i]
      end
    end
  end
end

-- Height of the visualizer strip in logical px: 300 * uiScale, as in DesktopVisualizer.qml
-- (stripHeight = MachineConfig.px(300); uiScale from ~/.config/quickshell-local/screens.json)
local function strip_height()
  local scale = 1
  local f = io.open(os.getenv("HOME") .. "/.config/quickshell-local/screens.json", "r")
  if f then
    local s = tonumber((f:read("*a") or ""):match('"uiScale"%s*:%s*([%d.]+)'))
    f:close()
    if s and s > 0.25 and s < 4 then
      scale = s
    end
  end
  return math.floor(300 * scale + 0.5)
end

for class, g in pairs(stage) do
  hl.window_rule({
    match     = { class = "^" .. class .. "$" },
    workspace = "1",
    float     = true,
    animation = "slide " .. g[5],
    -- less see-through than other kitty windows (looks.lua: 0.85 focused, 0.78 unfocused)
    opacity   = "0.95 override 0.9 override",
  })
end

-- move a stage window to its spot on its monitor
-- The monitor comes from the window's workspace (1 -> DP-2), not w.monitor: when the window opens,
-- w.monitor is still the focused monitor. At boot that was the portrait DP-3, so the shell got
-- DP-3's size (narrow and tall) before the rule moved it to workspace 1.
local function place(w)
  local g = stage[w.class]
  local m = (w.workspace and w.workspace.monitor) or w.monitor
  if not g or not m then
    return
  end
  local mw, mh = m.width / m.scale, m.height / m.scale
  if m.transform % 2 == 1 then
    mw, mh = mh, mw
  end
  local r = m.reserved
  local uw, uh = mw - r.left - r.right, mh - r.top - r.bottom
  local y, h = math.floor(r.top + uh * g[2]), math.floor(uh * g[4])
  -- The fractions fit 1440 px; the strip is a fixed 300 px, so on other heights (e.g. 1341 px)
  -- a window ended inside it and the visualizer hid itself for good -> end above the strip,
  -- first by shrinking, below 60 % of the planned height by moving up
  local limit = mh - strip_height()
  if y + h > limit then
    h = math.max(limit - y, math.floor(uh * g[4] * 0.6))
    y = math.max(r.top, limit - h)
  end
  hl.dispatch(hl.dsp.window.resize({
    window = w, x = math.floor(uw * g[3]), y = h, relative = false,
  }))
  -- move takes global coordinates (monitor position + offset)
  hl.dispatch(hl.dsp.window.move({
    window   = w,
    x        = math.floor(m.x + r.left + uw * g[1]),
    y        = math.floor(m.y + y),
    relative = false,
  }))
end
hl.on("window.open", place)

local function stage_windows()
  local found = {}
  for class in pairs(stage) do
    -- the filter takes the exact class, not a regex
    found[class] = hl.get_windows({ class = class })[1]
  end
  return found
end

-- put all floating stage windows (back) in their spots, e.g. after changing the layout above:
-- hyprctl eval 'require("home").arrange()'
function M.arrange()
  for _, w in pairs(stage_windows()) do
    if w.floating then
      place(w)
    end
  end
end

-- dwindle splits the tiled window under the mouse pointer and picks the side by its position.
-- So for a fixed order: focus the window to split, preselect the side and put the pointer
-- into that half (fx/fy = fraction of the usable area). Same trick as scripts/start.sh.
local function tile_next_to(w, target, dir, fx, fy)
  local m = target.monitor
  local r = m.reserved
  hl.dispatch(hl.dsp.focus({ window = target }))
  hl.dispatch(hl.dsp.cursor.move({
    x = math.floor(m.x + r.left + (m.width / m.scale - r.left - r.right) * fx),
    y = math.floor(m.y + r.top + (m.height / m.scale - r.top - r.bottom) * fy),
  }))
  hl.dispatch(hl.dsp.layout("preselect " .. dir))
  hl.dispatch(hl.dsp.window.float({ action = "disable", window = w }))
end

-- SUPER + D: stage <-> tiling (shell | music)
function M.toggle()
  local wins = stage_windows()
  local shell, music = wins[SHELL], wins[MUSIC]
  -- only on the stage's own workspace (focus/pointer would otherwise pull you over to it)
  local active = hl.get_active_workspace()
  if not shell or not shell.workspace or not active or shell.workspace.id ~= active.id then
    return
  end
  if shell.floating then
    hl.dispatch(hl.dsp.window.float({ action = "disable", window = shell }))
    if music then
      tile_next_to(music, shell, "r", 0.85, 0.5)
    end
    hl.dispatch(hl.dsp.focus({ window = shell }))
  else
    for _, w in pairs(wins) do
      hl.dispatch(hl.dsp.window.float({ action = "enable", window = w }))
    end
    M.arrange()
  end
end

return M

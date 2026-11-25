-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--   ~/.config/hypr/modules/keys.lua
--   Keybindings that can be changed in the settings window (Shortcuts page)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- keybindings.lua names every changeable binding and gives its default:
--
--   keys.bind("terminal", "MOD + Q", hl.dsp.exec_cmd("kitty"), "Apps: Open terminal")
--
-- "MOD" is the main modifier (SUPER unless the settings say otherwise). Your own choices live in
-- ~/.config/shiori-shell/settings.json, written by the settings window:
--
--   "keys": { "mod": "ALT", "binds": { "terminal": "SUPER + Return", "trash": "" } }
--
-- A binding named there replaces the default, "" turns it off. Hyprland has to reload for a change
-- (the settings window does that itself).
--
-- At the end keybindings.lua calls keys.export(): it writes what is bound now to
-- $XDG_RUNTIME_DIR/shiori-shell-keybinds.json, which is where the settings window reads the list from
-- (name, default, current keys). So the bindings are described in one place only, here in Lua.

local json = require("json")

local M = {}

local config = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")
local settings = json.read(config .. "/shiori-shell/settings.json")
local own = type(settings) == "table" and type(settings.keys) == "table" and settings.keys or {}
local overrides = type(own.binds) == "table" and own.binds or {}

local mods = { SUPER = true, ALT = true, CTRL = true }

-- Main modifier of all defaults
M.mod = mods[own.mod] and own.mod or "SUPER"

-- Everything bound here, in order, for the export
local list = {}

local function expand(keys)
  return (keys:gsub("MOD", M.mod))
end

-- A changeable binding. default: keys with "MOD" for the main modifier; description: "Group: what it
-- does" (the group sorts it in the shortcuts panel and on the settings page); opts: further options of hl.bind.
function M.bind(id, default, action, description, opts)
  default = expand(default)
  local keys = overrides[id]
  if type(keys) ~= "string" then
    keys = default
  end
  local entry = { id = id, description = description, default = default, keys = keys }
  list[#list + 1] = entry
  if keys == "" then
    return
  end
  opts = opts or {}
  opts.description = description
  -- Keys Hyprland does not accept (a typo in settings.json): hl.bind reports them itself and returns
  -- nothing. The action keeps its default then, and the settings page says so.
  local ok, made = pcall(hl.bind, keys, action, opts)
  if not ok or made == nil then
    entry.error = keys
    entry.keys = default
    -- (a binding without default keys simply stays unbound)
    if keys ~= default and default ~= "" then
      pcall(hl.bind, default, action, opts)
    end
  end
end

-- Bindings that stay as they are (groups like MOD + 1 … 0, mouse and media keys): only listed, so the
-- settings page can show them. keys is a text for display, the binding itself is made with hl.bind.
function M.note(keys, description)
  list[#list + 1] = { description = description, default = expand(keys), keys = expand(keys), fixed = true }
end

local function quote(text)
  return '"' .. tostring(text):gsub('[%c"\\]', function(c)
    if c == '"' or c == "\\" then
      return "\\" .. c
    end
    return string.format("\\u%04x", string.byte(c))
  end) .. '"'
end

function M.export()
  local rows = {}
  for _, e in ipairs(list) do
    local parts = {
      '"description": ' .. quote(e.description),
      '"default": ' .. quote(e.default),
      '"keys": ' .. quote(e.keys),
    }
    if e.id then
      parts[#parts + 1] = '"id": ' .. quote(e.id)
    end
    if e.fixed then
      parts[#parts + 1] = '"fixed": true'
    end
    if e.error then
      parts[#parts + 1] = '"error": ' .. quote(e.error)
    end
    rows[#rows + 1] = "    {" .. table.concat(parts, ", ") .. "}"
  end
  local text = '{\n  "mod": ' .. quote(M.mod) .. ',\n  "binds": [\n' .. table.concat(rows, ",\n") .. "\n  ]\n}\n"
  local path = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/shiori-shell-keybinds.json"
  -- Written next to it and moved over: a reader never sees half a file
  local f = io.open(path .. ".new", "w")
  if not f then
    return
  end
  f:write(text)
  f:close()
  os.rename(path .. ".new", path)
end

return M

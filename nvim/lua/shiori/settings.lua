-- ~/.config/nvim/lua/shiori/settings.lua --
-- The shell's settings for nvim: quickshell/defaults/settings.json with ~/.config/shiori-shell/settings.json
-- merged over it, same path rules as services/Settings.qml and scripts/shiori_settings.py
-- (~, $HOME and the XDG folders $DOCUMENTS, $DOWNLOAD, $PICTURES, $MUSIC, $VIDEOS, $DESKTOP).
--
--   require("shiori.settings").folder("projects")  -> absolute path or "" (not set)

local M = {}

local home = vim.env.HOME
local config = vim.env.XDG_CONFIG_HOME or (home .. "/.config")
local fallback = { DOCUMENTS = "Documents", DOWNLOAD = "Downloads", PICTURES = "Pictures", MUSIC = "Music",
  VIDEOS = "Videos", DESKTOP = "Desktop" }
local cache

local function read_json(path)
  local f = io.open(path, "r")
  if not f then
    return {}
  end
  local ok, data = pcall(vim.json.decode, f:read("*a"))
  f:close()
  return ok and type(data) == "table" and data or {}
end

local function user_dirs()
  local dirs = {}
  for k, v in pairs(fallback) do
    dirs[k] = home .. "/" .. v
  end
  local f = io.open(config .. "/user-dirs.dirs", "r")
  if f then
    for line in f:lines() do
      local key, value = line:match('^%s*XDG_([A-Z]+)_DIR="(.*)"')
      if key then
        dirs[key] = value:gsub("%$HOME", home)
      end
    end
    f:close()
  end
  return dirs
end

local function expand(path)
  if type(path) ~= "string" or path == "" then
    return ""
  end
  local dirs = user_dirs()
  path = path:gsub("^~", home):gsub("%$([A-Z]+)", function(name)
    return name == "HOME" and home or dirs[name]
  end)
  return (path:gsub("/+$", ""))
end

local function folders()
  if not cache then
    local defaults = read_json(config .. "/quickshell/defaults/settings.json").folders
    local own = read_json(config .. "/shiori-shell/settings.json").folders
    cache = vim.tbl_extend("force", type(defaults) == "table" and defaults or {}, type(own) == "table" and own or {})
  end
  return cache
end

function M.folder(key)
  return expand(folders()[key])
end

return M

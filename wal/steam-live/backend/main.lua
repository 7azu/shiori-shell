local logger     = require("logger")
local millennium = require("millennium")
local utils      = require("utils")

-- The same file Millennium loads as Quick CSS (wal writes into it via the symlink
-- ~/.cache/wal/steam-colors.css)
local config_home = utils.getenv("XDG_CONFIG_HOME")
if config_home == nil or config_home == "" then
    config_home = utils.getenv("HOME") .. "/.config"
end
local quick_css_path = config_home .. "/millennium/quick.css"
-- Own log file: backend logs of plugins do not end up in Steam's console-linux.txt
local log_path = utils.getenv("HOME") .. "/.cache/pywal-live.log"

local function write_log(message)
    utils.append_file(log_path, os.date("%H:%M:%S ") .. message .. "\n")
    logger:info(message)
end

---@ffi
--- Current content of the Quick CSS ("" if not readable)
---@return string
function read_quick_css()
    return utils.read_file(quick_css_path) or ""
end

---@ffi
--- Write a message of the frontend into the Steam log
---@param message string
---@return boolean
function log(message)
    write_log(message)
    return true
end

return {
    on_load = function()
        write_log("[pywal live] backend loaded, watching " .. quick_css_path)
        millennium.ready()
    end,
}

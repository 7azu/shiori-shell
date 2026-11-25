-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--   ~/.config/hypr/modules/json.lua
--   Small JSON reader for the shell's settings (~/.config/shiori-shell/settings.json)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- json.decode(text) returns the value, or nil and a message. Objects and arrays become tables,
-- null becomes nil. Plain Lua, so it runs in every Lua version Hyprland may ship.

local M = {}

local escapes = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

local function fail(pos, what)
  error(string.format("JSON: %s at character %d", what, pos), 0)
end

local function skip(s, i)
  return (s:find("[^ \t\r\n]", i)) or (#s + 1)
end

-- \uXXXX as UTF-8
local function utf8(code)
  if code < 0x80 then
    return string.char(code)
  elseif code < 0x800 then
    return string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40)
  elseif code < 0x10000 then
    return string.char(0xE0 + math.floor(code / 0x1000), 0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
  end
  return string.char(0xF0 + math.floor(code / 0x40000), 0x80 + math.floor(code / 0x1000) % 0x40,
    0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
end

local function read_string(s, i)
  local out, j = {}, i + 1
  while true do
    local k = s:find('["\\]', j)
    if not k then
      fail(i, "text without an end")
    end
    out[#out + 1] = s:sub(j, k - 1)
    if s:sub(k, k) == '"' then
      return table.concat(out), k + 1
    end
    local c = s:sub(k + 1, k + 1)
    if c == "u" then
      local code = tonumber(s:sub(k + 2, k + 5), 16)
      if not code then
        fail(k, "broken \\u")
      end
      j = k + 6
      -- two halves of one character beyond the basic plane
      if code >= 0xD800 and code < 0xDC00 and s:sub(j, j + 1) == "\\u" then
        local low = tonumber(s:sub(j + 2, j + 5), 16)
        if low and low >= 0xDC00 and low < 0xE000 then
          code = 0x10000 + (code - 0xD800) * 0x400 + (low - 0xDC00)
          j = j + 6
        end
      end
      out[#out + 1] = utf8(code)
    elseif escapes[c] then
      out[#out + 1] = escapes[c]
      j = k + 2
    else
      fail(k, "unknown escape")
    end
  end
end

local read_value

local function read_array(s, i)
  local out, n = {}, 0
  i = skip(s, i + 1)
  if s:sub(i, i) == "]" then
    return out, i + 1
  end
  while true do
    local v
    v, i = read_value(s, i)
    n = n + 1
    out[n] = v
    i = skip(s, i)
    local c = s:sub(i, i)
    if c == "]" then
      return out, i + 1
    elseif c ~= "," then
      fail(i, "expected , or ]")
    end
    i = skip(s, i + 1)
  end
end

local function read_object(s, i)
  local out = {}
  i = skip(s, i + 1)
  if s:sub(i, i) == "}" then
    return out, i + 1
  end
  while true do
    if s:sub(i, i) ~= '"' then
      fail(i, "expected a name")
    end
    local key
    key, i = read_string(s, i)
    i = skip(s, i)
    if s:sub(i, i) ~= ":" then
      fail(i, "expected :")
    end
    out[key], i = read_value(s, skip(s, i + 1))
    i = skip(s, i)
    local c = s:sub(i, i)
    if c == "}" then
      return out, i + 1
    elseif c ~= "," then
      fail(i, "expected , or }")
    end
    i = skip(s, i + 1)
  end
end

read_value = function(s, i)
  local c = s:sub(i, i)
  if c == "{" then
    return read_object(s, i)
  elseif c == "[" then
    return read_array(s, i)
  elseif c == '"' then
    return read_string(s, i)
  elseif s:sub(i, i + 3) == "true" then
    return true, i + 4
  elseif s:sub(i, i + 4) == "false" then
    return false, i + 5
  elseif s:sub(i, i + 3) == "null" then
    return nil, i + 4
  end
  local number = s:match("^-?%d+%.?%d*[eE]?[+-]?%d*", i)
  if not number or not tonumber(number) then
    fail(i, "unexpected character")
  end
  return tonumber(number), i + #number
end

function M.decode(text)
  local ok, value = pcall(function()
    local v, i = read_value(text, skip(text, 1))
    if skip(text, i) <= #text then
      fail(i, "text after the end")
    end
    return v
  end)
  if ok then
    return value
  end
  return nil, value
end

-- A file as a value; nil if it is missing or broken
function M.read(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local text = f:read("*a")
  f:close()
  return M.decode(text or "")
end

return M

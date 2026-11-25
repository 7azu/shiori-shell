-- ~/.config/nvim/lua/shiori/run.lua --
-- Compile and run the current file, output in a terminal at the bottom.

local M = {}

local term_buf = nil

-- Returns the shell command for the current file (or nil if unknown)
local function command_for(file)
  local q = vim.fn.shellescape
  local name = vim.fn.fnamemodify(file, ":t")
  local bin = q(vim.fn.fnamemodify(file, ":t:r"))
  local ft = vim.bo.filetype

  -- Sanitizer: on memory errors (array bounds, broken pointer, ...) an exact message with the line
  local san = " -fsanitize=address,undefined -fno-omit-frame-pointer "
  if ft == "c" then
    return "gcc -std=c17 -Wall -Wextra -g" .. san .. q(name) .. " -o " .. bin .. " && ./" .. bin
  elseif ft == "cpp" then
    return "g++ -std=c++20 -Wall -Wextra -g" .. san .. q(name) .. " -o " .. bin .. " && ./" .. bin
  elseif ft == "rust" then
    -- In a Cargo project cargo run, otherwise a single file with rustc
    if vim.fs.root(file, "Cargo.toml") then
      return "cargo run"
    end
    return "rustc " .. q(name) .. " -o " .. bin .. " && ./" .. bin
  elseif ft == "python" then
    return "python3 " .. q(name)
  elseif ft == "javascript" then
    return "node " .. q(name)
  elseif ft == "lua" then
    return "lua " .. q(name)
  elseif ft == "sh" or ft == "bash" then
    return "bash " .. q(name)
  elseif ft == "html" then
    return "xdg-open " .. q(name)
  end
end

function M.run()
  local file = vim.api.nvim_buf_get_name(0)
  if file == "" then
    vim.notify("The file has no name yet, save it first", vim.log.levels.WARN)
    return
  end
  local cmd = command_for(file)
  if not cmd then
    vim.notify("No run command for filetype '" .. vim.bo.filetype .. "'", vim.log.levels.WARN)
    return
  end

  vim.cmd("silent! write")

  -- With Cargo start in the project root, otherwise in the file's folder
  local cwd = vim.fs.root(file, "Cargo.toml")
  if not (vim.bo.filetype == "rust" and cwd) then
    cwd = vim.fn.fnamemodify(file, ":p:h")
  end

  -- Close the old run terminal, so more and more splits do not pile up
  if term_buf and vim.api.nvim_buf_is_valid(term_buf) then
    vim.api.nvim_buf_delete(term_buf, { force = true })
  end

  vim.cmd("botright 15new")
  term_buf = vim.api.nvim_get_current_buf()
  vim.fn.jobstart(cmd, { term = true, cwd = cwd })

  -- Esc closes the run window right away, whether the program is still running or not
  -- (force = true ends the process with it). nowait: do not wait for the global <Esc><Esc>.
  local buf = term_buf
  local function close()
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end
  for _, mode in ipairs({ "t", "n" }) do
    vim.keymap.set(mode, "<Esc>", close, { buffer = buf, nowait = true, desc = "Close run window" })
  end
  vim.keymap.set("n", "q", close, { buffer = buf, nowait = true, desc = "Close run window" })
  vim.cmd("startinsert") -- type right away (e.g. for cin/input())
end

return M

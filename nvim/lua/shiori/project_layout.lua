-- ~/.config/nvim/lua/shiori/project_layout.lua --
-- When you open a file of a project in nvim (inside tmux), two tmux panes are added
-- on the right automatically: Claude on top, a terminal below, both in the project folder.
-- Only with the setting folders.projects (~/.config/shiori-shell/settings.json, e.g. "~/Documents/Programming")
-- and the claude CLI installed; otherwise this does nothing.
--
--   ┌──────────────┬────────┐
--   │              │ claude │
--   │     nvim     ├────────┤
--   │              │  zsh   │
--   └──────────────┴────────┘

local M = {}

local programming = require("shiori.settings").folder("projects")
local projects = programming .. "/projects"
-- Projects: every folder directly under <projects folder>/projects, and any folder with one of these files
-- inside the projects folder
local markers = { "Cargo.toml", "package.json", "pyproject.toml", "Makefile", "CMakeLists.txt" }

local done = {} -- projects for which panes were already opened in this nvim instance

-- Project folder of a file, or nil
local function project_root(file)
  -- Every folder directly under projects/ is a project, even without a marker file
  local name = file:match("^" .. vim.pesc(projects) .. "/([^/]+)/")
  if name then
    return projects .. "/" .. name
  end
  local root = vim.fs.root(file, markers)
  if root and vim.startswith(root, programming .. "/") then
    return root
  end
end

local function tmux(args)
  local result = vim.system(vim.list_extend({ "tmux" }, args), { text = true }):wait()
  return result.code == 0 and vim.trim(result.stdout or "") or nil
end

local function open_layout(root)
  local pane = vim.env.TMUX_PANE
  -- Only when nvim is alone in the tmux window (otherwise you already have a layout)
  if tmux({ "display-message", "-p", "-t", pane, "#{window_panes}" }) ~= "1" then
    return
  end
  -- -d: the focus stays in nvim. Right column 38 % wide, Claude on top in it.
  local claude = tmux({ "split-window", "-h", "-d", "-l", "38%", "-t", pane, "-c", root, "-P", "-F", "#{pane_id}" })
  if not claude then
    return
  end
  -- Terminal below 35 %: Claude needs more height for long answers than short commands
  tmux({ "split-window", "-v", "-d", "-l", "35%", "-t", claude, "-c", root })
  -- Start through the shell: after quitting Claude a terminal stays in the project
  tmux({ "send-keys", "-t", claude, "claude", "Enter" })
end

function M.setup()
  if not vim.env.TMUX or not vim.env.TMUX_PANE or programming == "" or vim.fn.executable("claude") ~= 1 then
    return
  end
  vim.api.nvim_create_autocmd("BufEnter", {
    group = vim.api.nvim_create_augroup("ProjectLayout", { clear = true }),
    callback = function(args)
      if vim.bo[args.buf].buftype ~= "" then
        return
      end
      local file = vim.api.nvim_buf_get_name(args.buf)
      if file == "" then
        return
      end
      local root = project_root(vim.fn.resolve(file))
      if not root or done[root] then
        return
      end
      done[root] = true
      vim.schedule(function() open_layout(root) end)
    end,
  })
end

return M

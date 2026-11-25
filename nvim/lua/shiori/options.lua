
-- ~/.config/nvim/lua/user/options.lua

local opt = vim.opt

-- Display
opt.number = true
opt.relativenumber = true
opt.termguicolors = true
opt.signcolumn = "yes"
opt.cursorline = true

-- Indentation
opt.tabstop = 2
opt.shiftwidth = 2
opt.expandtab = true
opt.smartindent = true

-- Suche
opt.ignorecase = true
opt.smartcase = true
opt.hlsearch = false

-- Behavior
opt.undofile = true
opt.splitright = true
opt.splitbelow = true
opt.clipboard = "unnamedplus"  -- Use the system clipboard
opt.mouse = ""
opt.scrolloff = 8
opt.sidescrolloff = 8
-- Separator line between windows on top of each other (e.g. code / run terminal):
-- the empty status line is filled with a thin line (color in plugins/pywal.lua)
opt.fillchars:append({ stl = "─", stlnc = "─" })
-- auto-session needs localoptions (otherwise e.g. filetype/indent are lost on restore)
opt.sessionoptions = "blank,buffers,curdir,folds,help,tabpages,winsize,winpos,terminal,localoptions"

-- Diagnostics: since nvim 0.11 virtual_text is off by default
vim.diagnostic.config({ virtual_text = true })


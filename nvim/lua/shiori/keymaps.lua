-- ~/.config/nvim/lua/shiori/keymaps.lua
-- Overview of all shortcuts: KEYMAPS.md (in nvim: <space>?)

local map = vim.keymap.set

-- Window navigation with Ctrl+h/j/k/l: plugins/tmux-navigator.lua
-- (also jumps beyond the nvim edge into tmux panes)

-- Compile + run the current file
map("n", "<leader>r", function() require("shiori.run").run() end, { desc = "Run file" })

-- Terminal: Esc twice to get back to normal mode
map("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Leave terminal mode" })

-- Buffers (next/previous: ]b / [b, built in)
map("n", "<leader>bd", "<cmd>bdelete<cr>", { desc = "Close buffer" })

-- Clipboard: no own mapping needed, y/p use the system clipboard directly
-- thanks to clipboard=unnamedplus (options.lua)

-- Open the overview of all shortcuts
map("n", "<leader>?", function()
  vim.cmd("botright vsplit " .. vim.fn.fnameescape(vim.fn.stdpath("config") .. "/KEYMAPS.md"))
end, { desc = "Keymap overview" })

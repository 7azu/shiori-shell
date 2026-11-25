-- ~/.config/nvim/lua/shiori/plugins/tmux-navigator.lua --
-- Ctrl+h/j/k/l: to the window in that direction, first nvim splits, at the edge on into tmux panes
-- (counterpart in ~/.config/tmux/tmux.conf: @plugin 'christoomey/vim-tmux-navigator').

return {
  "christoomey/vim-tmux-navigator",
  init = function()
    vim.g.tmux_navigator_no_mappings = 1 -- own keymaps below, without Ctrl+\
  end,
  cmd = { "TmuxNavigateLeft", "TmuxNavigateDown", "TmuxNavigateUp", "TmuxNavigateRight" },
  keys = {
    { "<C-h>", "<cmd>TmuxNavigateLeft<cr>", desc = "Window left (nvim/tmux)" },
    { "<C-j>", "<cmd>TmuxNavigateDown<cr>", desc = "Window down (nvim/tmux)" },
    { "<C-k>", "<cmd>TmuxNavigateUp<cr>", desc = "Window up (nvim/tmux)" },
    { "<C-l>", "<cmd>TmuxNavigateRight<cr>", desc = "Window right (nvim/tmux)" },
  },
}

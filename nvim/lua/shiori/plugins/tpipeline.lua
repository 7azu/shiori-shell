-- ~/.config/nvim/lua/shiori/tpipeline.lua --



return {
  "vimpostor/vim-tpipeline",
  init = function()
    -- Clears the Neovim status bar, so it does not show up twice
    vim.g.tpipeline_clearstl = 1
  end,
}

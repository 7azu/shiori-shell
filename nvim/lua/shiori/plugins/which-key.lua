-- ~/.config/nvim/lua/shiori/plugins/which-key.lua --

-- After a key like <space> shows a popup with all possible continuations
return {
  "folke/which-key.nvim",
  event = "VeryLazy",
  opts = {
    preset = "helix",
    spec = {
      { "<leader>f", group = "Search" },
      { "<leader>o", group = "Open config folders" },
      { "<leader>b", group = "Buffer" },
      { "<leader>c", group = "Code" },
      { "<leader>d", group = "Debugger" },
      { "<leader>t", group = "Toggle" },
      { "gr", group = "LSP (rename, actions, references)" },
    },
  },
}

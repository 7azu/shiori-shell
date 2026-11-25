return {
  "mikavilpas/yazi.nvim",
  version = "*",
  event = "VeryLazy",
  dependencies = {
    { "nvim-lua/plenary.nvim", lazy = true },
  },
  keys = {
    {
      "<leader>e",
      mode = { "n", "v" },
      "<cmd>Yazi<cr>",
      desc = "Yazi (file manager) at this file",
    },
  },
  opts = {
    open_for_directories = false,
    -- Own yazi profile without image preview (sets YAZI_CONFIG_HOME): kitty images do not work in nvim's
    -- terminal, yazi would fall back to ueberzugpp (separate, flickering/misplaced
    -- windows). Real image previews are in the normal yazi (SUPER + E).
    config_home = vim.fn.expand("~/.config/yazi/nvim"),
    keymaps = {
      show_help = "<f1>",
    },
  },
  init = function()
    vim.g.loaded_netrwPlugin = 1
  end,
}

-- ~/.config/nvim/lua/shiori/plugins/fmt_utils.lua --


return {
  {
    "Wansmer/treesj",
    keys = {
      { "<space>m", function() require("treesj").toggle() end, desc = "Toggle block single-/multi-line" },
    },
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    config = function()
      require("treesj").setup({ use_default_keymaps = false }) -- otherwise also hidden <space>j/<space>s
    end,
  },
  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    config = function()
      local npairs = require("nvim-autopairs")
      npairs.setup({
        enable_check_bracket_line = false,
      })
    end,
  },
  {
    "echasnovski/mini.surround",
    opts = {
      custom_surroundings = nil,
      highlight_duration = 500,
      mappings = {
        add = "sa",            -- Add surrounding in Normal and Visual modes
        delete = "sd",         -- Delete surrounding
        replace = "sr",        -- Replace surrounding

        suffix_last = "l",     -- Suffix to search with "prev" method
        suffix_next = "n",     -- Suffix to search with "next" method
      },
      n_lines = 20,
      respect_selection_type = false,
      search_method = "cover",
      silent = false,
    },
  },
}

-- ~/.config/nvim/lua/shiori/plugins/flash.lua --

return {
  "folke/flash.nvim",
  event = "VeryLazy",
  opts = {},
  -- stylua: ignore
  keys = {
    { "sl",    mode = { "n", "x", "o" }, function() require("flash").jump() end,              desc = "Jump (Flash)" },
  },
}

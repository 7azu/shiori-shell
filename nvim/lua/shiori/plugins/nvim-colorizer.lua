-- ~/.config/nvim/lua/shiori/plugins/colorizer.lua --

return {
  "NvChad/nvim-colorizer.lua",
  event = "VeryLazy",
  config = function()
    require("colorizer").setup({
      filetypes = { "*" }, -- runs in all files
      user_default_options = {
        RGB = true,         -- #RGB hex codes
        RRGGBB = true,      -- #RRGGBB hex codes
        names = true,       -- "Name" colors (e.g. "blue")
        RRGGBBAA = true,    -- #RRGGBBAA hex codes
        rgb_fn = true,      -- CSS rgb() and rgba() functions
        hsl_fn = true,      -- CSS hsl() and hsla() functions
        css = true,         -- CSS support
        css_fn = true,      -- CSS-Funktionen
        mode = "background",-- sets the background color
      },
    })
  end,
}

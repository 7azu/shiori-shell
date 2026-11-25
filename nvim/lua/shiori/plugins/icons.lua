-- ~/.config/nvim/lua/shiori/plugins/icons.lua --

-- mini.icons as a replacement for nvim-web-devicons, so Telescope, alpha etc. get icons.
return {
  "echasnovski/mini.icons",
  opts = {},
  init = function()
    package.preload["nvim-web-devicons"] = function()
      require("mini.icons").mock_nvim_web_devicons()
      return package.loaded["nvim-web-devicons"]
    end
  end,
}

-- ~/.config/nvim/lua/shiori/plugins/lualine.lua


return {
  "nvim-lualine/lualine.nvim",
  dependencies = { "echasnovski/mini.icons" },
  config = function()
    require("lualine").setup({
      options = {
        icons_enabled = true,
        globalstatus = false, -- disable, so lualine does not keep forcing status=3
        -- Read live intermediate colours, not lualine's disk-based pywal theme.
        theme = function()
          local c = vim.g
          return {
            normal = {
              a = { fg = c.background, bg = c.color4, gui = "bold" },
              b = { fg = c.foreground, bg = c.color8 },
              c = { fg = c.foreground, bg = c.background },
            },
            insert = { a = { fg = c.background, bg = c.color2, gui = "bold" } },
            visual = { a = { fg = c.background, bg = c.color3, gui = "bold" } },
            replace = { a = { fg = c.background, bg = c.color1, gui = "bold" } },
            -- fg = color8 like StatusLineNC: the separator line (fillchars) then looks the same,
            -- no matter whether lualine or tpipeline drew the line just now
            inactive = {
              a = { fg = c.color8, bg = c.background },
              b = { fg = c.color8, bg = c.background },
              c = { fg = c.color8, bg = c.background },
            },
          }
        end,
        component_separators = "",
        section_separators = "",
      },
      sections = {
        lualine_a = { "mode" },
        lualine_b = { "branch" },
        lualine_c = {},
        lualine_x = {},
        lualine_y = { "progress" },
        lualine_z = { "location" },
      },
      -- Inactive windows without content: the default would be file name + position. With splits
      -- (e.g. the run terminal) lualine draws that into the separator line, tpipeline clears it
      -- again -> the file name flickers. Empty, there is nothing to flicker.
      inactive_sections = {
        lualine_a = {}, lualine_b = {}, lualine_c = {},
        lualine_x = {}, lualine_y = {}, lualine_z = {},
      },
    })

    -- The "sledgehammer" at the end of the plugin configuration
    vim.api.nvim_create_autocmd("User", {
      pattern = "LazyVimStarted", -- waits until really EVERYTHING is ready
      callback = function()
        vim.opt.laststatus = 0
        vim.opt.cmdheight = 0
      end,
    })
  end,
}

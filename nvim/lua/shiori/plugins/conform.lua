-- ~/.config/nvim/lua/shiori/plugins/conform.lua --

-- Filetypes that are NOT formatted automatically on save (only with <space>cf, on/off for all: <space>tf).
-- sh/bash: shfmt would heavily rewrite existing scripts (e.g. blow up one-liners).
local no_format_on_save = { sh = true, bash = true }

return {
  {
    "stevearc/conform.nvim",
    event = "BufWritePre", -- Loaded before saving
    cmd = "ConformInfo",
    keys = {
      {
        "<leader>cf",
        function() require("conform").format({ async = true, lsp_format = "fallback" }) end,
        mode = { "n", "v" },
        desc = "Format code",
      },
      {
        "<leader>tf",
        function()
          vim.g.autoformat_off = not vim.g.autoformat_off
          vim.notify("Format on save: " .. (vim.g.autoformat_off and "OFF" or "ON"))
        end,
        desc = "Toggle format on save",
      },
    },
    opts = {
      formatters_by_ft = {
        qml = { "qmlformat" },
        rust = { "rustfmt" },
        python = { "ruff_format" },
        sh = { "shfmt" },
        bash = { "shfmt" },
        -- Everything else (C/C++, JS, CSS, HTML, Lua) is formatted by the respective language server
      },
      -- shfmt takes the indentation from shiftwidth (set to 4 for sh, see autocmds.lua)
      format_on_save = function(bufnr)
        if vim.g.autoformat_off or no_format_on_save[vim.bo[bufnr].filetype] then
          return
        end
        return { timeout_ms = 500, lsp_format = "fallback" }
      end,
    },
  },
}

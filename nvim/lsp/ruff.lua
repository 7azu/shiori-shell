-- ~/.config/nvim/lsp/ruff.lua --
-- Ruff as a linter for Python (finds e.g. unused imports/variables that pyright does not report).
-- Types, hover and completion are still done by pyright.

return {
  cmd = { "ruff", "server" },
  filetypes = { "python" },
  root_markers = { "pyproject.toml", "ruff.toml", ".ruff.toml", ".git" },
  on_attach = function(client)
    -- ruff leaves hover to pyright, otherwise there are double popups on K
    client.server_capabilities.hoverProvider = false
  end,
}

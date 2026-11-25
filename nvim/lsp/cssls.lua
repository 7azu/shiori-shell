-- ~/.config/nvim/lsp/cssls.lua --
-- Paket: vscode-css-languageserver

return {
  cmd = { "vscode-css-language-server", "--stdio" },
  filetypes = { "css", "scss", "less" },
  root_markers = { "package.json", ".git" },
  init_options = { provideFormatter = true },
  -- Without these settings the server does not validate (no error display)
  settings = {
    css = { validate = true },
    scss = { validate = true },
    less = { validate = true },
  },
}

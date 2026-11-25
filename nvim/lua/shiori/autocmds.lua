-- ~/.config/nvim/lua/shiori/autocmds.lua --

-- As soon as a language server attaches to a buffer
vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("ShioriLspAttach", { clear = true }),
  callback = function(event)
    local buf = event.buf
    local client = vim.lsp.get_client_by_id(event.data.client_id)

    -- gd: jump to the definition (the other LSP keys like grn, gra, grr, K are built into nvim)
    vim.keymap.set("n", "gd", vim.lsp.buf.definition, { buffer = buf, desc = "Go to definition" })

    -- Inlay hints: show inferred types/parameter names in gray in the code
    if client and client:supports_method("textDocument/inlayHint") then
      vim.lsp.inlay_hint.enable(true, { bufnr = buf })
      vim.keymap.set("n", "<leader>th", function()
        vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = buf }), { bufnr = buf })
      end, { buffer = buf, desc = "Toggle inlay hints" })
    end
  end,
})

-- Shell scripts: 4 spaces (otherwise 2 globally)
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("ShioriIndent", { clear = true }),
  pattern = { "sh", "bash" },
  callback = function()
    vim.bo.shiftwidth = 4
    vim.bo.tabstop = 4
  end,
})

-- Fetch inlay hints again when the server is done indexing.
-- Otherwise nvim only asks once right at the start (answer: empty) and only shows something after the first change.
vim.api.nvim_create_autocmd("LspProgress", {
  group = vim.api.nvim_create_augroup("ShioriInlayRefresh", { clear = true }),
  pattern = "end",
  callback = function(event)
    local client = vim.lsp.get_client_by_id(event.data.client_id)
    if not client then return end
    for buf in pairs(client.attached_buffers) do
      if vim.lsp.inlay_hint.is_enabled({ bufnr = buf }) then
        vim.lsp.inlay_hint.enable(false, { bufnr = buf })
        vim.lsp.inlay_hint.enable(true, { bufnr = buf })
      end
    end
  end,
})

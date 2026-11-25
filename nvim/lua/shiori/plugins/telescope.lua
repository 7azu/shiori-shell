-- ~/.config/nvim/lua/shiori/plugins/telescope.lua --

return {
  {
    'nvim-telescope/telescope.nvim',
    dependencies = {
      'nvim-lua/plenary.nvim',
      { 'nvim-telescope/telescope-fzf-native.nvim', build = 'make' }
    },
    config = function()
      local builtin = require('telescope.builtin')
      local actions = require('telescope.actions')

      -- The "defaults" are defined here
      require('telescope').setup({
        defaults = {
          mappings = {
            i = {
              ["<C-j>"] = actions.move_selection_next,
              ["<C-k>"] = actions.move_selection_previous,
            },
            n = {
              ["j"] = actions.move_selection_next,
              ["k"] = actions.move_selection_previous,
            },
          },
        },
      })

      -- Load the FZF extension (for faster searching)
      pcall(require('telescope').load_extension, 'fzf')

      -- Keymaps (which-key groups in plugins/which-key.lua, overview: <space>?)
      -- No plain <space>f, otherwise nvim waits for timeoutlen every time because of <space>fX
      local map = function(lhs, fn, desc) vim.keymap.set("n", lhs, fn, { desc = desc }) end
      local files_in = function(dir) return function() builtin.find_files({ cwd = dir }) end end

      -- <space>f: search
      map("<space>ff", builtin.find_files, "Files (nvim's current folder)")
      map("<space>f.", function() builtin.find_files({ cwd = vim.fn.expand("%:p:h") }) end, "Files in this file's folder")
      -- Projects folder from the setting folders.projects (~/.config/shiori-shell/settings.json); unset -> no key
      local projects = require("shiori.settings").folder("projects")
      if projects ~= "" then
        map("<space>fp", files_in(projects), "Files in the projects folder")
      end
      map("<space>fr", builtin.oldfiles, "Recently opened")
      map("<space>fg", builtin.live_grep, "Text in all files")
      map("<space>fb", builtin.buffers, "Open buffers")
      map("<space>fd", builtin.diagnostics, "All errors/warnings")
      map("<space>fo", builtin.lsp_document_symbols, "Symbols of the file (LSP)")
      map("<space>fk", builtin.keymaps, "Search keymaps")
      map("<space>fh", builtin.help_tags, "Search nvim help")

      -- <space>o: open the config folder
      map("<space>oc", files_in("~/.config"), "~/.config (everything)")
      map("<space>oh", files_in("~/.config/hypr/modules/"), "Hypr modules")
      map("<space>os", files_in("~/.config/hypr/scripts/"), "Hypr scripts")
      map("<space>oq", files_in("~/.config/quickshell/"), "Quickshell")
      map("<space>on", files_in(vim.fn.stdpath("config")), "nvim config")
    end
  }
}

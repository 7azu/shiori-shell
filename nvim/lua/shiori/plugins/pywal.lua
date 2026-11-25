-- Follow the same intermediate palette as Kitty and the wallpaper transition.
return {
  "AlphaTechnolog/pywal.nvim",
  name = "pywal",
  priority = 1000,
  lazy = false,
  config = function()
    local pywal = require("pywal")
    -- Explicit RGB backgrounds become opaque as Kitty's default background fades.
    -- Use the terminal background for editor surfaces, preserving selection colours.
    -- Separator line (fillchars stl/stlnc in options.lua) in color8. tpipeline fixes the
    -- status line to %#StatusLine#, so practically only StatusLine counts.
    -- nocombine for NC: looks the same, but counts as a different highlight for nvim,
    -- otherwise nvim fills the active window's line with '^' instead of the line.
    local function separator_hl(colors)
      vim.api.nvim_set_hl(0, "StatusLine", { fg = colors.color8, bg = colors.background })
      vim.api.nvim_set_hl(0, "StatusLineNC", { fg = colors.color8, bg = colors.background, nocombine = true })
    end
    local function terminal_background()
      for _, group in ipairs({
        "Normal", "NormalNC", "SignColumn", "MsgArea", "ModeMsg",
        "MsgSeparator", "FoldColumn", "LineNr", "EndOfBuffer", "NonText",
        "NormalFloat", "FloatBorder",
      }) do
        local hl = vim.api.nvim_get_hl(0, { name = group, link = false })
        hl.bg = nil
        hl.ctermbg = nil
        vim.api.nvim_set_hl(0, group, hl)
      end
      separator_hl(require("pywal.core").get_colors())
    end
    local group = vim.api.nvim_create_augroup("PywalTerminalBackground", { clear = true })
    vim.api.nvim_create_autocmd("ColorScheme", {
      group = group, pattern = "pywal", callback = terminal_background,
    })
    pywal.setup()
    vim.cmd.colorscheme("pywal")
    local uv = vim.uv or vim.loop
    local directory = vim.fn.expand("$HOME/.cache")
    if vim.env.XDG_CACHE_HOME then directory = vim.env.XDG_CACHE_HOME end
    directory = directory .. "/wal"
    local last_frame, last_update = nil, 0
    local generation = 0
    local current = require("pywal.core").get_colors()
    local function apply(colors)
      current = colors
      for key, value in pairs(colors) do vim.g[key] = value end
      -- Install only final highlight values. Setting Normal.bg even briefly can
      -- make tmux/Kitty paint an opaque frame before the transparency override.
      local transparent = {
        Normal = true, NormalNC = true, SignColumn = true, MsgArea = true,
        ModeMsg = true, MsgSeparator = true, FoldColumn = true, LineNr = true,
        EndOfBuffer = true, NonText = true, NormalFloat = true, FloatBorder = true,
      }
      for name, hl in pairs(require("pywal.config").highlights_base(colors)) do
        if transparent[name] then hl.bg = nil; hl.ctermbg = nil end
        vim.api.nvim_set_hl(0, name, hl)
      end
      separator_hl(colors)
      -- Recolour existing statusline groups without rebuilding lualine and
      -- firing every plugin's ColorScheme handlers on every animation frame.
      local lualine = package.loaded["lualine"]
      if lualine then
        local theme = lualine.get_config().options.theme
        if type(theme) == "function" then
          local highlight = require("lualine.highlight")
          for mode, sections in pairs(theme()) do
            for section, hl in pairs(sections) do
              highlight.highlight("lualine_" .. section .. "_" .. mode, hl.fg, hl.bg, hl.gui)
            end
          end
          lualine.refresh({ place = { "statusline" }, trigger = "pywal" })
        end
      end
      if vim.g.loaded_tpipeline then pcall(vim.fn["tpipeline#update"]) end
      vim.cmd("redraw")
    end
    local function fade_to(target)
      generation = generation + 1
      local token, start = generation, current
      local function step(n)
        if token ~= generation then return end
        local colors = {}
        for key, value in pairs(target) do
          local old = start[key] or value
          local channels = {}
          for offset = 2, 6, 2 do
            local a = tonumber(old:sub(offset, offset + 1), 16)
            local b = tonumber(value:sub(offset, offset + 1), 16)
            channels[#channels + 1] = math.floor(a + (b - a) * n / 12 + 0.5)
          end
          colors[key] = string.format("#%02x%02x%02x", unpack(channels))
        end
        apply(colors)
        if n < 12 then vim.defer_fn(function() step(n + 1) end, 50) end
      end
      step(1)
    end
    local function update()
      local file = io.open(directory .. "/terminal-frame", "r")
      if not file then return end
      local line = file:read("*l")
      file:close()
      if not line or line == last_frame then return end
      local colors, count = {}, 0
      for color in line:gmatch("%S+") do
        if not color:match("^#%x%x%x%x%x%x$") then return end
        colors["color" .. count] = color
        count = count + 1
      end
      if count ~= 16 then return end
      last_frame, last_update = line, uv.now()
      colors.background, colors.foreground, colors.cursor = colors.color0, colors.color15, colors.color15
      generation = generation + 1
      apply(colors)
    end
    -- Poll the current path: atomic replacement or a replaced cache directory must
    -- not detach the receiver from future frames. Duplicate frames are ignored.
    local watcher = uv.new_timer()
    watcher:start(0, 40, vim.schedule_wrap(update))
    local signal = uv.new_signal()
    signal:start("sigusr1", function()
      vim.schedule(function()
        -- wal can finish during the animation: do not jump ahead of its frames.
        update()
        local target = require("pywal.core").get_colors()
        local matches = true
        for i = 0, 15 do
          local key = "color" .. i
          if current[key]:lower() ~= target[key]:lower() then matches = false end
        end
        if matches or uv.now() - last_update < 2000 then return end
        fade_to(target)
      end)
    end)
    vim.api.nvim_create_autocmd("VimLeavePre", { once = true, callback = function()
      watcher:stop()
      watcher:close()
      signal:stop()
      signal:close()
    end })
  end,
}

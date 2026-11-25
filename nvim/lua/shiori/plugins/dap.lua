-- ~/.config/nvim/lua/shiori/plugins/dap.lua --
-- Debugger for C, C++ and Rust.
-- Uses lldb-dap (package: lldb) if installed: then input (cin/scanf) works too.
-- Otherwise gdb (cannot pass input to the program).

-- Compiles the current file with debug info and returns the path to the program
local function build_for_debug()
  local dap = require("dap")
  vim.cmd("silent! write")

  local file = vim.api.nvim_buf_get_name(0)
  local dir = vim.fn.fnamemodify(file, ":p:h")
  local ft = vim.bo.filetype
  local cmd, program, cwd

  if ft == "c" or ft == "cpp" then
    local compiler = ft == "c" and { "gcc", "-std=c17" } or { "g++", "-std=c++20" }
    program = dir .. "/" .. vim.fn.fnamemodify(file, ":t:r")
    cmd = vim.list_extend(compiler, { "-g", "-O0", "-Wall", "-Wextra", file, "-o", program })
    cwd = dir
  elseif ft == "rust" then
    local root = vim.fs.root(file, "Cargo.toml")
    if root then
      -- Read the package name from Cargo.toml -> target/debug/<name>
      local name
      for line in io.lines(root .. "/Cargo.toml") do
        name = name or line:match('^name%s*=%s*"(.-)"')
      end
      cmd, program, cwd = { "cargo", "build" }, root .. "/target/debug/" .. (name or ""), root
    else
      program = dir .. "/" .. vim.fn.fnamemodify(file, ":t:r")
      cmd, cwd = { "rustc", "-g", file, "-o", program }, dir
    end
  else
    vim.notify("Debugging only works for C, C++ and Rust", vim.log.levels.WARN)
    return dap.ABORT
  end

  local result = vim.system(cmd, { cwd = cwd, text = true }):wait()
  if result.code ~= 0 then
    vim.notify("Compiling failed:\n" .. (result.stderr or ""), vim.log.levels.ERROR)
    return dap.ABORT
  end
  return program
end

return {
  "mfussenegger/nvim-dap",
  dependencies = {
    "rcarriga/nvim-dap-ui",
    "nvim-neotest/nvim-nio",
  },
  keys = {
    { "<F5>", function() require("dap").continue() end, desc = "Debug: start / continue" },
    { "<F10>", function() require("dap").step_over() end, desc = "Debug: next line" },
    { "<F11>", function() require("dap").step_into() end, desc = "Debug: step into" },
    { "<F12>", function() require("dap").step_out() end, desc = "Debug: step out" },
    { "<leader>db", function() require("dap").toggle_breakpoint() end, desc = "Toggle breakpoint" },
    { "<leader>dc", function() require("dap").continue() end, desc = "Start / continue (F5)" },
    { "<leader>dn", function() require("dap").step_over() end, desc = "Next line (F10)" },
    { "<leader>di", function() require("dap").step_into() end, desc = "Step into (F11)" },
    { "<leader>do", function() require("dap").step_out() end, desc = "Step out (F12)" },
    { "<leader>dr", function() require("dap").run_to_cursor() end, desc = "Run to cursor" },
    { "<leader>dq", function() require("dap").terminate(); require("dapui").close() end, desc = "Stop debugging" },
    { "<leader>td", function() require("dapui").toggle() end, desc = "Toggle debug windows" },
    { "<leader>de", function() require("dapui").eval() end, mode = { "n", "v" }, desc = "Show value under cursor" },
  },
  config = function()
    local dap, dapui = require("dap"), require("dapui")
    dapui.setup()

    -- Open the windows automatically at start. Do not close them automatically,
    -- so the output can still be read at the end (close: <space>td / <space>dq).
    dap.listeners.before.launch.shiori = function() dapui.open() end
    dap.listeners.before.attach.shiori = function() dapui.open() end

    -- Signs in the signcolumn
    vim.fn.sign_define("DapBreakpoint", { text = "●", texthl = "DiagnosticError" })
    vim.fn.sign_define("DapStopped", { text = "→", texthl = "DiagnosticWarn", linehl = "Visual" })

    local config
    if vim.fn.executable("lldb-dap") == 1 then
      dap.adapters.lldb = { type = "executable", command = vim.fn.exepath("lldb-dap"), name = "lldb" }
      config = {
        name = "Debug current file (lldb)",
        type = "lldb",
        request = "launch",
        program = build_for_debug,
        cwd = "${fileDirname}",
        stopOnEntry = false,
        runInTerminal = true, -- own terminal, so cin/scanf work
      }
    else
      dap.adapters.gdb = {
        type = "executable",
        command = "gdb",
        args = { "--interpreter=dap", "--eval-command", "set print pretty on" },
      }
      config = {
        name = "Debug current file (gdb)",
        type = "gdb",
        request = "launch",
        program = build_for_debug,
        cwd = "${fileDirname}",
        stopAtBeginningOfMainSubprogram = false,
      }
    end
    dap.configurations.c = { config }
    dap.configurations.cpp = { config }
    dap.configurations.rust = { config }
  end,
}

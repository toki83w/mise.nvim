local config = require("mise.config")
local runner = require("mise.runner")

local M = {}

---Setup mise.nvim with user options.
---@param opts MiseOpts|nil
function M.setup(opts)
  config.setup(opts)
  local lhs = config.options.help_keymap
  if lhs and lhs ~= "" then
    require("mise.help").setup_keymap(lhs)
  end
end

---Run a mise task.
---@param task string Task name
---@param args string[] Extra arguments forwarded after `--`
function M.run(task, args)
  if not task or task == "" then
    vim.notify("mise.nvim: task name is required.", vim.log.levels.WARN)
    return
  end
  runner.run(task, args or {})
end

---Toggle the mise terminal instance.
function M.toggle()
  runner.toggle()
end

---Open the MisePick telescope picker.
function M.pick()
  require("mise.picker").pick()
end

return M

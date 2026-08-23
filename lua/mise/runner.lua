local config = require("mise.config")

local M = {}

--- Last run task and args, for :MiseRunLast.
---@type { task: string, args: string[] }|nil
local last_run = nil

---Build the shell command string for `mise run`.
---@param task string Task name
---@param args string[] Extra arguments forwarded to the task
---@return string
local function build_cmd(task, args)
  local parts = { "mise", "run", task }
  if args and #args > 0 then
    vim.list_extend(parts, args)
  end
  return table.concat(parts, " ")
end

---Run a mise task in a toggleterm terminal.
---@param task string Task name
---@param args string[] Extra arguments
function M.run(task, args)
  local ok, toggleterm = pcall(require, "toggleterm.terminal")
  if not ok then
    vim.notify(
      "mise.nvim: toggleterm.nvim is required but not found.",
      vim.log.levels.ERROR
    )
    return
  end

  last_run = { task = task, args = args or {} }
  local cmd = build_cmd(task, args)
  local opts = config.options.toggleterm

  -- Re-use the same terminal instance across multiple runs so the user can
  -- toggle it with the standard toggleterm keybind.
  local term = toggleterm.Terminal:new({
    cmd = cmd,
    count = opts.count,
    direction = opts.direction,
    auto_scroll = opts.auto_scroll,
    close_on_exit = opts.close_on_exit,
    quit_on_exit = opts.quit_on_exit,
    hidden = opts.hidden,
    use_shell = opts.use_shell,
    keep_after_exit = opts.keep_after_exit,
    start_in_insert = opts.start_in_insert,
    -- Notify user when a new task replaces the previous one
    on_open = function(t)
      if opts.start_in_insert then
        vim.cmd("startinsert!")
      end
    end,
  })

  if opts.open_on_start then
    term:open()
  else
    term:spawn()
  end
end

---Re-run the last task with the same arguments.
function M.run_last()
  if not last_run then
    vim.notify("mise.nvim: no task has been run yet.", vim.log.levels.WARN)
    return
  end
  M.run(last_run.task, last_run.args)
end

---Toggle the configured mise terminal instance.
---If a task has never been run the terminal won't exist yet; notify the user.
function M.toggle()
  local ok, toggleterm = pcall(require, "toggleterm.terminal")
  if not ok then
    vim.notify(
      "mise.nvim: toggleterm.nvim is required but not found.",
      vim.log.levels.ERROR
    )
    return
  end

  local opts = config.options.toggleterm
  local term = toggleterm.get(opts.count)
  if not term then
    vim.notify(
      "mise.nvim: no terminal found (run a task with :MiseRun first).",
      vim.log.levels.WARN
    )
    return
  end
  term:toggle()
end

return M

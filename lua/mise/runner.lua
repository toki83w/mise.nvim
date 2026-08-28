local config = require("mise.config")
local state  = require("mise.state")

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

  -- If a terminal already exists for our count, kill any running process and
  -- tear it down so the new Terminal:new() below gets a clean slate.
  local existing = toggleterm.get(opts.count)
  if existing then
    if not existing.exited and existing.job_id then
      vim.fn.jobstop(existing.job_id)
    end
    existing:shutdown()
  end

  state.task   = task
  state.status = "running"

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
    on_open = function(t)
      t:scroll_bottom()
    end,
    on_exit = function(_, _, exit_code)
      state.status = exit_code == 0 and "success" or "failure"
    end,
  })

  -- Reset to idle when the terminal buffer is wiped (e.g. manually closed).
  local function on_buf_wipeout()
    if state.task == task then
      state.task   = nil
      state.status = "idle"
    end
  end

  -- The bufnr is assigned during spawn/open, so we defer the autocmd setup.
  vim.schedule(function()
    local t = toggleterm.get(opts.count)
    if t and t.bufnr and vim.api.nvim_buf_is_valid(t.bufnr) then
      vim.api.nvim_create_autocmd("BufWipeout", {
        buffer  = t.bufnr,
        once    = true,
        callback = on_buf_wipeout,
      })
    end
  end)

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

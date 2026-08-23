-- plugin/mise.lua  – loaded automatically by Neovim's runtime
if vim.g.loaded_mise then
  return
end
vim.g.loaded_mise = true

-- Lazy-load the heavy setup; the user calls require("mise").setup({}) in their
-- config.  We only register the user commands here.

---Parse the raw fargs list: first element is the task name, the rest are
---forwarded verbatim to the task after a "--" separator.
---@param fargs string[]
---@return string task, string[] args
local function parse_args(fargs)
  local task = fargs[1] or ""
  local args = {}
  for i = 2, #fargs do
    args[#args + 1] = fargs[i]
  end
  return task, args
end

-- ---------------------------------------------------------------------------
-- Completion helpers
-- ---------------------------------------------------------------------------

---Return parsed MiseArg list for a task from the JSON cache.
---@param task string
---@return MiseArg[]
local function get_task_args(task)
  local tasks_mod = require("mise.tasks")
  for _, t in ipairs(tasks_mod.fetch_sync()) do
    if t.name == task then
      return tasks_mod.parse_usage(t.usage or "")
    end
  end
  return {}
end

---Parse the command line to determine:
---  1. The task name (first argument after the command).
---  2. How many whitespace-separated tokens precede the current incomplete word.
---@param cmd_line string
---@param arg_lead string
---@return string task, integer completed_count, string|nil prev_token
local function parse_cmd_line(cmd_line, arg_lead)
  local rest = cmd_line:match("^%s*%S+%s+(.*)") or ""
  local before_lead = rest:sub(1, #rest - #arg_lead)
  local tokens = {}
  for tok in before_lead:gmatch("%S+") do
    tokens[#tokens + 1] = tok
  end
  local task = tokens[1] or ""
  local prev_token = tokens[#tokens]  -- token immediately before arg_lead
  return task, #tokens, prev_token
end

---Unified completion function for :MiseRun.
---  - Position 1 (task name): complete from `mise tasks --json`.
---  - Position >= 2, previous token is a value flag with choices: complete choices.
---  - Position >= 2, otherwise: complete --flags.
---@param arg_lead string
---@param cmd_line string
---@return string[]
local function complete_mise_run(arg_lead, cmd_line)
  local task, completed_count, prev_token = parse_cmd_line(cmd_line, arg_lead)

  -- ── First argument: task name ──────────────────────────────────────────
  if completed_count == 0 then
    local result = vim.fn.systemlist("mise tasks --no-header 2>/dev/null")
    local tasks = {}
    for _, line in ipairs(result) do
      local name = line:match("^%s*(%S+)")
      if name and vim.startswith(name, arg_lead) then
        tasks[#tasks + 1] = name
      end
    end
    return tasks
  end

  if task == "" then return {} end

  local args = get_task_args(task)
  if #args == 0 then return {} end

  -- ── Previous token is a value flag with choices: complete the value ────
  if prev_token then
    for _, arg in ipairs(args) do
      if not arg.is_bool and #arg.choices > 0 and arg.flag == prev_token then
        local matches = {}
        for _, choice in ipairs(arg.choices) do
          if vim.startswith(choice, arg_lead) then
            matches[#matches + 1] = choice
          end
        end
        return matches
      end
    end
  end

  -- ── Otherwise: complete flag names ────────────────────────────────────
  local matches = {}
  for _, arg in ipairs(args) do
    if vim.startswith(arg.flag, arg_lead) then
      matches[#matches + 1] = arg.flag
    end
  end
  return matches
end

-- ---------------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------------

vim.api.nvim_create_user_command("MiseRun", function(opts)
  local task, args = parse_args(opts.fargs)
  require("mise").run(task, args)
end, {
  nargs = "+",
  desc = "Run a mise task in a toggleterm terminal",
  complete = complete_mise_run,
})

vim.api.nvim_create_user_command("MiseToggleTerm", function()
  require("mise").toggle()
end, {
  nargs = 0,
  desc = "Toggle the mise toggleterm terminal instance",
})

vim.api.nvim_create_user_command("MisePick", function()
  require("mise").pick()
end, {
  nargs = 0,
  desc = "Open the mise task picker",
})



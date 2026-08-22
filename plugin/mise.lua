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

---Task name completion: calls `mise tasks` and returns matching task names.
---Only completes the first argument (the task name); subsequent arguments are
---passed through to the task itself so we leave them unconstrained.
---@param arg_lead string Current word being typed
---@param cmd_line string Full command line so far
---@return string[]
local function complete_tasks(arg_lead, cmd_line)
  -- Count how many space-separated tokens precede the cursor in the command
  -- line (excluding the command name itself).  If there is already one
  -- completed token before arg_lead we are on argument ≥ 2 and should not
  -- offer task completions.
  local cmd_name, rest = cmd_line:match("^%s*(%S+)%s+(.*)")
  if not rest then
    return {}
  end
  -- Strip the currently-typed (incomplete) word from the end so we can count
  -- how many arguments are already complete.
  local before_lead = rest:sub(1, #rest - #arg_lead)
  local completed_args = 0
  for _ in before_lead:gmatch("%S+") do
    completed_args = completed_args + 1
  end
  -- Only complete the first argument (the task name).
  if completed_args >= 1 then
    return {}
  end

  local result = vim.fn.systemlist("mise tasks --no-header 2>/dev/null")
  local tasks = {}
  for _, line in ipairs(result) do
    -- Each line looks like:  "build   Build the project"
    -- We only want the first whitespace-delimited token.
    local name = line:match("^%s*(%S+)")
    if name and vim.startswith(name, arg_lead) then
      tasks[#tasks + 1] = name
    end
  end
  return tasks
end

vim.api.nvim_create_user_command("MiseRun", function(opts)
  local task, args = parse_args(opts.fargs)
  require("mise").run(task, args)
end, {
  nargs = "+",
  desc = "Run a mise task in a toggleterm terminal",
  complete = complete_tasks,
})

vim.api.nvim_create_user_command("MiseToggleTerm", function()
  require("mise").toggle()
end, {
  nargs = 0,
  desc = "Toggle the mise toggleterm terminal instance",
})

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

--- Cache of task-name → list of --flag strings parsed from `mise run <task> --help`.
--- A sentinel value of `false` means we already tried and found nothing.
---@type table<string, string[]|false>
local task_args_cache = {}

---Extract --flag / -f style arguments from a help text string.
---
---Only scans lines where a flag token (-x or --word) appears as the first
---non-whitespace content.  This avoids picking up single letters from prose,
---example values, or descriptions.
---
---Handles common help formats:
---  "  -b --build-type [type]   Build type"   → -b, --build-type
---  "  --tests                  Build tests"  → --tests
---  "  -u, --update             Check …"      → -u, --update
---
---@param text string Raw stdout/stderr from `mise run <task> -- --help`
---@return string[]
local function parse_flags_from_help(text)
  local seen = {}
  local flags = {}

  for line in text:gmatch("[^\n]+") do
    -- A flag line: leading whitespace, then immediately a "-"
    if line:match("^%s+%-") or line:match("^%-") then
      -- Extract every -x and --word token from this line.
      -- Stop collecting once we hit the description text: we consider the
      -- description to start at the first token that is NOT a flag or a
      -- meta-variable (all-caps word, bracketed word, or comma).
      for token in line:gmatch("%S+") do
        local long  = token:match("^(%-%-[%w][%w%-]*)") -- --flag or --flag-name
        local short = token:match("^(-[%a%d])$")        -- -x (exactly one char)
        local flag  = long or short
        if flag then
          if not seen[flag] then
            seen[flag] = true
            flags[#flags + 1] = flag
          end
        elseif not token:match("^[%[%(<]")   -- meta-var: [TYPE], <TYPE>, (TYPE)
            and not token:match("^[A-Z_]+$")  -- meta-var: TYPE, BUILD_TYPE
            and not token:match("^,$")        -- separator comma
        then
          -- First non-flag, non-meta token → description starts, stop this line
          break
        end
      end
    end
  end

  return flags
end

---Fetch and cache the flags for a task by running `mise run <task> -- -h`.
---Returns the cached list (possibly empty) on subsequent calls.
---@param task string
---@return string[]
local function get_task_flags(task)
  if task_args_cache[task] ~= nil then
    return task_args_cache[task] or {}
  end

  -- `mise run <task> -h` prints the task's usage (handled by mise itself).
  local output = vim.fn.system(
    string.format("mise run %s -h 2>&1", vim.fn.shellescape(task))
  )

  local flags = parse_flags_from_help(output)
  task_args_cache[task] = #flags > 0 and flags or false
  return flags
end

---Parse the command line to determine:
---  1. The task name (first argument after the command).
---  2. How many whitespace-separated tokens sit between the command and the
---     current incomplete word (arg_lead).
---@param cmd_line string
---@param arg_lead string
---@return string task, integer completed_count
local function parse_cmd_line(cmd_line, arg_lead)
  -- Strip the Vim command name from the front.
  local rest = cmd_line:match("^%s*%S+%s+(.*)") or ""
  -- Remove the trailing incomplete word so we can count completed tokens.
  local before_lead = rest:sub(1, #rest - #arg_lead)
  local tokens = {}
  for tok in before_lead:gmatch("%S+") do
    tokens[#tokens + 1] = tok
  end
  local task = tokens[1] or ""
  return task, #tokens
end

---Unified completion function for :MiseRun.
---  - Position 1 (task name): complete from `mise tasks`.
---  - Position ≥ 2 (task args): complete --flags from `mise run <task> --help`.
---@param arg_lead string
---@param cmd_line string
---@return string[]
local function complete_mise_run(arg_lead, cmd_line)
  local task, completed_count = parse_cmd_line(cmd_line, arg_lead)

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

  -- ── Subsequent arguments: flags from --help ────────────────────────────
  -- Only offer flag completions when the user has started typing "--".
  if task == "" then
    return {}
  end
  local flags = get_task_flags(task)
  if #flags == 0 then
    return {}
  end
  local matches = {}
  for _, flag in ipairs(flags) do
    if vim.startswith(flag, arg_lead) then
      matches[#matches + 1] = flag
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

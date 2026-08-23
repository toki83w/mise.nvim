--- lua/mise/help.lua
--- Floating help popup for :MiseRun – triggered by <C-h> in cmdline mode.
---
--- Pressing <C-h> while the cmdline reads `:MiseRun <task> ...` fetches
--- `mise run <task> -h` asynchronously and shows the output in a centered
--- floating window.  Pressing <C-h> again with a different task name
--- refreshes the same window in place.  The window closes automatically
--- when cmdline mode ends.

local M = {}

--- Raw help text cache: task name -> string (raw output) or false (tried, empty).
---@type table<string, string|false>
local raw_cache = {}

--- Return the cached raw help text for a task, or nil if not yet fetched.
---@param task string
---@return string|false|nil
function M.get_cached_raw(task)
  return raw_cache[task]
end

--- Fetch raw help text for a task synchronously and cache it.
--- Used by the completion helper which runs synchronously.
---@param task string
---@return string
function M.fetch_raw_sync(task)
  if raw_cache[task] ~= nil then
    return raw_cache[task] or ""
  end
  local output = vim.fn.system(
    string.format("mise run %s -h 2>&1", vim.fn.shellescape(task))
  )
  raw_cache[task] = (output and output ~= "") and output or false
  return output or ""
end

---@class MiseHelpState
---@field win integer|nil   Window handle (nil when closed)
---@field buf integer|nil   Buffer handle
---@field task string|nil   Task whose help is currently shown
---@field job any|nil       Running vim.system handle (for cancellation)
local state = {
  win  = nil,
  buf  = nil,
  task = nil,
  job  = nil,
}

--- Close the popup and reset state.
local function close()
  if state.job then
    state.job:kill(9)
    state.job = nil
  end
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.api.nvim_buf_delete(state.buf, { force = true })
  end
  state.win  = nil
  state.buf  = nil
  state.task = nil
end

--- Compute floating window dimensions and position.
---@param lines string[]
---@return vim.api.keyset.win_config
local function win_config(lines)
  local max_line = 0
  for _, l in ipairs(lines) do
    max_line = math.max(max_line, #l)
  end
  local width  = math.max(40, math.min(max_line + 2, vim.o.columns - 6))
  local height = math.min(#lines, vim.o.lines - 6)
  return {
    relative = "editor",
    width    = width,
    height   = height,
    row      = math.floor((vim.o.lines   - height) / 2),
    col      = math.floor((vim.o.columns - width)  / 2),
    style    = "minimal",
    border   = "rounded",
  }
end

--- Populate buf with lines, (re)creating the float if needed, then redraw.
---@param task string
---@param lines string[]
local function show(task, lines)
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    state.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.buf].bufhidden = "wipe"
    vim.bo[state.buf].filetype  = "text"
    vim.keymap.set("n", "q", close, { buffer = state.buf, nowait = true })
  end

  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)

  local cfg = win_config(lines)
  cfg.title     = string.format(" mise run %s -h ", task)
  cfg.title_pos = "center"

  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_config(state.win, cfg)
  else
    state.win = vim.api.nvim_open_win(state.buf, false, cfg)
    vim.wo[state.win].wrap       = false
    vim.wo[state.win].cursorline = true
    vim.wo[state.win].number     = false
  end

  -- Force a repaint so the float is visible while cmdline is still open.
  vim.cmd("redraw")
  state.task = task
end

--- Extract the task name from the current cmdline string.
---@param cmdline string
---@return string|nil
local function task_from_cmdline(cmdline)
  return cmdline:match("^%s*MiseRun%s+(%S+)")
end

--- Trigger the help popup.  Call this from a <C-h> cmdline mapping.
function M.show_for_cmdline()
  local cmdline = vim.fn.getcmdline()
  local task = task_from_cmdline(cmdline)

  if not task then
    close()
    return
  end

  -- Same task already showing – nothing to do.
  if task == state.task and state.win and vim.api.nvim_win_is_valid(state.win) then
    return
  end

  -- Cancel any in-flight request for a previous task.
  if state.job then
    state.job:kill(9)
    state.job = nil
  end

  -- If we already have cached raw text, show it immediately – no fetch needed.
  local cached = raw_cache[task]
  if cached ~= nil then
    local lines = vim.split(cached or "(no help output)", "\n", { plain = true })
    while #lines > 0 and lines[#lines]:match("^%s*$") do lines[#lines] = nil end
    if #lines == 0 then lines = { "(no help output)" } end
    show(task, lines)
    return
  end

  -- Show a loading placeholder immediately for visual feedback.
  show(task, { "Loading help for '" .. task .. "'..." })

  state.job = vim.system(
    { "mise", "run", task, "-h" },
    { text = true },
    function(result)
      state.job = nil
      -- Populate the shared cache so completion can reuse it.
      local raw = (result.stdout or "") .. (result.stderr or "")
      raw_cache[task] = (raw ~= "") and raw or false
      vim.schedule(function()
        -- User may have left cmdline while we were waiting.
        if not state.win or not vim.api.nvim_win_is_valid(state.win) then
          return
        end
        local lines = vim.split(raw, "\n", { plain = true })
        while #lines > 0 and lines[#lines]:match("^%s*$") do
          lines[#lines] = nil
        end
        if #lines == 0 then
          lines = { "(no help output)" }
        end
        show(task, lines)
      end)
    end
  )
end

--- Register the <C-h> mapping and auto-close on CmdlineLeave.
--- Called once from setup().
---@param lhs string Keymap lhs, e.g. "<C-h>"
function M.setup_keymap(lhs)
  vim.keymap.set("c", lhs, function()
    M.show_for_cmdline()
  end, {
    silent = true,
    desc   = "Show mise task help popup",
  })

  -- Close the popup whenever the user leaves cmdline (Enter, Esc, <C-c>...).
  -- vim.schedule defers past the CmdlineLeave event to avoid E565.
  vim.api.nvim_create_autocmd("CmdlineLeave", {
    group    = vim.api.nvim_create_augroup("MiseHelpPopup", { clear = true }),
    callback = function() vim.schedule(close) end,
  })
end

return M

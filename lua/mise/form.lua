--- lua/mise/form.lua
--- Floating argument form for a mise task.
---
--- Layout:
---   ┌─ task-name ─────────────────────────────┐
---   │                                         │
---   │  --build-type   [RelWithDebInfo       ]  │
---   │  --tests        [ ]                      │
---   │  --update       [ ]                      │
---   │                                          │
---   │  [Run]                       Esc: cancel │
---   └─────────────────────────────────────────┘
---
--- Keymaps (normal mode):
---   j / k        move between rows
---   <Space>      toggle boolean / open input for value flags
---   <CR>         same as <Space> on arg rows; confirm on [Run]
---   <Tab>        cycle choices forward  (value flags with choices)
---   <S-Tab>      cycle choices backward
---   <Esc>        cancel and close

local M = {}

local COL_FLAG  = 3   -- left margin for flag column
local COL_VALUE = 20  -- left edge of value widget

--- Build the display lines for the form.
---@param task_name string
---@param args MiseArg[]
---@param values table<string,string>   current values keyed by arg.key
---@param cursor_row integer            1-based index into args (not line index)
---@return string[] lines
---@return integer[] arg_lines   1-based line numbers where each arg sits
---@return integer run_line      1-based line number of the [Run] row
local function build_lines(task_name, args, values, _cursor_row)
  -- Measure flag column width.
  local flag_w = 0
  for _, arg in ipairs(args) do
    flag_w = math.max(flag_w, #arg.flag)
  end

  local val_w = 30  -- width of value widget (bool widgets are padded to match)

  local lines = { "" }  -- leading blank line

  local arg_lines = {}

  for _, arg in ipairs(args) do
    local val = values[arg.key]
    local widget
    if arg.is_bool then
      local toggle = val == "true" and "[x]" or "[ ]"
      -- Pad bool widget to val_w so help text starts at the same column.
      widget = toggle .. string.rep(" ", val_w - #toggle)
    else
      local display = val or ""
      -- Pad/truncate to val_w - 2 (inside brackets)
      local inner = val_w - 2
      if #display > inner then
        display = display:sub(1, inner)
      end
      widget = "[" .. display .. string.rep(" ", inner - #display) .. "]"
    end

    -- Build the line: flag_name padded, then widget.
    local flag_padded = arg.flag .. string.rep(" ", flag_w - #arg.flag)
    local line = string.rep(" ", COL_FLAG - 1)
      .. flag_padded
      .. string.rep(" ", COL_VALUE - COL_FLAG - flag_w)
      .. widget

    -- Append help text dimly (no highlight here, handled via extmarks).
    if arg.help ~= "" then
      line = line .. "   " .. arg.help
    end

    arg_lines[#arg_lines + 1] = #lines + 1
    lines[#lines + 1] = line
  end

  -- Blank line before Run.
  lines[#lines + 1] = ""

  -- [Run] row.
  local run_line = #lines + 1
  lines[#lines + 1] = string.rep(" ", COL_FLAG - 1) .. "[Run]"

  -- Trailing blank + hint.
  lines[#lines + 1] = ""
  lines[#lines + 1] = string.rep(" ", COL_FLAG - 1) .. "j/k: move  Space/Enter: edit  Esc: cancel"

  return lines, arg_lines, run_line
end

--- Compute float dimensions.
---@param lines string[]
---@return table win_cfg
local function win_cfg(lines, title)
  local max_w = 0
  for _, l in ipairs(lines) do max_w = math.max(max_w, #l) end
  local width  = math.max(60, math.min(max_w + 4, vim.o.columns - 8))
  local height = math.min(#lines + 2, vim.o.lines - 6)
  return {
    relative  = "editor",
    width     = width,
    height    = height,
    row       = math.floor((vim.o.lines   - height) / 2),
    col       = math.floor((vim.o.columns - width)  / 2),
    style     = "minimal",
    border    = "rounded",
    title     = " " .. title .. " ",
    title_pos = "center",
    zindex    = 50,
  }
end

--- Apply highlights: dim help text, highlight selected row, mark required+empty.
---@param buf integer
---@param args MiseArg[]
---@param values table<string,string>
---@param arg_lines integer[]
---@param run_line integer
---@param cursor_row integer  index into args, or #args+1 for Run
local function apply_hl(buf, args, values, arg_lines, run_line, cursor_row)
  vim.api.nvim_buf_clear_namespace(buf, -1, 0, -1)
  local ns = vim.api.nvim_create_namespace("MiseForm")

  for i, arg in ipairs(args) do
    local lnum = arg_lines[i] - 1  -- 0-based

    -- Highlight the selected row.
    if i == cursor_row then
      vim.api.nvim_buf_add_highlight(buf, ns, "CursorLine", lnum, 0, -1)
    end

    -- Highlight required+empty fields.
    if arg.required and (not values[arg.key] or values[arg.key] == "") then
      vim.api.nvim_buf_add_highlight(buf, ns, "DiagnosticError", lnum, 0, -1)
    end
  end

  -- Highlight [Run] row.
  local run_lnum = run_line - 1
  if cursor_row == #args + 1 then
    vim.api.nvim_buf_add_highlight(buf, ns, "CursorLine", run_lnum, 0, -1)
  end
  -- Always bold the [Run] text.
  local run_col = COL_FLAG - 1
  vim.api.nvim_buf_add_highlight(buf, ns, "Special", run_lnum, run_col, run_col + 5)
end

--- Open the argument form for a task.
---@param task_name string
---@param args MiseArg[]
---@param on_run fun(args_list: string[])  called with assembled CLI args
function M.open(task_name, args, on_run)
  -- Initialise values from defaults.
  ---@type table<string,string>
  local values = {}
  for _, arg in ipairs(args) do
    if arg.is_bool then
      values[arg.key] = "false"
    else
      values[arg.key] = arg.default or ""
    end
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = false

  -- cursor_row: 1..#args = on an arg, #args+1 = on [Run]
  local cursor_row = #args > 0 and 1 or (#args + 1)

  local win

  local function redraw()
    local lines, arg_lines, run_line = build_lines(task_name, args, values, cursor_row)
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    apply_hl(buf, args, values, arg_lines, run_line, cursor_row)

    -- Position Neovim's cursor on the right line for visual consistency.
    if vim.api.nvim_win_is_valid(win) then
      local target_line
      if cursor_row <= #args then
        target_line = arg_lines[cursor_row]
      else
        target_line = run_line
      end
      vim.api.nvim_win_set_cursor(win, { target_line, COL_FLAG - 1 })
    end
  end

  --- Assemble CLI args list from current values and call on_run.
  local function do_run()
    -- Validate required fields.
    for _, arg in ipairs(args) do
      if arg.required and (not values[arg.key] or values[arg.key] == "") then
        vim.notify(
          string.format("mise.nvim: %s is required", arg.flag),
          vim.log.levels.WARN
        )
        return
      end
    end

    local cli = {}
    for _, arg in ipairs(args) do
      local v = values[arg.key]
      if arg.is_bool then
        if v == "true" then
          cli[#cli + 1] = arg.flag
        end
      else
        if v and v ~= "" then
          cli[#cli + 1] = arg.flag
          cli[#cli + 1] = v
        end
      end
    end

    -- Close before running so the terminal can take the full screen.
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    on_run(cli)
  end

  --- Edit a value flag: open vim.ui.input with current value as default.
  local function edit_value(arg)
    vim.ui.input({
      prompt  = arg.flag .. ": ",
      default = values[arg.key] or "",
      completion = #arg.choices > 0
        and ("customlist,v:lua.require'mise.form'._choices_for_" .. arg.key)
        or nil,
    }, function(input)
      if input ~= nil then
        values[arg.key] = input
      end
      -- Re-focus the form window after input closes.
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_set_current_win(win)
        redraw()
      end
    end)
  end

  --- Cycle through choices for a value arg.
  ---@param arg MiseArg
  ---@param dir integer +1 forward, -1 backward
  local function cycle_choice(arg, dir)
    if #arg.choices == 0 then return end
    local cur = values[arg.key] or ""
    local idx = 0
    for i, c in ipairs(arg.choices) do
      if c == cur then idx = i; break end
    end
    idx = ((idx - 1 + dir) % #arg.choices) + 1
    values[arg.key] = arg.choices[idx]
    redraw()
  end

  --- Act on the current row (Space / CR).
  local function activate()
    if cursor_row > #args then
      do_run()
      return
    end
    local arg = args[cursor_row]
    if arg.is_bool then
      values[arg.key] = values[arg.key] == "true" and "false" or "true"
      redraw()
    elseif #arg.choices > 0 then
      cycle_choice(arg, 1)
    else
      edit_value(arg)
    end
  end

  -- Open the window.
  local lines, _, _ = build_lines(task_name, args, values, cursor_row)
  local cfg = win_cfg(lines, task_name)
  win = vim.api.nvim_open_win(buf, true, cfg)
  vim.wo[win].cursorline = false  -- we handle highlighting ourselves
  vim.wo[win].number     = false
  vim.wo[win].wrap       = false

  redraw()

  -- ── Keymaps ────────────────────────────────────────────────────────────
  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, desc = desc })
  end

  map("j",      function() cursor_row = math.min(cursor_row + 1, #args + 1); redraw() end, "Next field")
  map("k",      function() cursor_row = math.max(cursor_row - 1, 1);         redraw() end, "Previous field")
  map("<Down>", function() cursor_row = math.min(cursor_row + 1, #args + 1); redraw() end, "Next field")
  map("<Up>",   function() cursor_row = math.max(cursor_row - 1, 1);         redraw() end, "Previous field")

  map("<Space>", activate, "Toggle/edit")
  map("<CR>",    activate, "Toggle/edit/run")

  map("<Esc>", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, "Cancel")

  map("q", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, "Cancel")
end

return M

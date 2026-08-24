--- lua/mise/picker.lua
--- Telescope picker for mise tasks.
---
--- Opens a telescope window listing all non-hidden tasks.
--- The preview pane shows the usage/help text for the highlighted task.
--- <CR> runs the task directly (no args) or opens the argument form.
--- <C-r> invalidates the task cache and refreshes the picker.

local M = {}

local function open_picker()
  local ok_tel, telescope   = pcall(require, "telescope")
  local ok_fnd, finders     = pcall(require, "telescope.finders")
  local ok_cnf, conf        = pcall(require, "telescope.config")
  local ok_pck, pickers     = pcall(require, "telescope.pickers")
  local ok_act, actions     = pcall(require, "telescope.actions")
  local ok_ast, action_state = pcall(require, "telescope.actions.state")
  local ok_pre, previewers  = pcall(require, "telescope.previewers")

  if not (ok_tel and ok_fnd and ok_cnf and ok_pck and ok_act and ok_ast and ok_pre) then
    vim.notify("mise.nvim: telescope.nvim is required for MisePick", vim.log.levels.ERROR)
    return
  end

  local tasks_mod = require("mise.tasks")
  local tasks = tasks_mod.fetch_sync()

  -- Filter hidden tasks and build display entries.
  ---@class MiseEntry
  ---@field name string
  ---@field description string
  ---@field usage string
  ---@field args MiseArg[]
  local entries = {}
  for _, t in ipairs(tasks) do
    if not t.hide then
      entries[#entries + 1] = {
        name        = t.name,
        description = t.description or "",
        usage       = t.usage or "",
        args        = tasks_mod.parse_usage(t.usage or ""),
      }
    end
  end

  if #entries == 0 then
    vim.notify("mise.nvim: no tasks found", vim.log.levels.WARN)
    return
  end

  -- ── Previewer ────────────────────────────────────────────────────────────
  -- Shows the usage spec (parsed into readable text) or falls back to the
  -- raw help output cached by mise.help.
  local previewer = previewers.new_buffer_previewer({
    title = "Task info",
    define_preview = function(self, entry)
      local buf = self.state.bufnr
      local lines = {}

      -- Helper: append a string that may contain embedded newlines as separate lines.
      local function push(prefix, s)
        local first = true
        for _, l in ipairs(vim.split(s, "\n", { plain = true })) do
          lines[#lines + 1] = (first and prefix or string.rep(" ", #prefix)) .. l
          first = false
        end
      end

      -- Header
      lines[#lines + 1] = "Task:  " .. entry.value.name
      if entry.value.description ~= "" then
        push("       ", entry.value.description)
      end
      lines[#lines + 1] = ""

      local args = entry.value.args
      if #args > 0 then
        lines[#lines + 1] = "Arguments:"
        lines[#lines + 1] = ""

        -- Measure flag column width.
        local flag_w = 0
        for _, arg in ipairs(args) do
          flag_w = math.max(flag_w, #arg.flag)
        end

        for _, arg in ipairs(args) do
          local flag_padded = arg.flag .. string.rep(" ", flag_w - #arg.flag)
          local detail = arg.help ~= "" and arg.help or ""
          if arg.default and arg.default ~= "" then
            detail = detail .. (detail ~= "" and "  " or "") .. "(default: " .. arg.default .. ")"
          end
          if arg.required then
            detail = detail .. (detail ~= "" and "  " or "") .. "[required]"
          end
          if #arg.choices > 0 then
            detail = detail .. (detail ~= "" and "  " or "") .. "choices: " .. table.concat(arg.choices, ", ")
          end
          lines[#lines + 1] = "  " .. flag_padded .. "   " .. detail
        end
      else
        -- Try help text cache.
        local help_mod = require("mise.help")
        local cached = help_mod.get_cached_raw(entry.value.name)
        if cached and cached ~= "" then
          lines[#lines + 1] = "Help:"
          lines[#lines + 1] = ""
          for _, l in ipairs(vim.split(cached, "\n", { plain = true })) do
            lines[#lines + 1] = l
          end
        else
          lines[#lines + 1] = "(no arguments)"
        end
      end

      if not vim.api.nvim_buf_is_valid(buf) then return end
      vim.bo[buf].modifiable = true
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.bo[buf].modifiable = false
      vim.bo[buf].filetype = "text"
    end,
  })

  -- ── Action: select a task ────────────────────────────────────────────────
  local function select_task(prompt_bufnr)
    local entry = action_state.get_selected_entry()
    actions.close(prompt_bufnr)

    if not entry then return end

    local task = entry.value
    local run = require("mise").run

    if #task.args == 0 then
      -- No arguments — run immediately.
      run(task.name, {})
    else
      -- Open the argument form.
      require("mise.form").open(task.name, task.args, function(cli_args)
        run(task.name, cli_args)
      end)
    end
  end

  -- ── Action: refresh task list ─────────────────────────────────────────────
  local function refresh(prompt_bufnr)
    actions.close(prompt_bufnr)
    require("mise.tasks").invalidate()
    open_picker()
  end

  -- Measure the longest task name for column alignment.
  local max_name_w = 0
  for _, e in ipairs(entries) do
    max_name_w = math.max(max_name_w, #e.name)
  end

  -- ── Build picker ─────────────────────────────────────────────────────────
  pickers.new({}, {
    prompt_title    = "Mise Tasks",
    results_title   = "Tasks",
    -- Use ascending to avoid a Telescope bug with descending strategy on
    -- Nvim 0.12: get_result_completor fires via vim.schedule_wrap after the
    -- results window can be resized, making max_results - visible_rows go out
    -- of range for nvim_win_set_cursor.
    sorting_strategy = "ascending",

    finder = finders.new_table({
      results = entries,
      entry_maker = function(entry)
        -- Returns (display_string, highlights) so we can dim the description.
        local display = function(_entry)
          local name = _entry.value.name
          -- Truncate at first newline so the results list stays single-line.
          local desc = (_entry.value.description:match("^([^\n]*)") or _entry.value.description)
          local gap  = 4
          local padded_name = name .. string.rep(" ", max_name_w - #name + gap)
          if desc == "" then
            return padded_name, {}
          end
          local text = padded_name .. desc
          -- Dim the description with Comment highlight.
          local hl = { { { max_name_w + gap, #text }, "Comment" } }
          return text, hl
        end

        return {
          value   = entry,
          display = display,
          ordinal = entry.name .. " " .. entry.description,
        }
      end,
    }),

    sorter   = conf.values.generic_sorter({}),
    previewer = previewer,

    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        select_task(prompt_bufnr)
      end)
      map({ "n", "i" }, "<C-r>", function()
        refresh(prompt_bufnr)
      end)
      return true
    end,
  }):find()
end

--- Open the MisePick telescope picker.
function M.pick()
  open_picker()
end

return M

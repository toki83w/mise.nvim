--- lua/mise/tasks.lua
--- Fetches task metadata from `mise tasks --json` and parses Usage spec strings.

local M = {}

--- Cached task list (array of raw task objects from JSON).
---@type table[]|nil
local cache = nil

--- Parse a mise Usage spec string into a list of flag definitions.
---
--- Handles both attribute styles emitted by mise:
---
---   Inline style:
---     flag "-b --build-type [type]" help="Build type" default="RelWithDebInfo" {
---         choices "Release" "Debug" "RelWithDebInfo"
---     }
---
---   Block style (attributes inside braces):
---     flag "-b --build-type <type>" {
---         help "Build type"
---         choices "Release" "Debug" "RelWithDebInfo"
---         default "RelWithDebInfo"
---     }
---
---   Boolean flags (no value placeholder):
---     flag "--tests" help="Build tests"
---     flag "--tests" { help "Build tests" }
---
---@param usage string Raw usage field from mise tasks --json
---@return MiseArg[]
function M.parse_usage(usage)
  if not usage or usage == "" then return {} end

  ---@class MiseArg
  ---@field flag    string   Display name: "--long-name" or "-s" if no long
  ---@field short   string|nil  Short flag including dash, e.g. "-b" (nil if none)
  ---@field key     string   mise template key (e.g. "build_type" from --build-type)
  ---@field help    string
  ---@field default string|nil
  ---@field required boolean
  ---@field choices string[]
  ---@field is_bool boolean   true = boolean toggle, false = value flag

  local args = {}

  local pos = 1
  local len = #usage

  while pos <= len do
    -- Skip whitespace / newlines.
    local ws_end = usage:match("^%s*()", pos)
    if ws_end then pos = ws_end end
    if pos > len then break end

    -- Match the keyword "flag".
    local kw, kw_end = usage:match('^(flag)%s+()', pos)
    if not kw then
      local nl = usage:find("\n", pos, true)
      pos = nl and nl + 1 or len + 1
    else
      pos = kw_end

      -- ── quoted spec string ────────────────────────────────────────────
      local spec, spec_end = usage:match('^"([^"]*)"()%s*', pos)
      if not spec then
        local nl = usage:find("\n", pos, true)
        pos = nl and nl + 1 or len + 1
      else
        pos = spec_end

        -- Parse spec: optional short "-x", optional long "--word",
        -- optional value placeholder: "[val]" or "<val>"
        local short = spec:match("^%-([%a%d])%s") or spec:match("^%-([%a%d])$")
        local long  = spec:match("%-%-([%w][%w%-]*)")
        local has_val = spec:match("%[.-%]") ~= nil
                     or spec:match("<.->")  ~= nil

        -- Display flag and mise template key.
        local flag_display, key
        if long then
          flag_display = "--" .. long
          key = long:gsub("%-", "_")
        elseif short then
          flag_display = "-" .. short
          key = short
        else
          flag_display = spec
          key = spec:gsub("[^%w]", "_")
        end

        -- ── collect attr_str and optional brace block ─────────────────
        local help     = ""
        local default  = nil
        local required = false
        local choices  = {}
        local attr_str = ""
        local brace_pos = nil

        local lookahead = usage:sub(pos)
        local brace_off = lookahead:find("{", 1, true)
        local next_flag = lookahead:find("\nflag ", 1, true)

        if brace_off and (not next_flag or brace_off < next_flag) then
          attr_str  = lookahead:sub(1, brace_off - 1)
          brace_pos = pos + brace_off - 1
          pos       = brace_pos
        else
          local eol = lookahead:find("\n", 1, true)
          attr_str = eol and lookahead:sub(1, eol - 1) or lookahead
          pos = pos + #attr_str
        end

        -- ── inline attributes: help="..." default="..." required ───────
        local h = attr_str:match('help="([^"]*)"')
        if h then help = h end

        local d = attr_str:match('default="([^"]*)"')
        if d then default = d end

        if attr_str:match("%srequired%s") or attr_str:match("%srequired$")
          or attr_str:match("^required%s") or attr_str:match("^required$") then
          required = true
        end

        -- ── optional brace block ───────────────────────────────────────
        -- Supports both styles inside the block:
        --   choices "a" "b" "c"
        --   help "some text"
        --   default "val"
        --   required
        if brace_pos then
          local close = usage:find("}", brace_pos, true)
          if close then
            local block = usage:sub(brace_pos, close)

            -- choices: grab all quoted strings after the "choices" keyword
            local choices_line = block:match('choices([^\n]*)')
            if choices_line then
              for choice in choices_line:gmatch('"([^"]*)"') do
                choices[#choices + 1] = choice
              end
            end

            -- block-style help "..." (only if not already set inline)
            if help == "" then
              local bh = block:match('\n%s*help%s+"([^"]*)"')
              if bh then help = bh end
            end

            -- block-style default "..." (only if not already set inline)
            if default == nil then
              local bd = block:match('\n%s*default%s+"([^"]*)"')
              if bd then default = bd end
            end

            -- block-style required
            if not required and block:match('\n%s*required%s*\n') then
              required = true
            end

            pos = close + 1
          else
            pos = len + 1
          end
        end

        args[#args + 1] = {
          flag     = flag_display,
          short    = short and ("-" .. short) or nil,
          key      = key,
          help     = help,
          default  = default,
          required = required,
          choices  = choices,
          is_bool  = not has_val,
        }
      end
    end
  end

  return args
end

--- Invalidate the task cache (e.g. after mise.toml changes).
function M.invalidate()
  cache = nil
end

--- Fetch tasks synchronously. Returns raw task objects array.
--- Blocks the UI briefly; use only where async is not possible.
---@return table[]
function M.fetch_sync()
  if cache then return cache end
  local raw = vim.fn.system("mise tasks --json 2>/dev/null")
  local ok, decoded = pcall(vim.json.decode, raw)
  if not ok or type(decoded) ~= "table" then
    vim.notify("mise.nvim: failed to parse `mise tasks --json`", vim.log.levels.WARN)
    return {}
  end
  cache = decoded
  return cache
end

--- Fetch tasks asynchronously. Calls cb(tasks) on completion.
--- Uses cache if available.
---@param cb fun(tasks: table[])
function M.fetch(cb)
  if cache then
    cb(cache)
    return
  end
  vim.system({ "mise", "tasks", "--json" }, { text = true }, function(result)
    vim.schedule(function()
      local raw = (result.stdout or "")
      local ok, decoded = pcall(vim.json.decode, raw)
      if not ok or type(decoded) ~= "table" then
        vim.notify("mise.nvim: failed to parse `mise tasks --json`", vim.log.levels.WARN)
        cb({})
        return
      end
      cache = decoded
      cb(cache)
    end)
  end)
end

return M

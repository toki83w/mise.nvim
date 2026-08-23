--- lua/mise/tasks.lua
--- Fetches task metadata from `mise tasks --json` and parses Usage spec strings.

local M = {}

--- Cached task list (array of raw task objects from JSON).
---@type table[]|nil
local cache = nil

--- Parse a mise Usage spec string into a list of flag definitions.
---
--- Handles:
---   flag "-b --build-type [type]" help="Build type" default="RelWithDebInfo" {
---       choices "Release" "Debug" "RelWithDebInfo"
---   }
---   flag "--tests" help="Build tests"
---   flag "-u --update" help="Check for updated packages"
---
---@param usage string Raw usage field from mise tasks --json
---@return MiseArg[]
function M.parse_usage(usage)
  if not usage or usage == "" then return {} end

  ---@class MiseArg
  ---@field flag    string   Display name: "--long-name" or "-s" if no long
  ---@field key     string   mise template key (e.g. "build_type" from --build-type)
  ---@field help    string
  ---@field default string|nil
  ---@field required boolean
  ---@field choices string[]
  ---@field is_bool boolean   true = boolean toggle, false = value flag

  local args = {}

  -- Iterate flag blocks. A block is either:
  --   flag "..." ... { choices ... }
  --   flag "..." ...          (no braces)
  --
  -- We consume the string position by position to handle multi-line blocks.
  local pos = 1
  local len = #usage

  while pos <= len do
    -- Skip whitespace and newlines.
    local ws_end = usage:match("^%s*()", pos)
    if ws_end then pos = ws_end end
    if pos > len then break end

    -- Match the keyword "flag".
    local kw, kw_end = usage:match('^(flag)%s+()', pos)
    if not kw then
      -- Skip any unrecognised content up to next newline.
      local nl = usage:find("\n", pos, true)
      pos = nl and nl + 1 or len + 1
    else
      pos = kw_end

      -- ── quoted spec string ────────────────────────────────────────────
      local spec, spec_end = usage:match('^"([^"]*)"()%s*', pos)
      if not spec then
        -- malformed, skip line
        local nl = usage:find("\n", pos, true)
        pos = nl and nl + 1 or len + 1
      else
        pos = spec_end

        -- Parse spec: optional short "-x", optional long "--word", optional "[val]"
        local short = spec:match("^%-([%a%d])%s") or spec:match("^%-([%a%d])$")
        local long  = spec:match("%-%-([%w][%w%-]*)")
        local has_val = spec:match("%[.-%]") ~= nil

        -- Display flag and mise template key
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

        -- ── inline attributes (help=".." default=".." required) ─────────
        local help    = ""
        local default = nil
        local required = false

        -- Collect everything up to "{" or newline-with-no-brace as attr string.
        -- Attributes may span to end of line before optional "{...}" block.
        local attr_str = ""
        local brace_pos = nil

        -- Look ahead for "{" on same or next lines (Usage spec allows it).
        -- Grab everything from current pos to first "{" or to double-newline.
        local lookahead = usage:sub(pos)
        local brace_off = lookahead:find("{", 1, true)
        local next_flag = lookahead:find("\nflag ", 1, true)

        if brace_off and (not next_flag or brace_off < next_flag) then
          attr_str  = lookahead:sub(1, brace_off - 1)
          brace_pos = pos + brace_off - 1
          pos       = brace_pos
        else
          -- No brace block: attrs go to end of line.
          local eol = lookahead:find("\n", 1, true)
          attr_str = eol and lookahead:sub(1, eol - 1) or lookahead
          pos = pos + #attr_str
        end

        -- Extract help="..."
        local h = attr_str:match('help="([^"]*)"')
        if h then help = h end

        -- Extract default="..."
        local d = attr_str:match('default="([^"]*)"')
        if d then default = d end

        -- Extract bare keyword "required"
        if attr_str:match("%srequired%s") or attr_str:match("%srequired$") then
          required = true
        end

        -- ── optional choices block { choices "a" "b" ... } ──────────────
        local choices = {}
        if brace_pos then
          -- Find matching closing brace.
          local block_start = pos
          local close = usage:find("}", block_start, true)
          if close then
            local block = usage:sub(block_start, close)
            for choice in block:gmatch('"([^"]*)"') do
              choices[#choices + 1] = choice
            end
            pos = close + 1
          else
            pos = len + 1
          end
        end

        args[#args + 1] = {
          flag     = flag_display,
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

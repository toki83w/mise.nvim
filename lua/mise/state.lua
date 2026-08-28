--- lua/mise/state.lua
--- Shared runtime state for mise.nvim (task name, terminal status).
--- Written by runner.lua; read by the lualine component and any other consumer.

local M = {}

---@alias MiseStatus "idle"|"running"|"success"|"failure"

---@class MiseState
---@field task    string|nil   Name of the last-run task
---@field status  MiseStatus   Current terminal status
M.task   = nil
M.status = "idle"  ---@type MiseStatus

return M

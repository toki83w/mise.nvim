--- lua/lualine/components/mise.lua
--- Lualine component that shows the status of the current mise task.
---
--- Usage:
---   require("lualine").setup({
---     sections = {
---       lualine_x = { "mise" },
---     },
---   })
---
---   Or with options:
---   require("lualine").setup({
---     sections = {
---       lualine_x = { { "mise", colored = false, symbols = { running = "…" } } },
---     },
---   })
---
--- Options:
---
---   colored (default: true)
---     Color the status symbol using highlight groups.
---
---   symbols (default: see below)
---     Map of status → display string.
---       running = "󰑮 "
---       success = "󰄴 "
---       failure = "󰅚 "
---
---   hide_on_idle (default: true)
---     When true, the component renders nothing when no task has been run yet.

local M = require("lualine.component"):extend()

local default_icons = {
	running = "󰑮 ",
	success = " ",
	failure = " ",
}

local default_no_icons = {
	running = "RUNNING ",
	success = "SUCCESS ",
	failure = "FAILURE ",
}

-- Colors used to create per-component highlight groups.
local STATUS_COLORS = {
	running = { fg = "#e5c07b" },
	success = { fg = "#98c379" },
	failure = { fg = "#e06c75" },
}

function M:init(options)
	M.super.init(self, options)

	if self.options.colored == nil then
		self.options.colored = true
	end
	if self.options.hide_on_idle == nil then
		self.options.hide_on_idle = true
	end
	if self.options.show_task_name == nil then
		self.options.show_task_name = false
	end

	self.symbols = vim.tbl_extend(
		"keep",
		self.options.symbols or {},
		self.options.icons_enabled ~= false and default_icons or default_no_icons
	)

	-- Create per-component highlight groups (same pattern as overseer component).
	if self.options.colored then
		self.highlight_groups = {}
		for status, color in pairs(STATUS_COLORS) do
			self.highlight_groups[status] = self:create_hl(color, status)
		end
	end
end

function M:update_status()
	local ok, state = pcall(require, "mise.state")
	if not ok then
		return
	end

	local status = state.status
	local task = state.task

	if not task or status == "idle" then
		if self.options.hide_on_idle then
			return
		end
		return "idle"
	end

	local symbol = self.symbols[status] or status

	if self.options.colored and self.highlight_groups and self.highlight_groups[status] then
		local hl_start = self:format_hl(self.highlight_groups[status])
		symbol = hl_start .. symbol
	end

	return self.options.show_task_name and (task .. " " .. symbol) or symbol
end

return M

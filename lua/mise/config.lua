local M = {}

---@class MiseToggletermOpts
---@field direction string Terminal direction: "tab", "float", "horizontal", "vertical"
---@field count integer Toggleterm instance count/id
---@field auto_scroll boolean Auto-scroll the terminal
---@field close_on_exit boolean Close terminal when process exits
---@field quit_on_exit string "always"|"success"|"never"
---@field open_on_start boolean Open the terminal when the task starts
---@field hidden boolean Hide terminal from toggleterm list
---@field use_shell boolean Run command via shell
---@field keep_after_exit boolean Keep terminal buffer after exit
---@field start_in_insert boolean Enter insert mode when terminal opens

---@class MiseOpts
---@field toggleterm MiseToggletermOpts

---@type MiseOpts
M.defaults = {
  toggleterm = {
    direction = "tab",
    count = 33,
    auto_scroll = false,
    close_on_exit = false,
    quit_on_exit = "never",
    open_on_start = true,
    hidden = false,
    use_shell = false,
    keep_after_exit = true,
    start_in_insert = false,
  },
}

---@type MiseOpts
M.options = {}

---Merge user options over defaults.
---@param opts MiseOpts|nil
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M

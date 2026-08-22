# mise.nvim

A Neovim plugin that runs [mise](https://mise.jdx.dev/) tasks in a [toggleterm.nvim](https://github.com/akinsho/toggleterm.nvim) terminal.

## Requirements

- Neovim 0.9+
- [toggleterm.nvim](https://github.com/akinsho/toggleterm.nvim)
- `mise` available in `$PATH`

## Installation

### lazy.nvim

```lua
{
  "your-username/mise.nvim",
  dependencies = { "akinsho/toggleterm.nvim" },
  opts = {}, -- uses defaults; see Configuration below
}
```

### packer.nvim

```lua
use {
  "your-username/mise.nvim",
  requires = { "akinsho/toggleterm.nvim" },
  config = function()
    require("mise").setup()
  end,
}
```

## Usage

```
:MiseRun <task> [args...]
```

All arguments after the task name are forwarded directly to `mise run`:

```
:MiseRun build --release        →  mise run build --release
:MiseRun test unit              →  mise run test unit
```

Tab-completion is available for task names (powered by `mise tasks`).

```
:MiseToggleTerm
```

Toggles the mise terminal instance open/closed. Equivalent to the standard
toggleterm keybind for the configured `count`. Shows a warning if no task has
been run yet.

### Lua API

```lua
require("mise").run("build", { "--release" })
require("mise").toggle()
```

## Configuration

Call `setup()` with any options you want to override. All fields are optional.

```lua
require("mise").setup({
  toggleterm = {
    direction      = "tab",    -- "tab" | "float" | "horizontal" | "vertical"
    count          = 33,       -- toggleterm instance id (toggle with <count><C-\><C-n>)
    auto_scroll    = false,
    close_on_exit  = false,
    quit_on_exit   = "never",  -- "always" | "success" | "never"
    open_on_start  = true,     -- open the terminal window immediately
    hidden         = false,    -- keep it toggleable; set true to hide from list
    use_shell      = false,
    keep_after_exit = true,
    start_in_insert = false,
  },
})
```

### Defaults

| Option            | Default   | Description                                          |
|-------------------|-----------|------------------------------------------------------|
| `direction`       | `"tab"`   | How the terminal window is opened                    |
| `count`           | `33`      | Toggleterm instance id used for all mise tasks       |
| `auto_scroll`     | `false`   | Scroll to the bottom on new output                   |
| `close_on_exit`   | `false`   | Close the window when the process finishes           |
| `quit_on_exit`    | `"never"` | Quit Neovim when the process finishes                |
| `open_on_start`   | `true`    | Open the terminal window when `:MiseRun` is called   |
| `hidden`          | `false`   | Hide from toggleterm list (disables toggling if true)|
| `use_shell`       | `false`   | Wrap command in `$SHELL -c`                          |
| `keep_after_exit` | `true`    | Keep the buffer after the process exits              |
| `start_in_insert` | `false`   | Enter insert mode when the terminal opens            |

## Toggling the Terminal

Because every `:MiseRun` call uses the same `count` (default `33`), you can toggle it with the standard toggleterm keybind:

```lua
-- With toggleterm default setup:
vim.keymap.set("n", "<leader>mt", "<cmd>33ToggleTerm<cr>", { desc = "Toggle mise terminal" })
```

## License

MIT

# mise.nvim

A Neovim plugin that runs [mise](https://mise.jdx.dev/) tasks in a [toggleterm.nvim](https://github.com/akinsho/toggleterm.nvim) terminal.

## Requirements

- Neovim 0.10+
- [toggleterm.nvim](https://github.com/toki83w/toggleterm.nvim)
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) (optional, for `:MisePick`)
- `mise` available in `$PATH`

## Installation

### lazy.nvim

```lua
{
  "toki83w/mise.nvim",
  dependencies = { "toki83w/toggleterm.nvim" },
  opts = {}, -- uses defaults; see Configuration below
}
```

### packer.nvim

```lua
use {
  "toki83w/mise.nvim",
  requires = { "toki83w/toggleterm.nvim" },
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
After typing a task name, press `<C-h>` to open a floating popup with the
output of `mise run <task> -h`. Press `<C-h>` again after editing the task
name to refresh the popup for the new task. The popup closes automatically
when you leave the command line (Enter, Esc, `<C-c>`).

```
:MiseToggleTerm
```

Toggles the mise terminal instance open/closed. Equivalent to the standard
toggleterm keybind for the configured `count`. Shows a warning if no task has
been run yet.

```
:MisePick
```

Opens a Telescope picker listing all available tasks. The preview pane shows
each task's arguments, defaults, and choices. Selecting a task with `<CR>`:

- Runs it immediately if it takes no arguments.
- Opens an argument form if it has arguments.

In the argument form:

- `j` / `k` move between fields.
- `<Space>` / `<CR>` toggle boolean flags or open an input prompt for value flags.
- `<CR>` on `[Run]` executes the task with the configured arguments.
- `<Esc>` / `q` cancel.

In the picker, `<C-r>` invalidates the task cache and refreshes the list.

Requires [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim).

### Lua API

```lua
require("mise").run("build", { "--release" })
require("mise").toggle()
```

## Configuration

Call `setup()` with any options you want to override. All fields are optional.

```lua
require("mise").setup({
  help_keymap = "<C-h>",  -- set to false to disable the help popup
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
| `help_keymap`     | `"<C-h>"` | Cmdline key to show the task help popup; `false` to disable |

`toggleterm` options:

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

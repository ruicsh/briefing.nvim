# briefing.nvim

A Neovim plugin for crafting prompts before sending them to agentic coding agents.

briefing.nvim opens a floating window for composing natural language prompts enriched with editor context. Reference your current buffer, diagnostics, git diff, or specific files using `#context` variables and `@resource` references — then send the resolved prompt to your agent of choice.

## Features

- Floating markdown window tuned for writing prompts (wrap, line breaks, no code autocompletion)
- Context variables (`#buffer`, `#diagnostics`, `#diff`, `#selection`, `#quickfix`, `#file`, `#files`) that resolve editor state into your prompt
- Resource references (`@<file>`, `@<folder>`, `http(s)://url`) for attaching external content
- Autocomplete for context variables via blink.cmp or nvim-cmp
- Interactive file and directory pickers via snacks.picker
- Adapter system to send prompts to different agents (sidekick.nvim or a custom callback)
- Reusable prompt templates

## Requirements

- Neovim >= 0.10
- [folke/snacks.nvim](https://github.com/folke/snacks.nvim) — picker backend
- [saghen/blink.cmp](https://github.com/saghen/blink.cmp) or [hrsh7th/nvim-cmp](https://github.com/hrsh7th/nvim-cmp) — autocomplete
- [folke/sidekick.nvim](https://github.com/folke/sidekick.nvim) — optional, for the sidekick adapter

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "ruicsh/briefing.nvim",
  dependencies = {
    "folke/snacks.nvim",
  },
  keys = {
    { "<leader>b", "<cmd>Briefing<cr>", mode = { "n", "v" }, desc = "Open Briefing" },
  },
  opts = {},
}
```

### Autocomplete setup

After installing briefing.nvim, register the autocomplete source in your completion plugin config.

#### blink.cmp

Add the briefing source to your blink.cmp config:

```lua
require("blink.cmp").setup({
  sources = {
    providers = {
      briefing = {
        module = "blink-cmp-briefing",
        name = "Briefing Context",
      },
    },
    default = { "lsp", "path", "buffer", "briefing" },
  },
})
```

#### nvim-cmp

```lua
require("cmp").setup({
  sources = {
    { name = "briefing" },
  },
})
```

The autocomplete source only activates in briefing buffers (filetype `briefing`).

## Usage

### Commands

| Command                    | Description                                     |
| -------------------------- | ----------------------------------------------- |
| `:Briefing`                | Open the floating window                        |
| `:Briefing <template>`     | Open with a template pre-loaded                 |
| `:BriefingTemplate <name>` | Apply a template to the current briefing buffer |
| `:BriefingSend`            | Send the prompt to the configured agent         |

### Keymaps

| Key     | Mode          | Action                           |
| ------- | ------------- | -------------------------------- |
| `<C-s>` | insert/normal | Send prompt to agent             |
| `q`     | normal        | Close window (content persists)  |
| `<C-x>` | insert/normal | Reset buffer (clear all content) |
| `<C-t>` | insert/normal | Open template picker             |

### Workflow

1. Open the briefing window with `:Briefing`
2. Write your prompt in natural language
3. Add context with `#` variables (e.g. `#buffer`, `#diagnostics`) — type `#` and use autocomplete
4. Reference files with `@` or `#file:<tab>` to open a picker
5. Press `<C-s>` to resolve all tokens and send the prompt to your agent

### Visual mode

Select text, then run `:Briefing`. The selection is captured and can be referenced in your prompt via `#selection`.

### Buffer lifecycle

- Content **persists** when you close the window with `q` — reopening shows your previous draft
- `<C-x>` clears the buffer completely
- One buffer per tab, reused across open/close cycles

## Context Variables (`#`)

Context variables insert editor state into your prompt. Type `#` in the briefing buffer to see completions.

| Variable        | Description                                                                                         | Sub-options                                                                        |
| --------------- | --------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| `#buffer`       | Current buffer contents                                                                             | `#buffer:diff` (changed portions only), `#buffer:all` (entire buffer, default)     |
| `#selection`    | Visual selection captured when the window was opened — resolves to empty if no selection was active | —                                                                                  |
| `#diagnostics`  | LSP diagnostics                                                                                     | `#diagnostics:buffer` (current buffer, default), `#diagnostics:all` (workspace)    |
| `#diff`         | Git diff output                                                                                     | bare `#diff` defaults to unstaged; `#diff:staged`, `#diff:<sha>` (specific commit) |
| `#file:<path>`  | A specific file's content                                                                           | `<tab>` opens a file picker; multi-select inserts multiple `#file:` tokens         |
| `#files:<path>` | All files in a directory                                                                            | `#files:grep` (pattern search), `#files:glob` (glob match)                         |
| `#quickfix`     | Quickfix list contents                                                                              | —                                                                                  |

## Resources (`@`)

Resources are explicit references to external content. Type `@` then `<tab>` to open a picker, or type the path manually. URLs are recognized as standalone tokens without a prefix.

| Syntax            | Description                                                                      |
| ----------------- | -------------------------------------------------------------------------------- |
| `@<file-path>`    | Attach a specific file                                                           |
| `@<folder-path>`  | Attach all files in a directory                                                  |
| `http(s)://<url>` | Reference a URL (translated to the agent's web fetch tool; no `@` prefix needed) |

## Picker

When `<tab>` is pressed after a token that accepts input, an interactive picker opens:

| Trigger            | Picker           | Result                                       |
| ------------------ | ---------------- | -------------------------------------------- |
| `#file:<tab>`      | File picker      | `#file:src/foo.lua` (multi-select supported) |
| `#files:<tab>`     | Directory picker | `#files:src/`                                |
| `#files:grep<tab>` | Grep picker      | Grep results                                 |
| `@<tab>`           | File picker      | `@src/foo.lua`                               |

Multi-select in the file picker produces separate tokens: `#file:a.lua #file:b.lua`.

## Templates

Templates are reusable prompts with pre-configured context variables.

### Defining templates

```lua
require("briefing").setup({
  templates = {
    {
      name = "explain error",
      description = "Explain the current error",
      content = "Explain this error:\n\n#diagnostics",
    },
    {
      name = "review changes",
      description = "Review unstaged changes",
      content = "Please review my changes:\n\n#diff:unstaged",
    },
    {
      name = "refactor selection",
      description = "Refactor selected code",
      content = "Refactor this code for clarity and maintainability:\n\n#selection",
    },
  },
})
```

### Applying templates

- `:Briefing <template>` — open with a template pre-loaded
- `:BriefingTemplate <name>` — apply to the current buffer
- `<C-t>` — open a picker to browse and select templates

## Configuration

The plugin ships with safe defaults and exposes everything through
`require("briefing").setup({ ... })`.

<details>
<summary>Default settings</summary>

<!-- config:start -->

```lua
---@class briefing.Config
local defaults = {
  ---@type briefing.Window.Opts
  window = {
    --- Called just before the window opens.
    --- Mutate the win_config table to override any option.
    ---@type fun(win_config: vim.api.keyset.win_config)?
    config = nil,
    wo = {}, ---@type vim.wo  window-local option overrides
    bo = {}, ---@type vim.bo  buffer-local option overrides
    -- width / height: absolute integers, or 0–1 as a fraction of the editor size
    width = 80,
    height = 20,
    border = "rounded",
    title = " Briefing ",
    title_pos = "center", ---@type "left"|"center"|"right"
  },

  --- Named keymaps for the briefing window.
  --- Each entry is { lhs, action, mode?, desc? }.
  --- Set any entry to `false` to disable that binding.
  --- mode is a string of mode characters: "n" = normal, "i" = insert, "ni" = both.
  ---@type table<string, briefing.Keymap|false>
  keymaps = {
    send  = { "<c-s>", "send",  mode = "ni", desc = "send prompt to agent" },
    close = { "q",     "close", mode = "n",  desc = "close the window" },
  },
}
```

<!-- config:end -->

</details>

## Adapters

Adapters translate your resolved prompt into the format expected by each agent.

### `callback` (default)

Resolves all tokens into plain text and passes the result to a callback function. The default callback copies the prompt to the system clipboard.

```lua
require("briefing").setup({
  adapter = "callback",
  adapter_config = {
    callback = function(resolved_text)
      vim.fn.setreg("+", resolved_text)
      vim.notify("Copied to clipboard!")
    end,
  },
})
```

### `sidekick`

Sends the prompt through [sidekick.nvim](https://github.com/folke/sidekick.nvim). Tokens are translated to sidekick's native context variables where possible, so sidekick handles their resolution. Tokens without a sidekick equivalent (like `#diff`) are resolved by briefing.nvim directly.

```lua
require("briefing").setup({
  adapter = "sidekick",
})
```

Requires `folke/sidekick.nvim` to be installed and configured.

## Lua API

```lua
require("briefing").open()                       -- open empty window
require("briefing").open({ template = "name" })  -- open with template
require("briefing").open({ content = "text" })   -- open with content
require("briefing").send()                       -- send current buffer
require("briefing").close()                      -- close window
require("briefing").reset()                      -- clear buffer
```

## Syntax Highlighting

Tokens in the briefing buffer are highlighted:

| Pattern              | Highlight Group                      | Default Link       |
| -------------------- | ------------------------------------ | ------------------ |
| `#context`           | `BriefingContext`                    | `@keyword`         |
| `#context:suboption` | `BriefingContext` + dimmed suboption | `@keyword`         |
| `@path`              | `BriefingResource`                   | `@string`          |
| `http(s)://url`      | `BriefingUrl`                        | `@markup.link.url` |

Override these highlight groups in your colorscheme to customize appearance.

## Acknowledgements

briefing.nvim draws inspiration from several projects:

- [codecompanion.nvim](https://github.com/olimorris/codecompanion.nvim) — editor context system
- [CopilotChat.nvim](https://github.com/CopilotC-Nvim/CopilotChat.nvim) — context variables and chat UX
- [sidekick.nvim](https://github.com/folke/sidekick.nvim) — prompts, context, and agent integration
- [avante.nvim](https://github.com/yetone/avante.nvim) — mentions and context triggers
- [opencode.nvim](https://github.com/nickjvandyke/opencode.nvim) — context system
- [Cursor](https://cursor.com/docs/agent/prompting) — `@` references and context model

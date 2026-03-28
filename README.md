# briefing.nvim

A Neovim plugin for crafting prompts before sending them to agentic coding agents.

briefing.nvim opens a floating window for composing natural language prompts enriched with editor context. Reference your current buffer, diagnostics, git diff, or specific files using `#context` variables and `@resource` references — then send the resolved prompt to your agent of choice.

## Features

- Floating markdown window tuned for writing prompts (wrap, line breaks, no code autocompletion)
- Context variables (`#buffer`, `#diagnostics`, `#diff`, `#selection`, `#quickfix`, `#file`) that resolve editor state into your prompt
- Resource references (`@<file>`, `@<folder>`, `http(s)://url`) for attaching external content
- Interactive file and directory pickers via snacks.picker
- Adapter system to send prompts to different agents (sidekick.nvim or a custom callback)
- Reusable prompt templates

## Requirements

- Neovim >= 0.10
- [folke/snacks.nvim](https://github.com/folke/snacks.nvim) — picker backend
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

## Usage

### Commands

| Command                    | Description                                     |
| -------------------------- | ----------------------------------------------- |
| `:Briefing`                | Open the floating window                        |
| `:Briefing <template>`     | Open with a template pre-loaded                 |
| `:BriefingTemplate <name>` | Apply a template to the current briefing buffer |
| `:BriefingSend`            | Send the prompt to the configured agent         |

### Keymaps

| Key     | Mode          | Action                               |
| ------- | ------------- | ------------------------------------ |
| `<C-s>` | insert/normal | Send prompt to agent                 |
| `q`     | normal        | Close window (content persists)      |
| `<C-x>` | insert/normal | Reset buffer (clear all content)     |
| `<C-t>` | insert/normal | Open template picker                 |
| `<Tab>` | insert        | Open picker after token or reference |

### Workflow

1. Open the briefing window with `:Briefing`
2. Write your prompt in natural language
3. Add context with `#` variables (e.g. `#buffer`, `#diagnostics`)
4. Reference files with `@` or `#file:<Tab>` to open a picker
5. Press `<C-s>` to resolve all tokens and send the prompt to your agent

### Visual mode

Select text, then run `:Briefing`. The selection is captured and can be referenced in your prompt via `#selection`.

### Buffer lifecycle

- Content **persists** when you close the window with `q` — reopening shows your previous draft
- `<C-x>` clears the buffer completely
- One buffer per tab, reused across open/close cycles

## Context Variables (`#`)

Context variables insert editor state into your prompt.

| Variable                | Description                                    | Notes                                            |
| ----------------------- | ---------------------------------------------- | ------------------------------------------------ |
| `#buffer`               | Current buffer contents (default)              | Same as `#buffer:diff`                           |
| `#buffer:diff`          | Changed portions of current buffer             | —                                                |
| `#buffer:all`           | Entire buffer contents                         | —                                                |
| `#selection`            | Visual selection captured when Briefing opened | Resolves to empty if no selection was active     |
| `#diagnostics`          | LSP diagnostics for current buffer (default)   | Same as `#diagnostics:buffer`                    |
| `#diagnostics:buffer`   | LSP diagnostics for current buffer             | —                                                |
| `#diagnostics:all`      | LSP diagnostics for entire workspace           | —                                                |
| `#diff`                 | Unstaged changes (default)                     | Same as `#diff:unstaged`                         |
| `#diff:staged`          | Staged changes                                 | —                                                |
| `#diff:hunk`            | Hunk at cursor position                        | Works in normal buffers, diff mode, and fugitive |
| `#diff:<file>`          | Diff for a specific file                       | e.g. `#diff:src/foo.lua`                         |
| `#diff:<sha>`           | Diff for a specific commit                     | e.g. `#diff:abc123`                              |
| `#file:<path>`          | A specific file's content                      | `<Tab>` opens file picker                        |
| `#quickfix`             | Quickfix list contents                         | —                                                |

## Resources (`@`)

Resources are explicit references to external content. Type `@` then `<tab>` to open a picker, or type the path manually. URLs are recognized as standalone tokens without a prefix.

| Syntax            | Description                                                                      |
| ----------------- | -------------------------------------------------------------------------------- |
| `@<file-path>`    | Attach a specific file                                                           |
| `@<folder-path>`  | Attach all files in a directory                                                  |
| `http(s)://<url>` | Reference a URL (translated to the agent's web fetch tool; no `@` prefix needed) |

## Picker

When `<Tab>` is pressed after a token that accepts input, an interactive picker opens:

| Trigger            | Picker           | Result                                       |
| ------------------ | ---------------- | -------------------------------------------- |
| `#file:<Tab>`      | File picker      | `#file:src/foo.lua` (multi-select supported) |
| `@<Tab>`           | File picker      | `@src/foo.lua`                               |
| `#buffer:<Tab>`    | Buffer picker    | Select from open buffers                     |

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
  --- Enable debug logging to :messages (via echom).
  --- Messages are prefixed with "Briefing [debug]:".
  --- Default: false
  ---@type boolean
  debug = false,

  --- Adapter used when sending the prompt.
  --- Built-in values: "sidekick" (default), "callback".
  --- May also be a table implementing the adapter interface.
  ---@type briefing.Adapter
  adapter = {
    --- Built-in adapter to use: "sidekick" (default) or "callback".
    --- May also be a table implementing the adapter interface ({ send = fun(...) }).
    name = "sidekick",

    --- Called by the callback adapter with the fully resolved prompt text.
    --- Default (nil): copies the prompt to the system clipboard.
    callback = nil,

    --- Options for the sidekick adapter.
    sidekick = {
      --- sidekick CLI tool to target when sending the prompt.
      --- Set to a tool name (e.g. "opencode", "claude") to always send to that tool.
      --- Default (nil): sends to whichever sidekick session is currently active.
      ---@type string?
      tool = nil,

      --- Automatically submit the prompt after appending it to the tool input.
      --- Set to false to only append without submitting (useful for review before send).
      --- Default: true
      ---@type boolean
      submit = true,
    },
  },

  ---@type briefing.Window.Opts
  window = {
    --- Called just before the window opens.
    --- Mutate the win_config table to override any option.
    ---@type fun(win_config: vim.api.keyset.win_config)?
    config = nil,
    wo = {}, ---@type vim.wo  window-local option overrides
    bo = {}, ---@type vim.bo  buffer-local option overrides
    -- width / height: absolute integers, or 0–1 as a fraction of the editor size
    width = 100,
    height = 0.6,
    border = "rounded",
    title = " Briefing ",
    title_pos = "center", ---@type "left"|"center"|"right"
    ---@type briefing.Footer
    footer = {
      enabled = true,                  -- show keymap hint footer on the border
      pos = "center",                  ---@type "left"|"center"|"right"
    },
  },

  --- Named keymaps for the briefing window.
  --- Each entry is { lhs, action, mode?, desc? }.
  --- Set any entry to `false` to disable that binding.
  --- mode is a string of mode characters: "n" = normal, "i" = insert, "ni" = both.
  ---@type table<string, briefing.Keymap|false>
  keymaps = {
    send        = { "<c-s>", "send",        mode = "ni", desc = "send prompt to agent" },
    reset       = { "<c-x>", "reset",       mode = "ni", desc = "clear the buffer" },
    close       = { "q",     "close",       mode = "n",  desc = "close the window" },
    picker      = { "<tab>", "picker",      mode = "i",  desc = "open picker" },
  },
}
```

<!-- config:end -->

</details>

## Adapters

Adapters translate your resolved prompt into the format expected by each agent.

### `sidekick` (default)

Sends the prompt through [sidekick.nvim](https://github.com/folke/sidekick.nvim). When `tool = "opencode"`, `#buffer` and `#buffer:all` are translated to `@<absolute-path>` so opencode can resolve the file itself. All other tokens are resolved by briefing.nvim and inlined as text before sending.

```lua
require("briefing").setup({
  adapter = {
    name = "sidekick",
    sidekick = {
      -- Pin a specific tool so you never have to pick one:
      tool = "opencode", -- or "claude", "gemini", etc.
      -- Set to false to append the prompt without auto-submitting:
      submit = true,     -- default
    },
  },
})
```

Requires `folke/sidekick.nvim` to be installed and configured.

### `callback`

Resolves all tokens into plain text and passes the result to a callback function. The default callback copies the prompt to the system clipboard.

````lua
require("briefing").setup({
  adapter = {
    name = "callback",
    callback = function(resolved_text)
      vim.fn.setreg("+", resolved_text)
      vim.notify("Copied to clipboard!")
    end,
  },
})

## Lua API

```lua
require("briefing").open()                       -- open empty window
require("briefing").open({ template = "name" })  -- open with template
require("briefing").open({ content = "text" })   -- open with content
require("briefing").send()                       -- send current buffer
require("briefing").close()                      -- close window
require("briefing").reset()                      -- clear buffer
````

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

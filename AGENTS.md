# AGENTS.md — briefing.nvim

Neovim plugin (Lua) that opens a floating window for composing natural-language
prompts enriched with editor context, sent to agentic coding agents (e.g.
sidekick.nvim). Early-stage project — only the core UI subsystem is implemented.

## Build / Lint / Test Commands

All commands are in the `Makefile`. CI runs lint and test on every push.

```bash
make deps        # clone plenary.nvim (test dependency)
make fmt         # format all Lua with StyLua (in-place)
make check-fmt   # check formatting without modifying files
make lint        # run luacheck on lua/ plugin/ spec/
make test        # run full test suite (headless Neovim + plenary)
```

### Running a single test file

```bash
nvim --headless --noplugin -u spec/minimal_init.lua \
  -c "lua require('plenary.test_harness').test_directory('spec/ui_spec.lua', { minimal_init = 'spec/minimal_init.lua' })"
```

Replace `spec/ui_spec.lua` with any `spec/*_spec.lua` file.

### CI workflows (.github/workflows/)

| Workflow   | What it does                          |
|------------|---------------------------------------|
| `lint.yml` | Installs luacheck via luarocks, `make lint` |
| `tests.yml`| Installs Neovim stable, caches plenary, `make deps && make test` |

## Project Structure

```
lua/briefing/
  init.lua        # public API facade: setup(), open(), close(), send()
  config.lua      # config defaults, merging, type definitions
  ui.lua          # floating window management, keymaps, get_text()
plugin/
  briefing.lua    # Neovim entry point: load guard, :Briefing command
spec/
  minimal_init.lua  # minimal init for headless test runner
  *_spec.lua        # test files (one per source module)
```

## Code Style

### Formatting (StyLua)

Enforced by StyLua (`.stylua.toml`):

- **Indentation:** Tabs (width 1)
- **Column width:** 120
- **Quotes:** Double quotes (`"AutoPreferDouble"`)
- **Call parentheses:** Always — `require("foo")`, never `require "foo"`
- **Trailing commas:** Always in multi-line tables

### Linting (luacheck)

Configured in `.luacheckrc`:

- Standard: `luajit`
- Global: `vim` is allowed
- Max line length: disabled (deferred to StyLua)
- Test files (`spec/**/*.lua`): busted globals (`describe`, `it`, `assert`, etc.) allowed

### General formatting rules

- Single blank line between logical sections; no double blank lines
- Short tables may be on one line; longer tables get one field per line
- No `--[[ ]]` block comments

## Naming Conventions

| Element                  | Convention            | Example                          |
|--------------------------|-----------------------|----------------------------------|
| Variables, functions     | `snake_case`          | `get_or_create_buf`, `mode_str`  |
| Module table             | Always `M`            | `local M = {}`                   |
| Type/class names         | `dot.PascalCase`      | `briefing.Config`, `briefing.Keymap` |
| User commands            | `PascalCase`          | `:Briefing`                      |
| Vim globals (tab/global) | `snake_case` prefixed | `vim.g.loaded_briefing`, `vim.t.briefing_bufnr` |
| Module file names        | Lowercase single word | `config.lua`, `ui.lua`           |

No camelCase anywhere.

## Type Annotations

Use LuaLS / EmmyLua `---@` annotations on all public and private interfaces:

```lua
---@class briefing.Keymap
---@field [1] string          lhs
---@field [2] string|fun()    action name or custom function
---@field mode? string        e.g. "ni" for normal + insert
---@field desc? string        human-readable description

---@param opts? briefing.Config
---@return integer bufnr
```

Conventions:
- Optional params/fields use `?` suffix: `opts?`, `config?`
- Union types with `|`: `string|fun()`, `briefing.Keymap|false`
- String literal enums: `"left"|"center"|"right"`
- Named returns: `---@return integer bufnr`
- Reference Neovim builtins directly: `vim.api.keyset.win_config`, `vim.wo`

## Module Structure

Every source file follows this pattern:

```lua
local M = {}

-- private helpers as local functions
local function helper() end

-- public API on the M table
function M.public() end

return M
```

Rules:
- Private functions: `local function name()` (declarations, not expressions)
- `init.lua` is a thin facade — delegates to `config.lua` and `ui.lua`
- `config.lua` self-initializes defaults at require time (`M.setup()` at bottom)
- Per-tab state lives on `vim.t.*`, not module-level locals
- `plugin/briefing.lua` uses a double-load guard via `vim.g.loaded_briefing`

## Import Conventions

```lua
-- Top-of-file require for always-needed sibling modules
local config = require("briefing.config")

-- Inline/lazy require inside functions (keeps module lightweight)
function M.setup(opts)
    require("briefing.config").setup(opts)
end

-- pcall for optional external dependencies
local ok, sidekick_cli = pcall(require, "sidekick.cli")
if not ok then
    vim.notify("Briefing: sidekick.nvim is not installed", vim.log.levels.ERROR)
    return
end
```

- All require paths are fully qualified from the plugin namespace (`"briefing.config"`)
- No relative paths
- Cross-module calls use `require("briefing")` to avoid circular deps

## Error Handling

- **User-facing errors:** `vim.notify("Briefing: <message>", vim.log.levels.ERROR)`
- **Warnings:** `vim.notify("Briefing: <message>", vim.log.levels.WARN)`
- All notifications prefixed with `"Briefing: "`
- Guard clauses with early `return` instead of nested conditionals
- `pcall` wraps optional `require` calls
- No `assert()`, `error()`, or `xpcall` — prefer graceful degradation

## Testing Conventions

Framework: plenary.nvim (busted-style: `describe`, `it`, `before_each`, `after_each`)

- Test files: `spec/<module>_spec.lua`
- Each file has a `reset()` helper for full state cleanup (close windows, wipe buffers, clear `vim.t` state, reset config)
- External deps mocked via `package.preload` / `package.loaded`
- `vim.notify` monkey-patched in tests to capture messages and levels
- Assertions: `assert.equals()`, `assert.is_true()`, `assert.is_nil()`, `assert.same()`, `assert.has_no.errors()`

## Commit Messages

Follow conventional-commit style without scopes:

```
feat: description of new feature
fix: description of bug fix
tests: add or update tests
build: build/CI changes
docs: documentation changes
chore: formatting, cleanup
```

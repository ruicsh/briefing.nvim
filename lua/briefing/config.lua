local M = {}

--- A named keymap entry for the briefing window.
--- Set a keymap to `false` in your config to disable it entirely.
---@class briefing.Keymap
---@field [1] string          lhs – the key sequence to bind
---@field [2] string|fun()    action name ("send" | "close" | "reset") or a custom function
---@field mode? string        mode characters concatenated (e.g. "ni" for normal + insert). Default: "n"
---@field desc? string        human-readable description shown in which-key / :map

--- Footer configuration for the briefing window border.
---@class briefing.Footer
---@field enabled? boolean               show the keymap hint footer (default: true)
---@field pos? "left"|"center"|"right"   footer alignment (default: "center")

---@class briefing.Window.Opts
---@field config? fun(win_config: vim.api.keyset.win_config)  called just before the window opens; mutate the table to override any option
---@field wo? vim.wo   window-local option overrides applied after the defaults
---@field bo? vim.bo   buffer-local option overrides applied after the defaults
---@field width? number    window width – values 0–1 are treated as a fraction of the editor width
---@field height? number   window height – values 0–1 are treated as a fraction of the editor height
---@field width_positional? number  window width when using cursor positioning (default: 60)
---@field height_positional? number  window height when using cursor positioning (default: 0.3)
---@field border? string   border style passed to nvim_open_win
---@field border_positional? string  border style for positional windows (default: "none")
---@field title? string    window title
---@field title_pos? "left"|"center"|"right"  title alignment
---@field footer? briefing.Footer  footer keymap hints rendered on the window border
---@field position? "center"|"cursor"|"smart"  window positioning strategy (default: "smart")

--- Adapter configuration for the briefing send action.
---@class briefing.Adapter
---@field name string|table  built-in adapter name ("sidekick" | "callback") or a custom adapter table
---@field callback? fun(resolved_text: string)  called by the callback adapter with the fully resolved prompt
---@field sidekick? briefing.SidekickAdapterConfig

--- Configuration for the sidekick adapter.
---@class briefing.SidekickAdapterConfig
---@field tool? string          sidekick CLI tool name to target (e.g. "opencode"). nil uses the active session.
---@field submit? boolean       submit the prompt automatically after appending (default: true)
---@class briefing.Config
local defaults = {
	--- Enable debug logging via vim.notify (WARN level).
	--- Messages are prefixed with "Briefing [debug]:".
	--- Default: false
	---@type boolean
	debug = false,

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
		config = nil,
		wo = {},
		bo = {},
		width = 100,
		height = 0.6,
		width_positional = 0.4,
		height_positional = 0.3,
		border = "rounded",
		border_positional = "none",
		title = " Briefing ",
		title_pos = "center",
		footer = {},
		position = "smart",
	},

	--- Named keymaps for the briefing window.
	--- Set any entry to `false` to disable that binding.
	---@type table<string, briefing.Keymap|false>
	keymaps = {
		send = { "<c-s>", "send", mode = "ni", desc = "send prompt to agent" },
		reset = { "<c-x>", "reset", mode = "ni", desc = "clear the buffer" },
		close = { "q", "close", mode = "n", desc = "close the window" },
		picker = { "<Tab>", "picker", mode = "i", desc = "picker after :" },
	},
}

---@type briefing.Config
M.options = {}

---@param opts? briefing.Config
function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", defaults, opts or {})
end

-- Initialize with defaults
M.setup()

return M

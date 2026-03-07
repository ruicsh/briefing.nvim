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
---@field border? string   border style passed to nvim_open_win
---@field title? string    window title
---@field title_pos? "left"|"center"|"right"  title alignment
---@field footer? briefing.Footer  footer keymap hints rendered on the window border

---@class briefing.Config
local defaults = {
	---@type briefing.Window.Opts
	window = {
		config = nil,
		wo = {},
		bo = {},
		width = 100,
		height = 0.6,
		border = "rounded",
		title = " Briefing ",
		title_pos = "center",
		footer = {},
	},

	--- Named keymaps for the briefing window.
	--- Set any entry to `false` to disable that binding.
	---@type table<string, briefing.Keymap|false>
	keymaps = {
		send = { "<c-s>", "send", mode = "ni", desc = "send prompt to agent" },
		reset = { "<c-x>", "reset", mode = "ni", desc = "clear the buffer" },
		close = { "q", "close", mode = "n", desc = "close the window" },
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

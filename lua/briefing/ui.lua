local config = require("briefing.config")

local M = {}

-- Track the window and buffer handles
-- Stored per-tab: vim.t.briefing_bufnr, vim.t.briefing_winid

--- Get or create the briefing buffer for the current tab.
---@return integer bufnr
local function get_or_create_buf()
	local bufnr = vim.t.briefing_bufnr

	if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
		return bufnr
	end

	bufnr = vim.api.nvim_create_buf(false, true)
	vim.bo[bufnr].filetype = "briefing"
	vim.bo[bufnr].bufhidden = "hide"
	vim.bo[bufnr].swapfile = false

	vim.t.briefing_bufnr = bufnr
	return bufnr
end

--- Resolve a dimension value: 0–1 is treated as a fraction of `total`,
--- any other positive number is used as an absolute value.
---@param value number
---@param total number  editor width or height in cells
---@return integer
local function resolve_dim(value, total)
	if value > 0 and value <= 1 then
		return math.floor(total * value)
	end
	return math.floor(value)
end

--- Build the win_config table from the current window options.
--- Respects fractional width/height values.
---@return vim.api.keyset.win_config
local function build_win_config()
	local opts = config.options.window
	local width = resolve_dim(opts.width, vim.o.columns)
	local height = resolve_dim(opts.height, vim.o.lines)
	local col = math.floor((vim.o.columns - width) / 2)
	local row = math.floor((vim.o.lines - height) / 2)

	return {
		relative = "editor",
		width = width,
		height = height,
		col = col,
		row = row,
		style = "minimal",
		border = opts.border,
		title = opts.title,
		title_pos = opts.title_pos or "center",
	}
end

--- Built-in action handlers referenced by name in keymap entries.
---@type table<string, fun()>
local actions = {
	send = function()
		require("briefing").send()
	end,
	close = function()
		require("briefing").close()
	end,
}

--- Set buffer-local keymaps from the named keymaps config.
--- Entries set to `false` are skipped (disabled).
---@param bufnr integer
local function set_keymaps(bufnr)
	for name, km in pairs(config.options.keymaps) do
		if km ~= false then
			local lhs = km[1]
			local action = km[2]
			local handler = type(action) == "function" and action or actions[action]

			if not handler then
				vim.notify(("Briefing: unknown keymap action %q for key %q"):format(tostring(action), name), vim.log.levels.WARN)
				goto continue
			end

			-- mode string like "ni" -> { "n", "i" }
			local mode_str = km.mode or "n"
			local modes = {}
			for c in mode_str:gmatch(".") do
				modes[#modes + 1] = c
			end

			vim.keymap.set(modes, lhs, handler, {
				buffer = bufnr,
				silent = true,
				nowait = true,
				desc = km.desc or ("Briefing " .. name),
			})

			::continue::
		end
	end
end

--- Open (or focus) the briefing floating window.
function M.open()
	local bufnr = get_or_create_buf()

	-- If the window is already open, just focus it
	local winid = vim.t.briefing_winid
	if winid and vim.api.nvim_win_is_valid(winid) then
		vim.api.nvim_set_current_win(winid)
		return
	end

	-- Build win_config and allow the user callback to mutate it
	local wc = build_win_config()
	if config.options.window.config then
		config.options.window.config(wc)
	end

	-- Open the floating window
	winid = vim.api.nvim_open_win(bufnr, true, wc)
	vim.t.briefing_winid = winid

	-- Window-local options tuned for prose writing (defaults)
	vim.wo[winid].wrap = true
	vim.wo[winid].linebreak = true
	vim.wo[winid].number = false
	vim.wo[winid].relativenumber = false
	vim.wo[winid].signcolumn = "no"

	-- Apply user window-option overrides
	local wo = config.options.window.wo or {}
	for k, v in pairs(wo) do
		vim.wo[winid][k] = v
	end

	-- Apply user buffer-option overrides
	local bo = config.options.window.bo or {}
	for k, v in pairs(bo) do
		vim.bo[bufnr][k] = v
	end

	set_keymaps(bufnr)

	vim.cmd("startinsert")
end

--- Close the floating window, keeping the buffer alive.
function M.close()
	local winid = vim.t.briefing_winid
	if winid and vim.api.nvim_win_is_valid(winid) then
		vim.api.nvim_win_close(winid, false)
	end
	vim.t.briefing_winid = nil
end

--- Return the current buffer contents as a single string.
---@return string
function M.get_text()
	local bufnr = vim.t.briefing_bufnr
	if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
		return ""
	end
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	return table.concat(lines, "\n")
end

return M

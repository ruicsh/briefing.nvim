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

--- Build the footer string from the active keymaps config.
--- Returns nil when footer is disabled via window.footer.enabled = false.
--- Keymaps are rendered in fixed display order: send, reset, close.
---@return string|nil
local function build_footer()
	local footer_cfg = config.options.window.footer or {}
	if footer_cfg.enabled == false then
		return nil
	end

	local display_order = { "send", "reset", "close" }
	local parts = {}
	for _, name in ipairs(display_order) do
		local km = config.options.keymaps[name]
		if km and km ~= false then
			local key = vim.fn.keytrans(vim.keycode(km[1]))
			parts[#parts + 1] = key .. " " .. name
		end
	end

	if #parts == 0 then
		return nil
	end

	return " " .. table.concat(parts, "  ") .. " "
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

	local wc = {
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

	local footer_str = build_footer()
	if footer_str then
		local footer_cfg = opts.footer or {}
		wc.footer = footer_str
		wc.footer_pos = footer_cfg.pos or "center"
	end

	return wc
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
	reset = function()
		local bufnr = vim.t.briefing_bufnr
		if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
		end
	end,
	pick_buffer = function()
		require("briefing.picker").on_tab()
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

			-- mode: a string like "ni" -> { "n", "i" }, or already a table like { "n", "i" }
			local modes
			if type(km.mode) == "table" then
				modes = km.mode
			else
				local mode_str = type(km.mode) == "string" and km.mode or "n"
				modes = {}
				for c in string.gmatch(mode_str, ".") do
					modes[#modes + 1] = c
				end
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

	-- Remember the caller's window and mode so close() can restore them
	vim.t.briefing_prev_winid = vim.api.nvim_get_current_win()
	local mode = vim.api.nvim_get_mode().mode
	vim.t.briefing_prev_mode = mode

	-- When called from visual mode, capture the selection content immediately.
	-- Use yank to capture (more reliable than getpos) and also capture positions
	-- for restoration when closing.
	local visual_modes = { v = true, V = true, ["\22"] = true }
	if visual_modes[mode] then
		-- Yank to register z for resolve
		vim.cmd('normal! "zY')

		-- Capture positions for close restoration
		local anchor = vim.fn.getpos("v")
		local cursor = vim.fn.getpos(".")
		if anchor[2] > 0 and cursor[2] > 0 then
			vim.t.briefing_prev_vis_anchor = anchor[2] .. "," .. anchor[3]
			vim.t.briefing_prev_vis_cursor = cursor[2] .. "," .. cursor[3]
		end
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
	vim.wo[winid].number = true
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

	-- If opened from visual mode, auto-insert #selection token with spacing
	if visual_modes[mode] then
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "#selection", "", "" })
		vim.api.nvim_win_set_cursor(winid, { 3, 0 })
	else
		vim.cmd("startinsert")
	end
end

--- Close the floating window, keeping the buffer alive.
function M.close()
	local winid = vim.t.briefing_winid
	if winid and vim.api.nvim_win_is_valid(winid) then
		vim.api.nvim_win_close(winid, false)
	end
	vim.t.briefing_winid = nil

	-- Restore the previous window's mode. startinsert leaks into the caller's
	-- window when the float is closed, so explicitly stop insert mode unless
	-- the caller was already in insert mode when open() was called.
	local prev_winid = vim.t.briefing_prev_winid
	local prev_mode = vim.t.briefing_prev_mode
	local prev_vis_anchor = vim.t.briefing_prev_vis_anchor
	local prev_vis_cursor = vim.t.briefing_prev_vis_cursor
	vim.t.briefing_prev_winid = nil
	vim.t.briefing_prev_mode = nil
	vim.t.briefing_prev_vis_anchor = nil
	vim.t.briefing_prev_vis_cursor = nil

	if prev_winid and vim.api.nvim_win_is_valid(prev_winid) then
		vim.api.nvim_set_current_win(prev_winid)
		local visual_modes = { v = true, V = true, ["\22"] = true }
		local buf = vim.api.nvim_win_get_buf(prev_winid)
		-- Only restore visual selection if we have valid anchor/cursor AND the marks
		-- resolve to valid positions in the current buffer. This guards against stale
		-- marks from a previous session or when #selection resolved to empty.
		if visual_modes[prev_mode] and prev_vis_anchor and prev_vis_cursor then
			local al, ac = prev_vis_anchor:match("^(%d+),(%d+)$")
			local cl, cc = prev_vis_cursor:match("^(%d+),(%d+)$")
			if al and cl then
				local buf_len = vim.api.nvim_buf_line_count(buf)
				-- Validate line numbers are within buffer bounds
				if tonumber(al) >= 1 and tonumber(al) <= buf_len and tonumber(cl) >= 1 and tonumber(cl) <= buf_len then
					-- Restore the visual selection: place '< and '> then re-enter visual mode.
					-- nvim_buf_set_mark uses 1-based lines, 0-based cols; getpos returns 1-based cols
					vim.api.nvim_buf_set_mark(buf, "<", tonumber(al), tonumber(ac) - 1, {})
					vim.api.nvim_buf_set_mark(buf, ">", tonumber(cl), tonumber(cc) - 1, {})
					vim.cmd("normal! `<" .. prev_mode .. "`>")
				end
			end
		elseif prev_mode == "i" or prev_mode == "ic" or prev_mode == "ix" then
			vim.cmd("startinsert")
		else
			vim.cmd("stopinsert")
		end
	end
end

--- Return the window handle that was active before the briefing window opened.
--- Returns nil when no briefing window has been opened in this tab yet.
---@return integer|nil
function M.get_prev_winid()
	return vim.t.briefing_prev_winid
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

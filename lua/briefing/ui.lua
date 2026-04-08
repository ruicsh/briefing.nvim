local config = require("briefing.config")
local dlog = require("briefing.log").dlog

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
	vim.bo[bufnr].buftype = "nofile"
	vim.bo[bufnr].filetype = "briefing"
	vim.bo[bufnr].bufhidden = "hide"
	vim.bo[bufnr].swapfile = false

	vim.t.briefing_bufnr = bufnr
	return bufnr
end

--- Resolve a dimension value: 0–1 is treated as a fraction of `total`.
---@param value number
---@param total number
---@return integer
local function resolve_dim(value, total)
	if value > 0 and value <= 1 then
		return math.floor(total * value)
	end
	return math.floor(value)
end

--- Build the footer string from the active keymaps config.
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
---@param is_positional boolean  whether this is a positional context (selection, git hunk, etc.)
---@return vim.api.keyset.win_config
local function build_win_config(is_positional)
	local opts = config.options.window
	local position = opts.position or "smart"
	local use_cursor_pos = (position == "cursor") or (position == "smart" and is_positional)
	dlog(
		"build_win_config: position="
			.. position
			.. ", is_positional="
			.. tostring(is_positional)
			.. ", use_cursor_pos="
			.. tostring(use_cursor_pos)
	)

	-- Use smaller dimensions for positional (annotation-style) windows
	local width, height
	if use_cursor_pos then
		width = resolve_dim(opts.width_positional or 60, vim.o.columns)
		height = resolve_dim(opts.height_positional or 0.3, vim.o.lines)
		dlog("build_win_config: using positional dimensions: width=" .. width .. ", height=" .. height)
	else
		width = resolve_dim(opts.width, vim.o.columns)
		height = resolve_dim(opts.height, vim.o.lines)
		dlog("build_win_config: using centered dimensions: width=" .. width .. ", height=" .. height)
	end

	local row, col, relative, border
	if use_cursor_pos then
		-- Smart inline positioning with offset to preserve context
		local offset = 3 -- Gap between cursor and window (lines of context to preserve)
		local cursor_row = vim.fn.screenrow()
		local space_below = vim.o.lines - cursor_row
		local space_above = cursor_row - 1

		dlog(
			"build_win_config: cursor_row="
				.. cursor_row
				.. ", space_above="
				.. space_above
				.. ", space_below="
				.. space_below
				.. ", height="
				.. height
				.. ", offset="
				.. offset
		)

		if space_below >= height + offset + 1 then
			-- Enough space below cursor with offset
			relative = "cursor"
			row = offset + 1 -- Position below cursor with gap
			col = 0
			border = opts.border
			dlog("build_win_config: positioning BELOW cursor with offset, row=" .. row)
		elseif space_above >= height + offset then
			-- Not enough space below, place above cursor with offset
			relative = "cursor"
			row = -height - offset -- Position above cursor with gap
			col = 0
			border = opts.border
			dlog("build_win_config: positioning ABOVE cursor with offset, row=" .. row)
		else
			-- Not enough space either way, fall back to centered (but keep smaller dims)
			relative = "editor"
			row = math.floor((vim.o.lines - height) / 2)
			col = math.floor((vim.o.columns - width) / 2)
			border = opts.border
			dlog("build_win_config: FALLBACK to centered due to insufficient space, row=" .. row)
		end
	else
		-- Center in editor
		relative = "editor"
		row = math.floor((vim.o.lines - height) / 2)
		col = math.floor((vim.o.columns - width) / 2)
		border = opts.border
		dlog("build_win_config: CENTERED at row=" .. row)
	end

	local wc = {
		relative = relative,
		width = width,
		height = height,
		col = col,
		row = row,
		style = "minimal",
		border = border,
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
	picker = function()
		require("briefing.picker").on_tab()
	end,
}

--- Set buffer-local keymaps from the named keymaps config.
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

--- Visual mode state captured at open() time for restoration in close().
---@class VisualState
---@field anchor string|nil  "line,col" format
---@field cursor string|nil  "line,col" format
---@field screen_row integer|nil  screen row position for window positioning

--- Capture visual selection state if currently in visual mode.
--- Yanks the selection to register z for later resolution.
---@return VisualState
local function capture_visual_state()
	local mode = vim.api.nvim_get_mode().mode
	local visual_modes = { v = true, V = true, ["\22"] = true }

	if not visual_modes[mode] then
		dlog("capture_visual_state: not in visual mode, mode=" .. mode)
		return { anchor = nil, cursor = nil, screen_row = nil }
	end

	dlog("capture_visual_state: in visual mode, mode=" .. mode)

	-- Capture screen position BEFORE yanking (yank exits visual mode)
	local screen_row = vim.fn.screenrow()
	dlog("capture_visual_state: captured screen_row=" .. screen_row)

	-- Yank to register z for resolve
	vim.cmd('normal! "zY')

	-- Capture positions for close restoration
	local anchor = vim.fn.getpos("v")
	local cursor = vim.fn.getpos(".")

	-- Capture source filetype for selection resolution
	local current_buf = vim.api.nvim_get_current_buf()
	vim.t.briefing_prev_filetype = vim.bo[current_buf].filetype or ""

	local result = { anchor = nil, cursor = nil, screen_row = screen_row }
	if anchor[2] > 0 and cursor[2] > 0 then
		result.anchor = anchor[2] .. "," .. anchor[3]
		result.cursor = cursor[2] .. "," .. cursor[3]
	end

	return result
end

--- Restore visual selection if prev_mode was visual mode.
---@param winid integer  previous window to restore selection in
---@param prev_mode string  mode string from when open() was called
---@param vis_state VisualState  visual state from capture_visual_state()
local function restore_visual_selection(winid, prev_mode, vis_state)
	local visual_modes = { v = true, V = true, ["\22"] = true }
	if not visual_modes[prev_mode] or not vis_state.anchor or not vis_state.cursor then
		return
	end

	local buf = vim.api.nvim_win_get_buf(winid)
	local al, ac = vis_state.anchor:match("^(%d+),(%d+)$")
	local cl, cc = vis_state.cursor:match("^(%d+),(%d+)$")

	if not al or not cl then
		return
	end

	local buf_len = vim.api.nvim_buf_line_count(buf)
	-- Validate line numbers are within buffer bounds
	if tonumber(al) >= 1 and tonumber(al) <= buf_len and tonumber(cl) >= 1 and tonumber(cl) <= buf_len then
		-- Restore the visual selection: place '< and '> then re-enter visual mode
		vim.api.nvim_buf_set_mark(buf, "<", tonumber(al), tonumber(ac) - 1, {})
		vim.api.nvim_buf_set_mark(buf, ">", tonumber(cl), tonumber(cc) - 1, {})
		vim.cmd("normal! `<" .. prev_mode .. "`>")
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
	vim.t.briefing_prev_mode = vim.api.nvim_get_mode().mode

	-- Capture visual selection state if in visual mode
	local vis_state = capture_visual_state()
	vim.t.briefing_prev_vis_anchor = vis_state.anchor
	vim.t.briefing_prev_vis_cursor = vis_state.cursor

	-- Detect positional context (selection, git hunks, etc.)
	local is_positional = vis_state.anchor ~= nil
	dlog("open: is_positional from visual=" .. tostring(is_positional))
	local fugitive_ctx = nil
	local codediff_ctx = nil

	if not is_positional then
		local prev_winid = vim.t.briefing_prev_winid
		local fugitive = require("briefing.context.fugitive")
		fugitive_ctx = prev_winid and fugitive.get_context(prev_winid) or nil
		is_positional = fugitive_ctx ~= nil
		dlog("open: is_positional from fugitive=" .. tostring(is_positional))

		-- Check for codediff.nvim if not a fugitive context
		if not is_positional and prev_winid then
			local codediff = require("briefing.context.codediff")
			codediff_ctx = codediff.get_context(prev_winid)
			is_positional = codediff_ctx ~= nil
			dlog("open: is_positional from codediff=" .. tostring(is_positional))
		end
	end
	dlog("open: final is_positional=" .. tostring(is_positional))

	-- Build win_config and allow the user callback to mutate it
	local wc = build_win_config(is_positional)
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
	vim.wo[winid].list = false

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

	-- If opened from visual mode, auto-insert descriptive text and #selection token
	if vis_state.anchor then
		local prev_winid = vim.t.briefing_prev_winid
		local bufname = prev_winid and vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(prev_winid)) or ""
		local lines
		if bufname ~= "" then
			lines = { "on file: #filepath", "", "#selection", "", "" }
		else
			lines = { "#selection", "", "" }
		end
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
		vim.api.nvim_win_set_cursor(winid, { #lines, 0 })
		vim.cmd("startinsert")
	elseif fugitive_ctx then
		-- Insert appropriate token based on fugitive context
		if fugitive_ctx.type == "hunk" then
			-- On a diff/hunk line - insert #diff:hunk to get just this hunk
			-- The diff resolver will use the prev_winid to figure out which file and line
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "#diff:hunk", "", "" })
			vim.api.nvim_win_set_cursor(winid, { 3, 0 })
		elseif fugitive_ctx.type == "file" then
			-- On a filename line - insert #diff:<filename> to get whole file diff
			local token = "#diff:" .. fugitive_ctx.path
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { token, "", "" })
			vim.api.nvim_win_set_cursor(winid, { 3, 0 })
		elseif fugitive_ctx.type == "diff" then
			-- On a git diff buffer but not on a hunk line - insert #diff to get whole diff
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "#diff", "", "" })
			vim.api.nvim_win_set_cursor(winid, { 3, 0 })
		else
			vim.cmd("startinsert")
		end
	elseif codediff_ctx then
		-- Insert #diff:hunk for codediff context
		-- The diff resolver will use the prev_winid to extract the hunk
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "#diff:hunk", "", "" })
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

	-- Restore the previous window's mode
	local prev_winid = vim.t.briefing_prev_winid
	local prev_mode = vim.t.briefing_prev_mode
	local vis_state = {
		anchor = vim.t.briefing_prev_vis_anchor,
		cursor = vim.t.briefing_prev_vis_cursor,
	}

	vim.t.briefing_prev_winid = nil
	vim.t.briefing_prev_mode = nil
	vim.t.briefing_prev_vis_anchor = nil
	vim.t.briefing_prev_vis_cursor = nil
	vim.t.briefing_prev_filetype = nil

	if prev_winid and vim.api.nvim_win_is_valid(prev_winid) then
		vim.api.nvim_set_current_win(prev_winid)

		restore_visual_selection(prev_winid, prev_mode, vis_state)

		if prev_mode == "i" or prev_mode == "ic" or prev_mode == "ix" then
			vim.cmd("startinsert")
		else
			vim.cmd("stopinsert")
		end
	end
end

--- Return the window handle that was active before the briefing window opened.
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

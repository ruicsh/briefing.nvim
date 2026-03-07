local M = {}

--- Resolve the `#selection` context variable.
--- Reads the visual selection coordinates stored by ui.open() when the briefing
--- window was opened from visual mode.  Falls back gracefully when no selection
--- is available.
---@param prev_winid? integer  the window that was active before briefing opened
---@return string
function M.resolve(prev_winid)
	local anchor_str = vim.t.briefing_prev_vis_anchor
	local cursor_str = vim.t.briefing_prev_vis_cursor

	if not anchor_str or not cursor_str then
		vim.notify("Briefing: #selection — no visual selection available", vim.log.levels.WARN)
		return ""
	end

	local al, ac = anchor_str:match("^(%d+),(%d+)$")
	local cl, cc = cursor_str:match("^(%d+),(%d+)$")
	if not al then
		vim.notify("Briefing: #selection — invalid selection coordinates", vim.log.levels.WARN)
		return ""
	end

	al, ac, cl, cc = tonumber(al), tonumber(ac), tonumber(cl), tonumber(cc)

	-- Determine which window/buffer to read from
	local winid = (prev_winid and vim.api.nvim_win_is_valid(prev_winid)) and prev_winid or vim.api.nvim_get_current_win()
	local bufnr = vim.api.nvim_win_get_buf(winid)

	if not vim.api.nvim_buf_is_valid(bufnr) then
		vim.notify("Briefing: #selection — no valid buffer found", vim.log.levels.WARN)
		return ""
	end

	-- Normalise so start_line <= end_line (anchor and cursor can be in any order)
	local start_line, start_col, end_line, end_col
	if al < cl or (al == cl and ac <= cc) then
		start_line, start_col = al, ac
		end_line, end_col = cl, cc
	else
		start_line, start_col = cl, cc
		end_line, end_col = al, ac
	end

	-- getpos() returns 1-based lines and cols; nvim_buf_get_lines uses 0-based
	local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
	if #lines == 0 then
		return ""
	end

	-- Trim columns: last line up to end_col, first line from start_col
	-- getpos() columns are 1-based; string.sub is also 1-based
	lines[#lines] = lines[#lines]:sub(1, end_col)
	lines[1] = lines[1]:sub(start_col)

	local lang = vim.bo[bufnr].filetype or ""
	local content = table.concat(lines, "\n")

	return ("```%s\n%s\n```"):format(lang, content)
end

return M

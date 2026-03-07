local M = {}

--- Resolve the `#selection` context variable.
--- First checks if content was already captured at open() time. If not,
--- falls back to reading from the source buffer using stored positions.
---@param prev_winid? integer  the window that was active before briefing opened
---@return string
function M.resolve(prev_winid)
	-- Read directly from register z (yanked at open time from visual selection)
	local content = vim.fn.getreg("z")
	if content and content ~= "" then
		content = content:gsub("\n$", "") -- strip trailing newline from yank
		local lang = vim.bo[vim.api.nvim_win_get_buf(vim.api.nvim_get_current_win())].filetype or ""
		return ("```%s\n%s\n```"):format(lang, content)
	end

	-- Fall back to reading from positions (for backwards compatibility)
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

	-- Trim columns: last line up to end_col, first line from start_col.
	-- getpos() columns are 1-based; string.sub is also 1-based.
	-- Single-line selections must be trimmed in one step: trimming lines[#lines]
	-- first mutates lines[1] (same slot), so a subsequent sub(start_col) would
	-- operate on the already-truncated string and clip the wrong characters.
	if #lines == 1 then
		lines[1] = lines[1]:sub(start_col, end_col)
	else
		lines[#lines] = lines[#lines]:sub(1, end_col)
		lines[1] = lines[1]:sub(start_col)
	end

	local lang = vim.bo[bufnr].filetype or ""
	local content = table.concat(lines, "\n")

	return ("```%s\n%s\n```"):format(lang, content)
end

return M

local M = {}

local dlog = require("briefing.log").dlog

--- Check if a window's buffer is part of a codediff session.
--- This is an optional dependency - gracefully handles missing codediff.
---@param winid? integer Window handle (defaults to current window)
---@return boolean
function M.is_codediff(winid)
	local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
	if not ok then
		dlog("codediff: lifecycle module not available")
		return false
	end

	local win = winid or 0
	if win ~= 0 and not vim.api.nvim_win_is_valid(win) then
		win = 0
	end

	local bufnr = vim.api.nvim_win_get_buf(win)
	local tabpage = vim.api.nvim_win_get_tabpage(win)
	local session = lifecycle.get_session(tabpage)

	if not session then
		return false
	end

	-- Check if buffer is one of the diff panes
	local is_original = bufnr == session.original_bufnr
	local is_modified = bufnr == session.modified_bufnr

	if is_original or is_modified then
		dlog("codediff: detected codediff buffer (original=" .. tostring(is_original) .. ")")
		return true
	end

	return false
end

--- Get the context for auto-insert when opening from a codediff buffer.
--- Returns information about what token should be auto-inserted.
---@param winid? integer Window handle (defaults to current window)
---@return table|nil context Context info or nil if not applicable
---   - type: "hunk" — always hunk for codediff
---   - path: string (optional) — the file path
function M.get_context(winid)
	local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
	if not ok then
		return nil
	end

	local win = winid or 0
	if win ~= 0 and not vim.api.nvim_win_is_valid(win) then
		win = 0
	end

	local bufnr = vim.api.nvim_win_get_buf(win)
	local tabpage = vim.api.nvim_win_get_tabpage(win)
	local session = lifecycle.get_session(tabpage)

	if not session then
		return nil
	end

	-- Must be in one of the diff buffers
	local is_original = bufnr == session.original_bufnr
	local is_modified = bufnr == session.modified_bufnr

	if not is_original and not is_modified then
		return nil
	end

	-- Always use modified_path as the reference file (per user preference)
	local path = session.modified_path
	if not path or path == "" then
		path = session.original_path
	end

	dlog("codediff: context is hunk, path=" .. (path or "nil"))
	return { type = "hunk", path = path }
end

--- Get the filename and file line number from a codediff buffer at cursor position.
--- This is used when resolving #diff:hunk from a codediff buffer.
---@param winid? integer Window handle (defaults to current window)
---@return string|nil filename The filename, or nil if not found
---@return integer|nil file_line The file line number, or nil if not found
function M.get_file_info_for_hunk(winid)
	local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
	if not ok then
		return nil, nil
	end

	local win = winid or 0
	if win ~= 0 and not vim.api.nvim_win_is_valid(win) then
		win = 0
	end

	local bufnr = vim.api.nvim_win_get_buf(win)
	local cursor_line = vim.api.nvim_win_get_cursor(win)[1]
	local tabpage = vim.api.nvim_win_get_tabpage(win)
	local session = lifecycle.get_session(tabpage)

	if not session then
		return nil, nil
	end

	-- Determine which side we're on
	local is_original = bufnr == session.original_bufnr
	local is_modified = bufnr == session.modified_bufnr

	if not is_original and not is_modified then
		return nil, nil
	end

	-- Get filename - always prefer modified side
	local filename = session.modified_path
	if not filename or filename == "" then
		filename = session.original_path
	end

	if not filename or filename == "" then
		return nil, nil
	end

	-- Calculate file line from the diff result
	local diff_result = session.stored_diff_result
	if not diff_result or not diff_result.changes then
		return filename, cursor_line
	end

	-- Find the hunk containing the cursor line
	for _, mapping in ipairs(diff_result.changes) do
		local range = is_original and mapping.original or mapping.modified
		if not range then
			goto continue
		end

		-- Check if cursor is within this hunk's range
		if cursor_line >= range.start_line and cursor_line <= range.end_line then
			-- Calculate the actual file line number
			local offset = cursor_line - range.start_line
			-- For the modified side, the line number directly corresponds to the file
			-- For the original side, we'd need to map through git
			local file_line = range.start_line + offset
			dlog("codediff: found hunk at buffer line " .. cursor_line .. ", file line " .. file_line)
			return filename, file_line
		end

		::continue::
	end

	-- Cursor not in a hunk - return cursor line as fallback
	dlog("codediff: cursor not in hunk, using cursor line " .. cursor_line)
	return filename, cursor_line
end

return M

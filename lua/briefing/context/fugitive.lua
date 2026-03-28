local M = {}

local dlog = require("briefing.log").dlog

--- Check if a buffer is a fugitive buffer.
--- This includes:
--- - Fugitive summary buffer (filetype "fugitive")
--- - Fugitive diff buffer (buffer name starting with "fugitive://")
---@param winid? integer Window handle (defaults to current window)
---@return boolean
function M.is_fugitive(winid)
	local win = winid or 0
	if win ~= 0 and not vim.api.nvim_win_is_valid(win) then
		win = 0
	end

	local bufnr = vim.api.nvim_win_get_buf(win)
	local bufname = vim.api.nvim_buf_get_name(bufnr)
	local filetype = vim.bo[bufnr].filetype

	-- Check for fugitive:// URL (diff buffers)
	if bufname:match("^fugitive://") then
		dlog("fugitive: detected fugitive:// buffer")
		return true
	end

	-- Check for summary buffer (filetype "fugitive" - fugitive sets this)
	if filetype == "fugitive" then
		dlog("fugitive: detected summary buffer (filetype=fugitive)")
		return true
	end

	dlog("fugitive: not a fugitive buffer")
	return false
end

--- Check if a buffer is a git diff buffer (filetype "git").
--- These are diff buffers created by commands like `:Git diff HEAD %`
---@param winid? integer Window handle (defaults to current window)
---@return boolean
function M.is_git_diff(winid)
	local win = winid or 0
	if win ~= 0 and not vim.api.nvim_win_is_valid(win) then
		win = 0
	end

	local bufnr = vim.api.nvim_win_get_buf(win)
	local filetype = vim.bo[bufnr].filetype

	if filetype == "git" then
		dlog("fugitive: detected git diff buffer (filetype=git)")
		return true
	end

	return false
end

--- Find filename in a git diff buffer content.
--- Searches for "diff --git a/path b/path" or "+++ b/path" lines
---@param winid integer Window handle
---@return string|nil filename The filename, or nil if not found
local function find_filename_in_git_diff(winid)
	local bufnr = vim.api.nvim_win_get_buf(winid)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	for _, line in ipairs(lines) do
		-- Try to extract from "diff --git a/path b/path"
		local _, new_path = line:match("^diff %-%-git a/(.+) b/(.+)$")
		if new_path then
			dlog("fugitive: found filename in diff --git line: " .. new_path)
			return new_path
		end

		-- Try to extract from "+++ b/path"
		local file_path = line:match("^%+%+%+ b/(.+)$")
		if file_path then
			dlog("fugitive: found filename in +++ line: " .. file_path)
			return file_path
		end
	end

	return nil
end

--- Check if the cursor is on a hunk line in a git diff buffer.
--- Hunk lines are lines starting with +, -, or space (context/added/removed)
--- that appear after a hunk header.
---@param winid? integer Window handle (defaults to current window)
---@return boolean
local function is_git_diff_hunk_line(winid)
	local win = winid or 0
	if win ~= 0 and not vim.api.nvim_win_is_valid(win) then
		win = 0
	end

	local cursor_line = vim.api.nvim_win_get_cursor(win)[1]
	local bufnr = vim.api.nvim_win_get_buf(win)
	local lines = vim.api.nvim_buf_get_lines(bufnr, cursor_line - 1, cursor_line, false)

	if #lines == 0 then
		return false
	end

	local line = lines[1]

	-- Hunk lines start with +, -, or space (but not +++ or --- which are headers)
	if line:match("^%+%+%+") or line:match("^%-%-%-") then
		return false
	end

	if line:match("^[%+%-%s]") then
		dlog("fugitive: detected git diff hunk line: " .. line:sub(1, 30))
		return true
	end

	return false
end

--- Check if the current line in a fugitive summary buffer is a diff line.
--- Diff lines in fugitive summary buffers are indented with a space
--- and start with + or - (representing added/removed lines).
---@param winid? integer Window handle (defaults to current window)
---@return boolean
local function is_diff_line(winid)
	local win = winid or 0
	if win ~= 0 and not vim.api.nvim_win_is_valid(win) then
		win = 0
	end

	local bufnr = vim.api.nvim_win_get_buf(win)
	local cursor_line = vim.api.nvim_win_get_cursor(win)[1]
	local lines = vim.api.nvim_buf_get_lines(bufnr, cursor_line - 1, cursor_line, false)

	if #lines == 0 then
		return false
	end

	local line = lines[1]
	dlog("fugitive: checking diff line content: " .. line:sub(1, 50))
	-- Diff lines in fugitive summary start with + or - (optionally with leading space)
	local is_diff = line:match("^[%+%-]") ~= nil or line:match("^ [%+%-]") ~= nil
	if is_diff then
		dlog("fugitive: detected diff line: " .. line:sub(1, 30))
	end
	return is_diff
end

--- Get the filename under the cursor in a fugitive buffer.
--- In fugitive summary buffers, filenames are the <cfile> (file under cursor).
--- In fugitive:// buffers, we extract from the URL.
---@param winid? integer Window handle (defaults to current window)
---@return string|nil filename The filename, or nil if not found
function M.get_filename(winid)
	local win = winid or 0
	if win ~= 0 and not vim.api.nvim_win_is_valid(win) then
		win = 0
	end

	local bufnr = vim.api.nvim_win_get_buf(win)
	local bufname = vim.api.nvim_buf_get_name(bufnr)

	-- For fugitive:// URLs, parse out the file path
	-- Format: fugitive://<repo-path>//<sha>/<path>
	-- Example: fugitive:///path/to/repo//commit123/lua/file.lua
	if bufname:match("^fugitive://") then
		-- Pattern matches everything after the second //
		-- The format is: fugitive://<repo-path>//<ref>/<filepath>
		-- We want to extract the <filepath> part
		local filepath = bufname:match("^fugitive://.-//.-/(.+)$")
		if filepath then
			dlog("fugitive: extracted path from fugitive:// URL: " .. filepath)
			return filepath
		end
		-- Fallback: try to get everything after the last slash
		filepath = bufname:match("^fugitive://.+/(.-)//.-/(.+)$")
		if filepath then
			dlog("fugitive: extracted path from fugitive:// URL (fallback 1): " .. filepath)
			return filepath
		end
	end

	-- For summary buffers, use expand('<cfile>') in the context of the window
	local current_win = vim.api.nvim_get_current_win()
	vim.api.nvim_set_current_win(win)
	local filename = vim.fn.expand("<cfile>")
	vim.api.nvim_set_current_win(current_win)

	-- Verify filename looks like a path (has / or .) and is not just a word
	if filename and filename ~= "" and not filename:match("^%s*$") and (filename:match("/") or filename:match("%.")) then
		dlog("fugitive: got filename from <cfile>: " .. filename)
		return filename
	end

	return nil
end

--- Find the filename for a diff line by searching backwards.
--- In fugitive summary buffers, diff lines are indented, and the filename
--- is on a line starting with M, A, D, ?, etc. above the diff.
---@param winid integer Window handle
---@param cursor_line integer 1-based cursor line
---@return string|nil filename The filename, or nil if not found
local function find_filename_for_diff(winid, cursor_line)
	local bufnr = vim.api.nvim_win_get_buf(winid)

	-- Search backwards from cursor line
	for line_num = cursor_line - 1, 1, -1 do
		local lines = vim.api.nvim_buf_get_lines(bufnr, line_num - 1, line_num, false)
		if #lines > 0 then
			local line = lines[1]
			-- Look for file status lines: M <path>, A <path>, D <path>, ? <path>, etc.
			-- These lines don't start with space and have a status char followed by space
			local status, filepath = line:match("^([MAD?]) (.+)$")
			if status and filepath then
				dlog("fugitive: found filename for diff: " .. filepath .. " (status: " .. status .. ")")
				return filepath
			end
			-- Also check for renamed files: Rxxx <old> <new>
			local rename_status, new_path = line:match("^(R%d%d%d) %S+ (.+)$")
			if rename_status and new_path then
				dlog("fugitive: found filename for diff (rename): " .. new_path)
				return new_path
			end
		end
	end

	return nil
end

--- Get the file line number from cursor position in a fugitive diff.
--- In fugitive summary buffers, we need to parse the hunk header to calculate
--- the actual file line number where the cursor is positioned.
---@param winid integer Window handle
---@param cursor_line integer 1-based cursor line
---@return integer|nil file_line The file line number, or nil if not found
local function get_file_line_from_fugitive_diff(winid, cursor_line)
	local bufnr = vim.api.nvim_win_get_buf(winid)
	local hunk_header_line = nil
	local hunk_new_start = nil

	-- Search backwards from cursor to find hunk header (@@ line)
	for line_num = cursor_line - 1, 1, -1 do
		local lines = vim.api.nvim_buf_get_lines(bufnr, line_num - 1, line_num, false)
		if #lines > 0 then
			local line = lines[1]
			-- Hunk header format: @@ -start,count +start,count @@
			local _, _, new_start, _ = line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
			if new_start then
				hunk_header_line = line_num
				hunk_new_start = tonumber(new_start)
				dlog("fugitive: found hunk header at line " .. line_num .. ", new_start=" .. new_start)
				break
			end
		end
	end

	if not hunk_header_line then
		dlog("fugitive: no hunk header found")
		return nil
	end

	-- Count lines from hunk header to cursor
	-- Only count lines that affect the new file (+ lines and context lines)
	local offset = 0
	for line_num = hunk_header_line + 1, cursor_line - 1 do
		local lines = vim.api.nvim_buf_get_lines(bufnr, line_num - 1, line_num, false)
		if #lines > 0 then
			local line = lines[1]
			-- Lines affecting new file: + (added) or  (context)
			-- - (removed) lines don't affect new file line count
			if line:match("^[%+]") or line:match("^ ") then
				offset = offset + 1
			end
		end
	end

	-- The line at cursor also counts
	offset = offset + 1

	local file_line = hunk_new_start + offset - 1
	dlog(
		"fugitive: calculated file line "
			.. file_line
			.. " (hunk_new_start="
			.. hunk_new_start
			.. ", offset="
			.. offset
			.. ")"
	)
	return file_line
end

--- Get the context for auto-insert when opening from a fugitive buffer.
--- Returns information about what token should be auto-inserted.
---@param winid? integer Window handle (defaults to current window)
---@return table|nil context Context info or nil if not applicable
---   - type: "hunk" | "file" | "diff" — what type of context
---   - path: string (optional) — the file path (for hunk or file types)
function M.get_context(winid)
	local win = winid or 0
	if win ~= 0 and not vim.api.nvim_win_is_valid(win) then
		win = 0
	end

	-- Check if we're in a git diff buffer (filetype "git")
	if M.is_git_diff(win) then
		local filename = find_filename_in_git_diff(win)

		-- Check if on a hunk line
		if is_git_diff_hunk_line(win) then
			if filename then
				dlog("fugitive: context is hunk (git diff buffer): " .. filename)
				return { type = "hunk", path = filename }
			else
				dlog("fugitive: context is hunk (git diff buffer) but no filename found")
				return { type = "hunk" }
			end
		end

		-- Not on a hunk line - return diff context
		if filename then
			dlog("fugitive: context is diff (git diff buffer): " .. filename)
			return { type = "diff", path = filename }
		else
			dlog("fugitive: context is diff (git diff buffer)")
			return { type = "diff" }
		end
	end

	-- First check if we're in a fugitive buffer
	if not M.is_fugitive(win) then
		return nil
	end

	local bufnr = vim.api.nvim_win_get_buf(win)
	local bufname = vim.api.nvim_buf_get_name(bufnr)
	local filetype = vim.bo[bufnr].filetype
	dlog("fugitive: buffer type - filetype=" .. filetype .. " bufname=" .. bufname:sub(1, 50))

	-- For summary buffer (filetype=fugitive), check what line we're on
	if filetype == "fugitive" then
		local cursor_line = vim.api.nvim_win_get_cursor(win)[1]

		-- Check if on a diff line
		if is_diff_line(win) then
			-- Find the associated filename by searching backwards
			local filename = find_filename_for_diff(win, cursor_line)
			if filename then
				dlog("fugitive: context is hunk (diff line in summary): " .. filename)
				return { type = "hunk", path = filename }
			else
				dlog("fugitive: context is hunk (diff line in summary) but no filename found")
				return { type = "hunk" }
			end
		end

		-- Check if on a filename line (not a diff line, but has <cfile>)
		local filename = M.get_filename(win)
		if filename then
			dlog("fugitive: context is file: " .. filename)
			return { type = "file", path = filename }
		end

		dlog("fugitive: no specific context detected for summary buffer")
		return nil
	end

	-- For fugitive:// diff buffers (not summary), we're always in diff context
	-- These buffers have filetype "diff" or empty filetype
	if bufname:match("^fugitive://") then
		local filename = M.get_filename(win)
		if filename then
			dlog("fugitive: context is hunk (fugitive:// diff buffer): " .. filename)
			return { type = "hunk", path = filename }
		end
		dlog("fugitive: fugitive:// buffer but no filename found")
		return nil
	end

	dlog("fugitive: no specific context detected")
	return nil
end

--- Get the filename and file line number from a fugitive buffer at cursor position.
--- This is used when resolving #diff:hunk from a fugitive buffer.
---@param winid? integer Window handle (defaults to current window)
---@return string|nil filename The filename, or nil if not found
---@return integer|nil file_line The file line number, or nil if not found
function M.get_file_info_for_hunk(winid)
	local win = winid or 0
	if win ~= 0 and not vim.api.nvim_win_is_valid(win) then
		win = 0
	end

	local cursor_line = vim.api.nvim_win_get_cursor(win)[1]

	-- Find filename
	local filename = find_filename_for_diff(win, cursor_line)
	if not filename then
		return nil, nil
	end

	-- Calculate file line from hunk header
	local file_line = get_file_line_from_fugitive_diff(win, cursor_line)

	return filename, file_line
end

return M

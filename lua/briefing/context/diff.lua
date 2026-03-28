local M = {}

local dlog = require("briefing.log").dlog

--- Run a git command and return (stdout, ok).
--- `ok` is false when the exit code is non-zero.
---@param args string[]
---@return string stdout
---@return boolean ok
local function git(args)
	local completed = vim.system(args, { text = true }):wait()
	if completed.code ~= 0 then
		return (completed.stderr or ""), false
	end
	return (completed.stdout or ""), true
end

--- Wrap raw diff output in a fenced diff block.
---@param output string
---@return string
local function wrap_diff(output)
	if output == "" then
		return ""
	end
	return "```diff\n" .. output .. "\n```"
end

--- Get the cursor line number (1-based) from the specified window.
---@param winid? integer Window handle (defaults to current window)
---@return integer
local function get_cursor_line(winid)
	local win = winid or 0
	if win ~= 0 and not vim.api.nvim_win_is_valid(win) then
		win = 0
	end
	return vim.api.nvim_win_get_cursor(win)[1]
end

--- Get the buffer number from the specified window.
---@param winid? integer Window handle (defaults to current window)
---@return integer
local function get_win_buf(winid)
	local win = winid or 0
	if win ~= 0 and not vim.api.nvim_win_is_valid(win) then
		win = 0
	end
	return vim.api.nvim_win_get_buf(win)
end

--- Extract a single hunk from git diff output based on line number.
---@param diff_output string
---@param cursor_line integer
---@return string
local function extract_hunk_from_diff(diff_output, cursor_line)
	local lines = vim.split(diff_output, "\n", { plain = true })
	local result = {}
	local in_target_hunk = false
	local found_target_hunk = false
	local headers = {}

	for _, line in ipairs(lines) do
		-- Hunk header format: @@ -start,count +start,count @@
		local old_start, _, new_start, new_count = line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")

		if old_start then
			-- Calculate the range this hunk covers in the new file
			new_start = tonumber(new_start)
			new_count = tonumber(new_count) or 1
			local hunk_end = new_start + new_count - 1

			-- Check if cursor is in this hunk
			if cursor_line >= new_start and cursor_line <= hunk_end then
				in_target_hunk = true
				found_target_hunk = true
				-- Add collected headers first
				for _, header in ipairs(headers) do
					result[#result + 1] = header
				end
				result[#result + 1] = line
			elseif in_target_hunk then
				-- We've moved past the target hunk
				break
			end
		elseif in_target_hunk then
			result[#result + 1] = line
		else
			-- Collect file headers until we find the right hunk
			if line:match("^---") or line:match("^%+%+%+") or line:match("^diff %-%-git") then
				headers[#headers + 1] = line
			end
		end
	end

	if not found_target_hunk then
		return ""
	end

	return table.concat(result, "\n")
end

--- Extract a single hunk from git diff buffer content based on cursor position.
--- For git diff buffers, we track buffer line positions, not file line numbers.
---@param source_winid integer Window handle for the source window
---@return string
local function extract_hunk_from_git_diff_buffer(source_winid)
	local bufnr = get_win_buf(source_winid)
	local cursor_line = get_cursor_line(source_winid)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	local result = {}
	local in_target_hunk = false
	local found_target_hunk = false
	local file_headers = {}
	local current_buffer_line = 0

	for _, line in ipairs(lines) do
		current_buffer_line = current_buffer_line + 1

		-- Check for file-level headers
		if line:match("^diff %-%-git") then
			-- New file diff section starts
			if in_target_hunk then
				break
			end
			file_headers = { line }
		elseif line:match("^---") or line:match("^%+%+%+") or line:match("^index ") then
			file_headers[#file_headers + 1] = line
		elseif in_target_hunk then
			-- We're collecting the target hunk - check for end markers
			if line:match("^@@ ") or line:match("^diff %-%-git") then
				break
			end
			result[#result + 1] = line
		else
			-- Hunk header format: @@ -start,count +start,count @@
			local is_hunk_header = line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")

			if is_hunk_header then
				-- Check if cursor is on or after this hunk header line in the buffer
				if cursor_line >= current_buffer_line then
					in_target_hunk = true
					found_target_hunk = true
					-- Add collected file headers first
					for _, header in ipairs(file_headers) do
						result[#result + 1] = header
					end
					result[#result + 1] = line
				end
			end
		end
	end

	if not found_target_hunk then
		return ""
	end

	return table.concat(result, "\n")
end

--- Get hunk from a git diff buffer (filetype "git").
---@param source_winid integer Window handle for the source window
---@return string
local function get_git_filetype_hunk(source_winid)
	local hunk = extract_hunk_from_git_diff_buffer(source_winid)
	if hunk == "" then
		vim.notify("Briefing: #diff:hunk — cursor not in any hunk", vim.log.levels.WARN)
		return ""
	end

	dlog("hunk: git diff buffer hunk extracted")
	return wrap_diff(hunk)
end

--- Get full diff content from a git diff buffer (filetype "git").
---@param source_winid integer Window handle for the source window
---@return string
local function get_git_filetype_diff(source_winid)
	local bufnr = get_win_buf(source_winid)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local diff_content = table.concat(lines, "\n")
	return wrap_diff(diff_content)
end

--- Get hunk using git diff for the file at cursor position.
---@param source_winid integer Window handle for the source window
---@return string
local function get_git_hunk(source_winid)
	local bufnr = get_win_buf(source_winid)
	local bufname = vim.api.nvim_buf_get_name(bufnr)
	if bufname == "" then
		vim.notify("Briefing: #diff:hunk — buffer has no filename", vim.log.levels.WARN)
		return ""
	end

	local filename = vim.fn.fnamemodify(bufname, ":.")
	local cursor_line = get_cursor_line(source_winid)

	-- Use git diff with context lines to get hunks
	local out, ok = git({ "git", "diff", "-U3", "--", filename })
	if not ok then
		-- Try staged if unstaged fails or is empty
		out, ok = git({ "git", "diff", "--cached", "-U3", "--", filename })
		if not ok then
			vim.notify("Briefing: #diff:hunk — git diff failed: " .. out, vim.log.levels.WARN)
			return ""
		end
	end

	if out == "" then
		vim.notify("Briefing: #diff:hunk — no changes found in " .. filename, vim.log.levels.WARN)
		return ""
	end

	local hunk = extract_hunk_from_diff(out, cursor_line)
	if hunk == "" then
		vim.notify("Briefing: #diff:hunk — cursor not in any hunk at line " .. cursor_line, vim.log.levels.WARN)
		return ""
	end

	dlog("hunk: git found hunk at line " .. cursor_line)
	return wrap_diff(hunk)
end

--- Try to get hunk from built-in diff mode.
---@param source_winid integer Window handle for the source window
---@return string|nil
local function try_builtin_diff(source_winid)
	if not vim.wo[source_winid].diff then
		dlog("hunk: not in diff mode")
		return nil
	end

	-- In diff mode, we need to find the corresponding window with the original file
	local current_buf = get_win_buf(source_winid)
	local cursor_line = get_cursor_line(source_winid)

	-- Find the other window in diff mode
	for _, winid in ipairs(vim.api.nvim_list_wins()) do
		if winid ~= source_winid and vim.wo[winid].diff then
			local other_buf = vim.api.nvim_win_get_buf(winid)
			if other_buf ~= current_buf then
				-- Get the diff between the two buffers
				local current_lines = vim.api.nvim_buf_get_lines(current_buf, 0, -1, false)
				local other_lines = vim.api.nvim_buf_get_lines(other_buf, 0, -1, false)

				local diff_output = vim.diff(
					table.concat(other_lines, "\n") .. "\n",
					table.concat(current_lines, "\n") .. "\n",
					{ result_type = "unified", ctxlen = 3 }
				)

				if diff_output and diff_output ~= "" then
					local hunk = extract_hunk_from_diff(diff_output, cursor_line)
					if hunk ~= "" then
						dlog("hunk: built-in diff found hunk at line " .. cursor_line)
						return wrap_diff(hunk)
					end
				end
			end
		end
	end

	dlog("hunk: built-in diff - no hunk found")
	return nil
end

--- Get hunk from a fugitive buffer.
---@param source_winid integer Window handle for the source window
---@return string
local function get_fugitive_hunk(source_winid)
	local fugitive = require("briefing.context.fugitive")
	local filename, file_line = fugitive.get_file_info_for_hunk(source_winid)

	if not filename then
		vim.notify("Briefing: #diff:hunk — could not determine filename from fugitive buffer", vim.log.levels.WARN)
		return ""
	end

	if not file_line then
		vim.notify("Briefing: #diff:hunk — could not determine file line from fugitive buffer", vim.log.levels.WARN)
		return ""
	end

	-- Use git diff with context lines to get hunks
	local out, ok = git({ "git", "diff", "-U3", "--", filename })
	if not ok then
		-- Try staged if unstaged fails or is empty
		out, ok = git({ "git", "diff", "--cached", "-U3", "--", filename })
		if not ok then
			vim.notify("Briefing: #diff:hunk — git diff failed: " .. out, vim.log.levels.WARN)
			return ""
		end
	end

	if out == "" then
		vim.notify("Briefing: #diff:hunk — no changes found in " .. filename, vim.log.levels.WARN)
		return ""
	end

	local hunk = extract_hunk_from_diff(out, file_line)
	if hunk == "" then
		vim.notify("Briefing: #diff:hunk — cursor not in any hunk at line " .. file_line, vim.log.levels.WARN)
		return ""
	end

	dlog("hunk: fugitive found hunk for " .. filename .. " at line " .. file_line)
	return wrap_diff(hunk)
end

--- Resolve `#diff:buffer` — inline `git diff HEAD <buffer_file>` output.
---@param source_winid integer Window handle for the source window
---@return string
local function resolve_buffer(source_winid)
	local bufnr = vim.api.nvim_win_get_buf(source_winid)
	local name = vim.api.nvim_buf_get_name(bufnr)
	if name == "" then
		vim.notify("Briefing: #diff:buffer — buffer has no file path", vim.log.levels.WARN)
		return ""
	end

	local completed = vim.system({ "git", "diff", "HEAD", "--", name }, { text = true }):wait()

	if completed.code ~= 0 then
		vim.notify("Briefing: #diff:buffer — git diff failed: " .. (completed.stderr or ""), vim.log.levels.WARN)
		return ""
	end

	local result = completed.stdout or ""
	return wrap_diff(result)
end

--- Resolve `#diff` (no suboption) — uses buffer content for git diff buffers.
---@param source_winid integer Window handle for the source window
---@return string
local function resolve_diff(source_winid)
	-- Check if we're in a git diff buffer (filetype "git")
	local fugitive = require("briefing.context.fugitive")
	if fugitive.is_git_diff(source_winid) then
		return get_git_filetype_diff(source_winid)
	end

	-- Otherwise default to buffer-based git diff
	return resolve_buffer(source_winid)
end

--- Get hunk from a codediff buffer.
---@param source_winid integer Window handle for the source window
---@return string
local function get_codediff_hunk(source_winid)
	local codediff = require("briefing.context.codediff")
	local filename, file_line = codediff.get_file_info_for_hunk(source_winid)

	if not filename then
		vim.notify("Briefing: #diff:hunk — could not determine filename from codediff buffer", vim.log.levels.WARN)
		return ""
	end

	if not file_line then
		vim.notify("Briefing: #diff:hunk — could not determine file line from codediff buffer", vim.log.levels.WARN)
		return ""
	end

	-- Use git diff with context lines to get hunks
	local out, ok = git({ "git", "diff", "-U3", "--", filename })
	if not ok then
		-- Try staged if unstaged fails or is empty
		out, ok = git({ "git", "diff", "--cached", "-U3", "--", filename })
		if not ok then
			vim.notify("Briefing: #diff:hunk — git diff failed: " .. out, vim.log.levels.WARN)
			return ""
		end
	end

	if out == "" then
		vim.notify("Briefing: #diff:hunk — no changes found in " .. filename, vim.log.levels.WARN)
		return ""
	end

	local hunk = extract_hunk_from_diff(out, file_line)
	if hunk == "" then
		vim.notify("Briefing: #diff:hunk — cursor not in any hunk at line " .. file_line, vim.log.levels.WARN)
		return ""
	end

	dlog("hunk: codediff found hunk for " .. filename .. " at line " .. file_line)
	return wrap_diff(hunk)
end

--- Resolve `#diff:hunk` — hunk at cursor position.
---@param source_winid integer Window handle for the source window
---@return string
local function resolve_hunk(source_winid)
	-- First check if we're in a codediff buffer
	local codediff = require("briefing.context.codediff")
	if codediff.is_codediff(source_winid) then
		return get_codediff_hunk(source_winid)
	end

	-- Then check if we're in a git diff buffer (filetype "git")
	local fugitive = require("briefing.context.fugitive")
	if fugitive.is_git_diff(source_winid) then
		return get_git_filetype_hunk(source_winid)
	end

	-- Check built-in diff mode (vimdiff/diffsplit)
	local result = try_builtin_diff(source_winid)
	if result then
		return result
	end

	-- Check if we're in a fugitive buffer
	if fugitive.is_fugitive(source_winid) then
		return get_fugitive_hunk(source_winid)
	end

	-- Otherwise use git diff
	return get_git_hunk(source_winid)
end

--- Resolve `#diff:<filename>` — diff for a specific file.
---@param filename string  the file path (relative or absolute)
---@return string
local function resolve_file(filename)
	local out, ok = git({ "git", "diff", "-U3", "--", filename })
	if not ok then
		vim.notify("Briefing: #diff:" .. filename .. " — git diff failed: " .. out, vim.log.levels.WARN)
		return ""
	end

	-- If empty, try staged
	if out == "" then
		out, ok = git({ "git", "diff", "--cached", "-U3", "--", filename })
		if not ok then
			vim.notify("Briefing: #diff:" .. filename .. " — git diff failed: " .. out, vim.log.levels.WARN)
			return ""
		end
	end

	-- If still empty, file might be untracked - use diff against /dev/null
	if out == "" then
		out, ok = git({ "git", "diff", "--no-index", "/dev/null", "--", filename })
		if not ok then
			vim.notify("Briefing: #diff:" .. filename .. " — no changes found", vim.log.levels.WARN)
			return ""
		end
		-- Remove "diff --git /dev/null" and "--- /dev/null" lines for cleaner output
		local lines = vim.split(out, "\n", { plain = true })
		local result = {}
		local skip_count = 0
		for _, line in ipairs(lines) do
			if skip_count > 0 then
				skip_count = skip_count - 1
			elseif line:match("^diff %-%-git") then
				skip_count = 2 -- Skip diff line and --- line
				result[#result + 1] = "diff --git a/" .. filename .. " b/" .. filename
			elseif line:match("^%+%+%+ /dev/null") then
				result[#result + 1] = "+++ b/" .. filename
			else
				result[#result + 1] = line
			end
		end
		out = table.concat(result, "\n")
	end

	if out == "" then
		vim.notify("Briefing: #diff:" .. filename .. " — no changes found", vim.log.levels.WARN)
		return ""
	end

	return wrap_diff(out)
end

--- Resolve `#diff:unstaged` — all unstaged changes.
---@return string
local function resolve_unstaged()
	local out, ok = git({ "git", "diff" })
	if not ok then
		vim.notify("Briefing: #diff:unstaged — git diff failed: " .. out, vim.log.levels.WARN)
		return ""
	end
	if out == "" then
		vim.notify("Briefing: #diff:unstaged — no unstaged changes", vim.log.levels.WARN)
		return ""
	end
	return wrap_diff(out)
end

--- Resolve `#diff:staged` — staged changes.
---@return string
local function resolve_staged()
	local out, ok = git({ "git", "diff", "--cached" })
	if not ok then
		vim.notify("Briefing: #diff:staged — git diff --cached failed: " .. out, vim.log.levels.WARN)
		return ""
	end
	if out == "" then
		vim.notify("Briefing: #diff:staged — no staged changes", vim.log.levels.WARN)
		return ""
	end
	return wrap_diff(out)
end

--- Resolve `#diff:<sha>` — diff for a specific commit.
---@param sha string
---@return string
local function resolve_sha(sha)
	local out, ok = git({ "git", "show", sha })
	if not ok then
		vim.notify("Briefing: #diff:" .. sha .. " — git show failed: " .. out, vim.log.levels.WARN)
		return ""
	end
	if out == "" then
		return ""
	end
	return wrap_diff(out)
end

--- Resolve the `#diff` context variable.
--- Suboptions: "buffer" (default), "staged", "hunk", "unstaged", or a commit SHA.
---@param suboption? string  "buffer", "staged", "hunk", "unstaged", a sha, filepath, or nil (defaults to "buffer")
---@param prev_winid? integer  window handle that was active before briefing opened
---@return string
function M.resolve(suboption, prev_winid)
	-- Use prev_winid if valid, otherwise use current window
	local source_winid = prev_winid and vim.api.nvim_win_is_valid(prev_winid) and prev_winid or 0

	if suboption == nil then
		return resolve_diff(source_winid)
	elseif suboption == "buffer" then
		return resolve_buffer(source_winid)
	elseif suboption == "unstaged" then
		return resolve_unstaged()
	elseif suboption == "staged" then
		return resolve_staged()
	elseif suboption == "hunk" then
		return resolve_hunk(source_winid)
	elseif suboption and (suboption:match("^[%w%./_%-]+") or suboption:match("%.")) then
		-- Check if it looks like a file path (contains / or starts with .)
		if suboption:find("/") or suboption:match("^%.") then
			return resolve_file(suboption)
		end
		-- Otherwise treat as SHA
		return resolve_sha(suboption)
	else
		return resolve_sha(suboption)
	end
end

return M

local M = {}

local dlog = require("briefing.log").dlog

--- Check if the cursor is positioned after a file token pattern.
--- Matches `#file:` at the end of the line before cursor.
---@param line string  current line content
---@param col integer  cursor column (0-indexed, position after the last typed char)
---@return boolean matched  true if matched
---@return integer start_col  column where the token starts (0-indexed)
function M.get_file_pattern(line, col)
	local text_before = line:sub(1, col)
	dlog("get_file_pattern: line='" .. line .. "' col=" .. col .. " text_before='" .. text_before .. "'")
	local start_idx = text_before:find("#file:$")
	dlog("get_file_pattern: start_idx=" .. tostring(start_idx))
	if start_idx then
		return true, start_idx
	end
	return false, 0
end

--- Check if the cursor is positioned after a buffer token pattern.
--- Matches `#buffer:` or `#buffer:diff:` at the end of the line before cursor.
---@param line string  current line content
---@param col integer  cursor column (0-indexed, position after the last typed char)
---@return string|nil pattern  "buffer" or "buffer:diff" if matched, nil otherwise
---@return integer start_col  column where the token starts (0-indexed)
function M.get_buffer_pattern(line, col)
	-- Get text from start to cursor position
	local text_before = line:sub(1, col)

	-- Pattern: ends with `#buffer:diff:`
	local start_idx = text_before:find("#buffer:diff:$")
	if start_idx then
		return "buffer:diff", start_idx
	end

	-- Pattern: ends with `#buffer:`
	start_idx = text_before:find("#buffer:$")
	if start_idx then
		return "buffer", start_idx
	end

	return nil, 0
end

--- Return a path relative to the current working directory.
--- Falls back to the absolute path when outside cwd.
---@param abs_path string  absolute file path
---@return string
local function relative_path(abs_path)
	if abs_path == "" then
		return ""
	end
	local cwd = vim.fn.getcwd()
	cwd = cwd:gsub("/$", "")
	if abs_path:sub(1, #cwd + 1) == cwd .. "/" then
		return abs_path:sub(#cwd + 2)
	end
	return abs_path
end

--- Append file paths after the #file: token.
---@param bufnr integer  briefing buffer number
---@param winid integer  briefing window handle
---@param line_nr integer  line number (1-indexed)
---@param start_col integer  column where #file: starts (0-indexed)
---@param paths string[]  array of file paths (will be made relative to cwd)
local function replace_file_token(bufnr, winid, line_nr, start_col, paths)
	dlog("replace_file_token: START")

	local line = vim.api.nvim_buf_get_lines(bufnr, line_nr - 1, line_nr, false)[1]
	if not line then
		dlog("replace_file_token: ERROR - no line found")
		return
	end
	dlog("replace_file_token: input line='" .. line .. "'")

	-- Build replacement text: keep #file:, add paths as #file:<path> with trailing space
	local replacements = {}
	for _, path in ipairs(paths) do
		dlog("replace_file_token: processing path='" .. path .. "'")
		table.insert(replacements, "#file:" .. relative_path(path))
	end
	local replacement = table.concat(replacements, " ") .. " "
	dlog("replace_file_token: replacement='" .. replacement .. "'")

	-- Replace the token (Lua string indices are 1-based)
	-- #file: is 6 chars, we replace just "#file:" with the paths
	local new_line = line:sub(1, start_col - 1) .. replacement .. line:sub(start_col + 6)
	dlog("replace_file_token: new_line='" .. new_line .. "'")

	-- Update the buffer
	vim.api.nvim_buf_set_lines(bufnr, line_nr - 1, line_nr, false, { new_line })
	dlog("replace_file_token: buffer updated")

	-- Focus the briefing window
	if vim.api.nvim_win_is_valid(winid) then
		vim.api.nvim_set_current_win(winid)
		dlog("replace_file_token: window focused")
	end

	-- Move cursor to end of line and enter insert mode
	vim.schedule(function()
		dlog("replace_file_token: moving to end of line and entering insert mode")
		vim.cmd("normal! A")
	end)
	dlog("replace_file_token: END")
end

--- Replace the buffer token at the specified position with @<path> paths.
---@param bufnr integer  briefing buffer number
---@param winid integer  briefing window handle
---@param line_nr integer  line number (1-indexed)
---@param start_col integer  column where token starts (0-indexed)
-- patterns are 1-indexed in Lua string.find
-- but nvim_win_set_cursor uses 0-indexed columns
---@param pattern string  the matched pattern ("buffer" or "buffer:diff")
---@param paths string[]  array of file paths (will be made relative to cwd)
local function replace_token(bufnr, winid, line_nr, start_col, pattern, paths)
	dlog("replace_token: START")
	dlog(
		"replace_token: bufnr="
			.. bufnr
			.. " winid="
			.. winid
			.. " line_nr="
			.. line_nr
			.. " start_col="
			.. start_col
			.. " pattern="
			.. pattern
	)

	local line = vim.api.nvim_buf_get_lines(bufnr, line_nr - 1, line_nr, false)[1]
	if not line then
		dlog("replace_token: ERROR - no line found")
		return
	end
	dlog("replace_token: input line='" .. line .. "'")
	dlog("replace_token: input line length=" .. #line)

	-- Build replacement text: space-separated #file:<path> tokens with trailing space
	local replacements = {}
	for _, path in ipairs(paths) do
		dlog("replace_token: processing path='" .. path .. "'")
		dlog("replace_token: relative_path='" .. relative_path(path) .. "'")
		table.insert(replacements, "#file:" .. relative_path(path))
	end
	local replacement = table.concat(replacements, " ") .. " "
	dlog("replace_token: replacement='" .. replacement .. "'")
	dlog("replace_token: replacement length=" .. #replacement)
	dlog("replace_token: replacement last char code=" .. string.byte(replacement:sub(-1)))

	-- Replace the token (Lua string indices are 1-based)
	local token_len = #("#" .. pattern .. ":")
	dlog("replace_token: token_len=" .. token_len)
	local new_line = line:sub(1, start_col - 1) .. replacement .. line:sub(start_col + token_len)
	dlog("replace_token: new_line='" .. new_line .. "'")
	dlog("replace_token: new_line length=" .. #new_line)
	dlog("replace_token: new_line last char code=" .. string.byte(new_line:sub(-1)))

	-- Update the buffer
	vim.api.nvim_buf_set_lines(bufnr, line_nr - 1, line_nr, false, { new_line })
	dlog("replace_token: buffer updated")

	-- Verify what was actually written
	local verify_line = vim.api.nvim_buf_get_lines(bufnr, line_nr - 1, line_nr, false)[1]
	dlog("replace_token: verify_line='" .. verify_line .. "'")
	dlog("replace_token: verify_line length=" .. #verify_line)
	dlog("replace_token: verify_line last char code=" .. string.byte(verify_line:sub(-1)))

	-- Focus the briefing window
	if vim.api.nvim_win_is_valid(winid) then
		vim.api.nvim_set_current_win(winid)
		dlog("replace_token: window focused")
	end

	-- Move cursor to end of line and enter insert mode (defer to ensure window focus)
	vim.schedule(function()
		dlog("replace_token: moving to end of line and entering insert mode")
		vim.cmd("normal! A")
	end)
	dlog("replace_token: END")
end

--- Open the snacks buffer picker for #buffer:<tab> completion.
---@param opts? { pattern?: string, start_col?: integer, line_nr?: integer }
function M.open_buffer_picker(opts)
	opts = opts or {}
	local bufnr = vim.api.nvim_get_current_buf()
	local winid = vim.api.nvim_get_current_win()
	local line_nr = opts.line_nr or vim.api.nvim_win_get_cursor(0)[1]
	local start_col = opts.start_col
	local pattern = opts.pattern or "buffer"

	dlog("open_buffer_picker: START")
	dlog(
		"open_buffer_picker: bufnr="
			.. bufnr
			.. " winid="
			.. winid
			.. " line_nr="
			.. line_nr
			.. " start_col="
			.. tostring(start_col)
			.. " pattern="
			.. pattern
	)

	-- Check for snacks.nvim
	local ok, snacks = pcall(require, "snacks")
	if not ok or not snacks.picker then
		vim.notify("Briefing: snacks.nvim is required for buffer picker", vim.log.levels.WARN)
		return
	end

	dlog("open_buffer_picker: calling snacks.picker.buffers()")

	local picker_ok, err = pcall(snacks.picker.buffers, {
		-- Show all buffers including unlisted ones (hidden buffers may not be buflisted)
		hidden = true,
		confirm = function(picker, item)
			dlog("picker.confirm: START")
			picker:close()

			if not item or not item.file then
				dlog("picker.confirm: ERROR - no item or file")
				return
			end
			dlog("picker.confirm: selected file='" .. item.file .. "'")

			-- Get all selected items (for multi-select)
			local selected = picker:selected()
			dlog("picker.confirm: selected count=" .. #selected)
			local items = (#selected > 0) and selected or { item }

			-- Collect paths
			local paths = {}
			for _, sel in ipairs(items) do
				if sel.file then
					dlog("picker.confirm: adding path='" .. sel.file .. "'")
					table.insert(paths, sel.file)
				end
			end
			dlog("picker.confirm: total paths=" .. #paths)

			if #paths > 0 then
				-- We need to re-calculate start_col if not provided
				-- This can happen when called directly
				if not start_col then
					dlog("picker.confirm: recalculating start_col")
					local line = vim.api.nvim_buf_get_lines(bufnr, line_nr - 1, line_nr, false)[1] or ""
					local _, col = M.get_buffer_pattern(line, #line)
					start_col = col
					dlog("picker.confirm: recalculated start_col=" .. start_col)
				end

				dlog("picker.confirm: calling replace_token")
				replace_token(bufnr, winid, line_nr, start_col, pattern, paths)
			else
				dlog("picker.confirm: no paths to process")
			end
			dlog("picker.confirm: END")
		end,
		on_close = function(_picker)
			dlog("picker.on_close: restoring focus to briefing window")
			-- Defer focus restoration to override snacks' automatic main window focus
			vim.schedule(function()
				if vim.api.nvim_win_is_valid(winid) then
					vim.api.nvim_set_current_win(winid)
					-- Position cursor right after the #buffer: pattern and enter insert mode
					-- start_col is 1-indexed, nvim_win_set_cursor col is 0-indexed
					-- Token is: # + pattern + : = 1 + #pattern + 1 = #pattern + 2 chars
					-- So 0-indexed position after = (start_col - 1) + (#pattern + 2) = start_col + #pattern + 1
					local col_after = start_col and (start_col + #pattern + 1) or 1
					vim.api.nvim_win_set_cursor(winid, { line_nr, col_after })
					vim.cmd("startinsert")
				end
			end)
		end,
	})

	if not picker_ok then
		dlog("open_buffer_picker: ERROR calling snacks.picker.buffers: " .. tostring(err))
		vim.notify("Briefing: Failed to open buffer picker: " .. tostring(err), vim.log.levels.ERROR)
		return
	end

	dlog("open_buffer_picker: END")
end

--- Open the snacks file picker for #file:<tab> completion.
---@param opts? { start_col?: integer, line_nr?: integer }
function M.open_file_picker(opts)
	opts = opts or {}
	local bufnr = vim.api.nvim_get_current_buf()
	local winid = vim.api.nvim_get_current_win()
	local line_nr = opts.line_nr or vim.api.nvim_win_get_cursor(0)[1]
	local start_col = opts.start_col

	dlog("open_file_picker: START")
	dlog(
		"open_file_picker: bufnr="
			.. bufnr
			.. " winid="
			.. winid
			.. " line_nr="
			.. line_nr
			.. " start_col="
			.. tostring(start_col)
	)

	local ok, snacks = pcall(require, "snacks")
	dlog("open_file_picker: snacks require ok=" .. tostring(ok))
	if not ok or not snacks.picker then
		dlog("open_file_picker: snacks.nvim not available, snacks.picker=" .. tostring(snacks and snacks.picker or "nil"))
		vim.notify("Briefing: snacks.nvim is required for file picker", vim.log.levels.WARN)
		return
	end

	dlog("open_file_picker: calling snacks.picker.files()")

	local picker_ok, err = pcall(snacks.picker.files, {
		confirm = function(picker, item)
			dlog("file_picker.confirm: START")
			picker:close()

			if not item or not item.file then
				dlog("file_picker.confirm: ERROR - no item or file")
				return
			end
			dlog("file_picker.confirm: selected file='" .. item.file .. "'")

			local selected = picker:selected()
			dlog("file_picker.confirm: selected count=" .. #selected)
			local items = (#selected > 0) and selected or { item }

			local paths = {}
			for _, sel in ipairs(items) do
				if sel.file then
					dlog("file_picker.confirm: adding path='" .. sel.file .. "'")
					table.insert(paths, sel.file)
				end
			end
			dlog("file_picker.confirm: total paths=" .. #paths)

			if #paths > 0 then
				if not start_col then
					dlog("file_picker.confirm: recalculating start_col")
					local line = vim.api.nvim_buf_get_lines(bufnr, line_nr - 1, line_nr, false)[1] or ""
					local _, col = M.get_file_pattern(line, #line)
					start_col = col
					dlog("file_picker.confirm: recalculated start_col=" .. start_col)
				end

				dlog("file_picker.confirm: calling replace_file_token")
				replace_file_token(bufnr, winid, line_nr, start_col, paths)
			else
				dlog("file_picker.confirm: no paths to process")
			end
			dlog("file_picker.confirm: END")
		end,
		on_close = function(_picker)
			dlog("file_picker.on_close: restoring focus to briefing window")
			vim.schedule(function()
				if vim.api.nvim_win_is_valid(winid) then
					vim.api.nvim_set_current_win(winid)
					-- Position cursor right after the #file: pattern and enter insert mode
					-- start_col is 1-indexed, #file: is 6 chars
					-- 0-indexed position after = (start_col - 1) + 6 = start_col + 5
					local col_after = start_col and (start_col + 5) or 6
					vim.api.nvim_win_set_cursor(winid, { line_nr, col_after })
					vim.cmd("startinsert")
				end
			end)
		end,
	})

	if not picker_ok then
		dlog("open_file_picker: ERROR calling snacks.picker.files: " .. tostring(err))
		vim.notify("Briefing: Failed to open file picker: " .. tostring(err), vim.log.levels.ERROR)
		return
	end

	dlog("open_file_picker: END")
end

--- Handle <Tab> keypress in insert mode.
--- Checks if cursor follows a file or buffer pattern and opens picker if so.
--- Falls back to normal tab behavior otherwise.
function M.on_tab()
	dlog("on_tab: START")
	local bufnr = vim.api.nvim_get_current_buf()
	dlog("on_tab: bufnr=" .. bufnr .. " filetype=" .. vim.bo[bufnr].filetype)

	-- Only activate in briefing buffers
	if vim.bo[bufnr].filetype ~= "briefing" then
		dlog("on_tab: not a briefing buffer, falling back")
		return vim.api.nvim_feedkeys(vim.keycode("<Tab>"), "n", true)
	end

	local cursor = vim.api.nvim_win_get_cursor(0)
	local line_nr = cursor[1]
	local col = cursor[2] -- 0-indexed column
	dlog("on_tab: line_nr=" .. line_nr .. " col=" .. col)

	local line = vim.api.nvim_buf_get_lines(bufnr, line_nr - 1, line_nr, false)[1] or ""
	dlog("on_tab: line='" .. line .. "'")

	-- Check for #file: pattern first
	local is_file, file_start_col = M.get_file_pattern(line, col)
	dlog("on_tab: is_file=" .. tostring(is_file) .. " file_start_col=" .. tostring(file_start_col))

	if is_file then
		dlog("on_tab: opening file picker")
		M.open_file_picker({
			start_col = file_start_col,
			line_nr = line_nr,
		})
		return
	end

	-- Then check for #buffer: pattern
	local pattern, start_col = M.get_buffer_pattern(line, col)
	dlog("on_tab: pattern=" .. tostring(pattern) .. " start_col=" .. tostring(start_col))

	if pattern then
		dlog("on_tab: opening buffer picker")
		M.open_buffer_picker({
			pattern = pattern,
			start_col = start_col,
			line_nr = line_nr,
		})
		return
	end

	dlog("on_tab: no pattern match, falling back to tab")
	-- Fall back to normal tab behavior
	vim.api.nvim_feedkeys(vim.keycode("<Tab>"), "n", true)
	dlog("on_tab: END")
end

return M

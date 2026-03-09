local M = {}

local dlog = require("briefing.log").dlog

--- Check if the cursor is positioned after a file token pattern.
---@param line string  current line content
---@param col integer  cursor column (0-indexed)
---@return boolean matched
---@return integer start_col
function M.get_file_pattern(line, col)
	dlog("get_file_pattern: line='" .. line .. "' col=" .. col)
	local start_idx = line:sub(1, col):find("#file:$")
	if start_idx then
		return true, start_idx
	end
	return false, 0
end

--- Check if the cursor is positioned after a buffer token pattern.
---@param line string  current line content
---@param col integer  cursor column (0-indexed)
---@return string|nil pattern
---@return integer start_col
function M.get_buffer_pattern(line, col)
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

--- Append file paths after a token, replacing it with #file:<path> tokens.
---@param bufnr integer  briefing buffer number
---@param winid integer  briefing window handle
---@param line_nr integer  line number (1-indexed)
---@param start_col integer  column where token starts (0-indexed)
---@param pattern string  the matched pattern (for token length calculation)
---@param paths string[]  array of file paths
local function replace_with_paths(bufnr, winid, line_nr, start_col, pattern, paths)
	dlog("replace_with_paths: pattern=" .. pattern .. " paths=" .. #paths)

	local line = vim.api.nvim_buf_get_lines(bufnr, line_nr - 1, line_nr, false)[1]
	if not line then
		return
	end

	-- Build replacement: space-separated #file:<relative_path> tokens
	local replacements = {}
	for _, path in ipairs(paths) do
		table.insert(replacements, "#file:" .. relative_path(path))
	end
	local replacement = table.concat(replacements, " ") .. " "

	-- Replace the token (Lua strings are 1-indexed)
	local token_len = #("#" .. pattern .. ":")
	local new_line = line:sub(1, start_col - 1) .. replacement .. line:sub(start_col + token_len)

	vim.api.nvim_buf_set_lines(bufnr, line_nr - 1, line_nr, false, { new_line })

	if vim.api.nvim_win_is_valid(winid) then
		vim.api.nvim_set_current_win(winid)
	end

	vim.schedule(function()
		vim.cmd("normal! A")
	end)
end

--- Open the snacks picker for file or buffer selection.
---@param opts? { type: "file"|"buffer", pattern?: string, start_col?: integer, line_nr?: integer }
function M.open_picker(opts)
	opts = opts or {}
	local picker_type = opts.type or "file"
	local bufnr = vim.api.nvim_get_current_buf()
	local winid = vim.api.nvim_get_current_win()
	local line_nr = opts.line_nr or vim.api.nvim_win_get_cursor(0)[1]
	local start_col = opts.start_col
	local pattern = opts.pattern or "buffer"

	dlog("open_picker: type=" .. picker_type .. " pattern=" .. pattern)

	local ok, snacks = pcall(require, "snacks")
	if not ok or not snacks.picker then
		vim.notify("Briefing: snacks.nvim is required for picker", vim.log.levels.WARN)
		return
	end

	local picker_fn = picker_type == "file" and snacks.picker.files or snacks.picker.buffers

	local picker_ok, err = pcall(picker_fn, {
		hidden = picker_type == "buffer",
		confirm = function(picker, item)
			picker:close()

			if not item or not item.file then
				return
			end

			local selected = picker:selected()
			local items = (#selected > 0) and selected or { item }

			local paths = {}
			for _, sel in ipairs(items) do
				if sel.file then
					table.insert(paths, sel.file)
				end
			end

			if #paths == 0 then
				return
			end

			-- Recalculate start_col if not provided
			if not start_col then
				local line = vim.api.nvim_buf_get_lines(bufnr, line_nr - 1, line_nr, false)[1] or ""
				local _, pattern_col
				if picker_type == "file" then
					_, pattern_col = M.get_file_pattern(line, #line)
				else
					_, pattern_col = M.get_buffer_pattern(line, #line)
				end
				start_col = pattern_col
			end

			replace_with_paths(bufnr, winid, line_nr, start_col, pattern, paths)
		end,
		on_close = function(_)
			vim.schedule(function()
				if vim.api.nvim_win_is_valid(winid) then
					vim.api.nvim_set_current_win(winid)
					local col_after = start_col and (start_col + #pattern + 1) or 1
					vim.api.nvim_win_set_cursor(winid, { line_nr, col_after })
					vim.cmd("startinsert")
				end
			end)
		end,
	})

	if not picker_ok then
		dlog("open_picker: ERROR " .. tostring(err))
		vim.notify("Briefing: Failed to open picker: " .. tostring(err), vim.log.levels.ERROR)
	end
end

--- Handle <Tab> keypress in insert mode.
function M.on_tab()
	dlog("on_tab: START")

	local bufnr = vim.api.nvim_get_current_buf()
	if vim.bo[bufnr].filetype ~= "briefing" then
		return vim.api.nvim_feedkeys(vim.keycode("<Tab>"), "n", true)
	end

	local cursor = vim.api.nvim_win_get_cursor(0)
	local line_nr = cursor[1]
	local col = cursor[2]
	local line = vim.api.nvim_buf_get_lines(bufnr, line_nr - 1, line_nr, false)[1] or ""

	-- Check for #file: pattern first
	local is_file, file_start_col = M.get_file_pattern(line, col)
	if is_file then
		return M.open_picker({ type = "file", pattern = "file", start_col = file_start_col, line_nr = line_nr })
	end

	-- Then check for #buffer: pattern
	local pattern, start_col = M.get_buffer_pattern(line, col)
	if pattern then
		return M.open_picker({ type = "buffer", pattern = pattern, start_col = start_col, line_nr = line_nr })
	end

	-- Fall back to normal tab behavior
	vim.api.nvim_feedkeys(vim.keycode("<Tab>"), "n", true)
end

return M

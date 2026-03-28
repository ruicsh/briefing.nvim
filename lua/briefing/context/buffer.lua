local M = {}

--- Return the filetype of a buffer as a fenced code block language tag.
--- Falls back to an empty string when there is no recognised filetype.
---@param bufnr integer
---@return string
local function buf_lang(bufnr)
	return vim.bo[bufnr].filetype or ""
end

--- Return a path for the buffer relative to the current working directory,
--- or the absolute path when the buffer is outside the cwd.
---@param name string  absolute path from nvim_buf_get_name()
---@return string
local function relative_path(name)
	if name == "" then
		return "[No Name]"
	end
	local cwd = vim.fn.getcwd()
	-- Strip trailing slash from cwd if present
	cwd = cwd:gsub("/$", "")
	if name:sub(1, #cwd + 1) == cwd .. "/" then
		return name:sub(#cwd + 2)
	end
	return name
end

--- Resolve `#buffer` — inline the full buffer content.
---@param bufnr integer
---@return string
local function resolve_all(bufnr)
	local path = relative_path(vim.api.nvim_buf_get_name(bufnr))
	local lang = buf_lang(bufnr)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local line_count = #lines
	local content = table.concat(lines, "\n")

	return ("File: %s (lines 1-%d)\n```%s\n%s\n```"):format(path, line_count, lang, content)
end

--- Resolve the `#buffer` context variable.
---@param prev_winid? integer  the window that was active before briefing opened
---@return string
function M.resolve(prev_winid)
	-- Determine the buffer to read: use the window that was active before
	-- briefing opened, falling back to the current window.
	local winid = (prev_winid and vim.api.nvim_win_is_valid(prev_winid)) and prev_winid or vim.api.nvim_get_current_win()
	local bufnr = vim.api.nvim_win_get_buf(winid)

	if not vim.api.nvim_buf_is_valid(bufnr) then
		vim.notify("Briefing: #buffer — no valid buffer found", vim.log.levels.WARN)
		return ""
	end

	return resolve_all(bufnr)
end

return M

local M = {}

--- Return the filetype of a buffer as a fenced code block language tag.
--- Falls back to an empty string when there is no recognised filetype.
---@param bufnr integer
---@return string
function M.buf_lang(bufnr)
	return vim.bo[bufnr].filetype or ""
end

--- Return a path for the buffer relative to the current working directory,
--- or the absolute path when the buffer is outside the cwd.
---@param name string  absolute path from nvim_buf_get_name()
---@return string
function M.relative_path(name)
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

--- Format a single buffer's content as a fenced code block with header.
---@param bufnr integer
---@return string|nil  nil if buffer is invalid
function M.format_buf_content(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return nil
	end

	local name = vim.api.nvim_buf_get_name(bufnr)
	local path = M.relative_path(name)
	local lang = M.buf_lang(bufnr)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local line_count = #lines
	local content = table.concat(lines, "\n")

	return ("File: %s (lines 1-%d)\n```%s\n%s\n```"):format(path, line_count, lang, content)
end

return M

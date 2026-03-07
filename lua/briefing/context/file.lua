local M = {}

--- Return the content of a file at `path`, formatted as a fenced code block.
---@param path string  absolute or relative path
---@return string
function M.resolve(path)
	if not path or path == "" then
		vim.notify("Briefing: #file — no path specified", vim.log.levels.WARN)
		return ""
	end

	-- Resolve relative paths from the cwd
	local abs_path = path
	if path:sub(1, 1) ~= "/" then
		abs_path = vim.fn.getcwd() .. "/" .. path
	end

	local ok, lines_or_err = pcall(vim.fn.readfile, abs_path)
	if not ok or type(lines_or_err) ~= "table" then
		vim.notify("Briefing: #file — could not read file: " .. path, vim.log.levels.WARN)
		return ""
	end

	---@cast lines_or_err string[]
	local lines = lines_or_err
	local line_count = #lines
	local content = table.concat(lines, "\n")

	-- Detect filetype from extension
	local ext = path:match("%.([^%.]+)$") or ""
	local lang = vim.filetype.match({ filename = path }) or ext

	return ("File: %s (lines 1-%d)\n```%s\n%s\n```"):format(path, line_count, lang, content)
end

return M

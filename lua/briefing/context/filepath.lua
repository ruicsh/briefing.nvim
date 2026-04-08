local M = {}

--- Get the absolute path of the current buffer.
---@param prev_winid? integer  the window that was active before briefing opened
---@return string
local function get_absolute_path(prev_winid)
	local winid = (prev_winid and vim.api.nvim_win_is_valid(prev_winid)) and prev_winid or vim.api.nvim_get_current_win()
	local bufnr = vim.api.nvim_win_get_buf(winid)
	return vim.api.nvim_buf_get_name(bufnr)
end

--- Convert an absolute path to relative to cwd.
--- Returns absolute path if outside cwd.
---@param absolute string
---@return string
local function to_relative(absolute)
	if absolute == "" then
		return ""
	end
	local cwd = vim.fn.getcwd()
	cwd = cwd:gsub("/$", "")
	if absolute:sub(1, #cwd + 1) == cwd .. "/" then
		return absolute:sub(#cwd + 2)
	end
	return absolute
end

--- Resolve `#filepath` — returns the relative path of the current file.
--- For unnamed buffers, returns empty string (token is skipped).
---@param suboption? string  "absolute" for full path, nil for relative
---@param prev_winid? integer  the window that was active before briefing opened
---@return string
function M.resolve(suboption, prev_winid)
	local absolute = get_absolute_path(prev_winid)

	if absolute == "" then
		return ""
	end

	if suboption == "absolute" then
		return absolute
	end

	return to_relative(absolute)
end

return M

local M = {}

local util = require("briefing.context.util")

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

	local formatted = util.format_buf_content(bufnr)
	if not formatted then
		vim.notify("Briefing: #buffer — could not format buffer content", vim.log.levels.WARN)
		return ""
	end

	return formatted
end

return M

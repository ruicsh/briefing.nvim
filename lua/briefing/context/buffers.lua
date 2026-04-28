local M = {}

local util = require("briefing.context.util")

--- Resolve the `#buffers` context variable.
--- Inlines the content of all listed buffers (non-empty, non-briefing buffers).
---@return string
function M.resolve()
	local all_bufs = vim.api.nvim_list_bufs()
	local outputs = {}

	for _, bufnr in ipairs(all_bufs) do
		-- Filter: buffer must be listed
		if not vim.bo[bufnr].buflisted then
			goto continue
		end

		-- Skip the briefing buffer itself
		if vim.bo[bufnr].filetype == "briefing" then
			goto continue
		end

		-- Skip buffers with empty names
		local name = vim.api.nvim_buf_get_name(bufnr)
		if name == "" then
			goto continue
		end

		local formatted = util.format_buf_content(bufnr)
		if formatted then
			table.insert(outputs, formatted)
		end

		::continue::
	end

	if #outputs == 0 then
		vim.notify("Briefing: #buffers — no listed buffers found", vim.log.levels.WARN)
		return ""
	end

	return table.concat(outputs, "\n\n")
end

return M

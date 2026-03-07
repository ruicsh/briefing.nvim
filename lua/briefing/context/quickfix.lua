local M = {}

--- Resolve the `#quickfix` context variable.
--- Inlines the current quickfix list as a structured text block.
---@return string
function M.resolve()
	local qf = vim.fn.getqflist()

	if #qf == 0 then
		vim.notify("Briefing: #quickfix — quickfix list is empty", vim.log.levels.WARN)
		return ""
	end

	local cwd = vim.fn.getcwd():gsub("/$", "")

	local lines = { ("Quickfix (%d items)"):format(#qf) }
	for _, item in ipairs(qf) do
		-- Resolve buffer name
		local fname = ""
		if item.bufnr and item.bufnr > 0 then
			fname = vim.api.nvim_buf_get_name(item.bufnr)
			if fname ~= "" and fname:sub(1, #cwd + 1) == cwd .. "/" then
				fname = fname:sub(#cwd + 2)
			end
		end
		if fname == "" then
			fname = "[No Name]"
		end

		local lnum = item.lnum or 0
		local col = item.col or 0
		local text = (item.text or ""):gsub("\n", " ")
		local type_str = item.type and item.type ~= "" and (item.type .. ": ") or ""

		lines[#lines + 1] = ("%s:%d:%d: %s%s"):format(fname, lnum, col, type_str, text)
	end

	return table.concat(lines, "\n")
end

return M

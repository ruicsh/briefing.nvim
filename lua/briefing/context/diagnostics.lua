local M = {}

--- Format a single diagnostic entry as a human-readable string.
---@param d vim.Diagnostic
---@param include_path? boolean  prepend the file path (for workspace-level output)
---@return string
local function format_diag(d, include_path)
	local severity_map = {
		[vim.diagnostic.severity.ERROR] = "ERROR",
		[vim.diagnostic.severity.WARN] = "WARN",
		[vim.diagnostic.severity.INFO] = "INFO",
		[vim.diagnostic.severity.HINT] = "HINT",
	}
	local sev = severity_map[d.severity] or "UNKNOWN"
	local line = d.lnum + 1 -- lnum is 0-based
	local col = d.col + 1 -- col is 0-based
	local source = d.source and ("[" .. d.source .. "] ") or ""
	local msg = d.message:gsub("\n", " ")

	if include_path then
		local path = d.bufnr and vim.api.nvim_buf_get_name(d.bufnr) or ""
		if path ~= "" then
			local cwd = vim.fn.getcwd():gsub("/$", "")
			if path:sub(1, #cwd + 1) == cwd .. "/" then
				path = path:sub(#cwd + 2)
			end
		else
			path = "[No Name]"
		end
		return ("%s:%d:%d: %s%s: %s"):format(path, line, col, source, sev, msg)
	end

	return ("%d:%d: %s%s: %s"):format(line, col, source, sev, msg)
end

--- Resolve `#diagnostics` or `#diagnostics:buffer` — diagnostics for the current buffer.
---@param prev_winid? integer
---@return string
local function resolve_buffer(prev_winid)
	local winid = (prev_winid and vim.api.nvim_win_is_valid(prev_winid)) and prev_winid or vim.api.nvim_get_current_win()
	local bufnr = vim.api.nvim_win_get_buf(winid)

	local diags = vim.diagnostic.get(bufnr)
	if #diags == 0 then
		vim.notify("Briefing: #diagnostics — no diagnostics found in buffer", vim.log.levels.WARN)
		return ""
	end

	-- Sort by line, then col
	table.sort(diags, function(a, b)
		if a.lnum ~= b.lnum then
			return a.lnum < b.lnum
		end
		return a.col < b.col
	end)

	local path = vim.api.nvim_buf_get_name(bufnr)
	if path == "" then
		path = "[No Name]"
	else
		local cwd = vim.fn.getcwd():gsub("/$", "")
		if path:sub(1, #cwd + 1) == cwd .. "/" then
			path = path:sub(#cwd + 2)
		end
	end

	local lines = { ("Diagnostics: %s"):format(path) }
	for _, d in ipairs(diags) do
		lines[#lines + 1] = format_diag(d, false)
	end

	return table.concat(lines, "\n")
end

--- Resolve `#diagnostics:all` — all diagnostics across the workspace.
---@return string
local function resolve_all()
	local diags = vim.diagnostic.get(nil)
	if #diags == 0 then
		vim.notify("Briefing: #diagnostics:all — no diagnostics found", vim.log.levels.WARN)
		return ""
	end

	-- Sort by bufnr, then line, then col
	table.sort(diags, function(a, b)
		if a.bufnr ~= b.bufnr then
			return (a.bufnr or 0) < (b.bufnr or 0)
		end
		if a.lnum ~= b.lnum then
			return a.lnum < b.lnum
		end
		return a.col < b.col
	end)

	local lines = { "Diagnostics: workspace" }
	for _, d in ipairs(diags) do
		lines[#lines + 1] = format_diag(d, true)
	end

	return table.concat(lines, "\n")
end

--- Resolve the `#diagnostics` context variable.
---@param suboption? string  "buffer", "all", or nil (defaults to "buffer")
---@param prev_winid? integer
---@return string
function M.resolve(suboption, prev_winid)
	if suboption == "all" then
		return resolve_all()
	end
	return resolve_buffer(prev_winid)
end

return M

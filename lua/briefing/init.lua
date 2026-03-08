local M = {}

---@param opts? briefing.Config
function M.setup(opts)
	require("briefing.config").setup(opts)
end

--- Open (or focus) the briefing floating window.
function M.open()
	require("briefing.ui").open()
end

--- Close the briefing floating window (content persists).
function M.close()
	require("briefing.ui").close()
end

--- Send the current buffer contents to the configured adapter, then close the window.
--- Context tokens (e.g. `#buffer`) are resolved or translated before sending.
function M.send()
	local ui = require("briefing.ui")
	local text = ui.get_text()

	-- Check if text is empty or contains only whitespace
	if text:match("^%s*$") then
		vim.notify("Briefing: prompt is empty", vim.log.levels.WARN)
		return
	end

	-- Trim leading and trailing whitespace (including newlines)
	text = text:gsub("^%s+", ""):gsub("%s+$", "")

	-- Capture prev_winid before close() clears it
	local prev_winid = ui.get_prev_winid()

	-- Preprocess @path references to #file:path format
	local context = require("briefing.context")
	text = context.preprocess_at_refs(text)

	local tokens = context.parse(text)
	require("briefing.adapter").send(text, tokens, prev_winid)
	M.close()
end

return M

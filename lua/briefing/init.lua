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

	-- Strip leading/trailing whitespace
	text = text:match("^%s*(.-)%s*$")

	if text == "" then
		vim.notify("Briefing: nothing to send", vim.log.levels.WARN)
		return
	end

	-- Capture prev_winid before close() clears it
	local prev_winid = ui.get_prev_winid()

	local tokens = require("briefing.context").parse(text)
	require("briefing.adapter").send(text, tokens, prev_winid)
	M.close()
end

return M

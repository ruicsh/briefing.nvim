local M = {}

local dlog = require("briefing.log").dlog

--- Resolve the `#selection` context variable.
--- Reads from register z which was yanked at open() time from visual selection.
---@return string
function M.resolve()
	-- Read directly from register z (yanked at open time from visual selection)
	local content = vim.fn.getreg("z")
	dlog("selection resolve: reg z len=" .. (content and #content or 0))
	if content and content ~= "" then
		content = content:gsub("\n$", "") -- strip trailing newline from yank
		local lang = vim.t.briefing_prev_filetype or ""
		return ("```%s\n%s\n```"):format(lang, content)
	end

	dlog("selection resolve: no content in register z")
	vim.notify("Briefing: #selection — no visual selection available", vim.log.levels.WARN)
	return ""
end

return M

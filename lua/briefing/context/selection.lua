local M = {}

local dlog = require("briefing.log").dlog

--- Convert tabs to spaces using the current tabstop setting.
---@param str string
---@return string
local function tabs_to_spaces(str)
	local tabstop = vim.o.tabstop or 8
	return str:gsub("\t", string.rep(" ", tabstop))
end

--- Resolve the `#selection` context variable.
--- Reads from register z which was yanked at open() time from visual selection.
---@return string
function M.resolve()
	-- Read directly from register z (yanked at open time from visual selection)
	local content = vim.fn.getreg("z")
	dlog("selection resolve: reg z len=" .. (content and #content or 0))
	if content and content ~= "" then
		content = content:gsub("\n$", "") -- strip trailing newline from yank
		content = tabs_to_spaces(content) -- convert tabs to spaces for consistent rendering
		local lang = vim.t.briefing_prev_filetype or ""
		return ("```%s\n%s\n```"):format(lang, content)
	end

	dlog("selection resolve: no content in register z")
	vim.notify("Briefing: #selection — no visual selection available", vim.log.levels.WARN)
	return ""
end

return M

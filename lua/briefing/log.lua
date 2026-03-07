local M = {}

--- Emit a debug message via echom when config.debug is enabled.
--- Messages are prefixed with "Briefing [debug]: ".
---@param msg string
function M.dlog(msg)
	if require("briefing.config").options.debug then
		vim.cmd("echom " .. vim.inspect("Briefing [debug]: " .. msg))
	end
end

return M

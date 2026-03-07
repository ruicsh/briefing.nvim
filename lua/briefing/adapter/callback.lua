local M = {}

--- Self-resolve all tokens in `raw_text` by substituting each token's raw
--- string with the content returned by the context resolver.  Tokens that
--- have no resolver are left in place as-is.
---@param raw_text string
---@param tokens briefing.Token[]
---@param prev_winid? integer
---@return string  fully resolved prompt text
local function resolve_text(raw_text, tokens, prev_winid)
	local context = require("briefing.context")
	local result = raw_text

	for _, token in ipairs(tokens) do
		local resolved = context.resolve(token, prev_winid)
		if resolved ~= nil then
			-- Replace the first (and only) occurrence of the raw token.
			-- Escape magic pattern characters in the token literal.
			local escaped = token.raw:gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1")
			result = result:gsub(escaped, resolved, 1)
		end
	end

	return result
end

--- Send the resolved prompt via the callback adapter.
--- Calls `adapter.callback(resolved_text)` when configured, or falls
--- back to copying to the system clipboard (`+` register).
---@param raw_text string
---@param tokens briefing.Token[]
---@param prev_winid? integer
function M.send(raw_text, tokens, prev_winid)
	local resolved = resolve_text(raw_text, tokens, prev_winid)

	local cfg = require("briefing.config").options
	local cb = cfg.adapter and cfg.adapter.callback

	if type(cb) == "function" then
		cb(resolved)
	else
		vim.fn.setreg("+", resolved)
		vim.notify("Briefing: prompt copied to clipboard", vim.log.levels.INFO)
	end
end

return M

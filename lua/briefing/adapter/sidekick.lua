local M = {}

--- Sidekick token translation table.
--- Maps briefing token names (+ optional suboption) to sidekick {var} strings.
--- Tokens with no sidekick equivalent must be self-resolved before sending.
---@type table<string, string>
local SIDEKICK_MAP = {
	buffer = "{file}",
}

--- Translate a single briefing token to its sidekick equivalent.
--- Returns nil when the token has no sidekick native equivalent.
---@param token briefing.Token
---@return string|nil sidekick_var
local function translate_token(token)
	if token.name == "buffer" then
		if token.suboption and token.suboption ~= "all" then
			vim.notify(
				("Briefing: sidekick adapter — #buffer:%s has no sidekick equivalent, using {file}"):format(token.suboption),
				vim.log.levels.WARN
			)
		end
		return SIDEKICK_MAP["buffer"]
	end
	return nil
end

--- Translate all recognised tokens to sidekick {vars} and self-resolve any
--- tokens that have no sidekick equivalent, leaving them inline as resolved text.
---@param raw_text string
---@param tokens briefing.Token[]
---@param prev_winid? integer
---@return string  translated prompt ready for sidekick_cli.send()
local function translate(raw_text, tokens, prev_winid)
	local context = require("briefing.context")
	local result = raw_text

	for _, token in ipairs(tokens) do
		local escaped = token.raw:gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1")
		local sidekick_var = translate_token(token)

		if sidekick_var then
			result = result:gsub(escaped, sidekick_var, 1)
		else
			-- Self-resolve tokens that sidekick cannot handle
			local resolved = context.resolve(token, prev_winid)
			if resolved ~= nil then
				result = result:gsub(escaped, resolved, 1)
			end
		end
	end

	return result
end

--- Send the prompt through sidekick.nvim.
---@param raw_text string
---@param tokens briefing.Token[]
---@param prev_winid? integer
function M.send(raw_text, tokens, prev_winid)
	local ok, sidekick_cli = pcall(require, "sidekick.cli")
	if not ok then
		vim.notify("Briefing: sidekick.nvim is not installed", vim.log.levels.ERROR)
		return
	end

	local translated = translate(raw_text, tokens, prev_winid)
	sidekick_cli.send({ msg = translated })
end

return M

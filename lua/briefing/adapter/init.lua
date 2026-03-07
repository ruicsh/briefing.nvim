local M = {}

--- Return the configured adapter module.
--- Resolves adapter.name: "callback", "sidekick", or a custom adapter table.
---@return table  adapter module with a send() function
function M.get()
	local cfg = require("briefing.config").options
	local name = cfg.adapter.name

	if type(name) == "table" then
		return name
	end

	if name == "sidekick" then
		return require("briefing.adapter.sidekick")
	end

	-- Default: callback
	return require("briefing.adapter.callback")
end

--- Resolve all tokens in `raw_text` and send via the configured adapter.
--- This is the single entry-point called by briefing.send().
---@param raw_text string   the prompt as typed by the user
---@param tokens briefing.Token[]  parsed tokens from context.parse()
---@param prev_winid? integer  window handle active before briefing opened
function M.send(raw_text, tokens, prev_winid)
	M.get().send(raw_text, tokens, prev_winid)
end

return M

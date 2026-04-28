local M = {}

local dlog = require("briefing.log").dlog

--- Convert a plain string to sidekick.Text[] so sidekick skips its template
--- renderer and sends the content verbatim.
---@param str string
---@return table
local function to_text(str)
	local ok, Text = pcall(require, "sidekick.text")
	if not ok then
		return {}
	end
	return Text.to_text(str)
end

--- Check if a local (non-external) sidekick session is running.
---@param tool string
---@return boolean has_local_session
local function has_local_session(tool)
	local ok_state, State = pcall(require, "sidekick.cli.state")
	if not ok_state then
		return false
	end

	local running = State.get({ name = tool, started = true, external = false })
	dlog("non-external started=" .. #running)
	return #running >= 1
end

--- Pre-create and attach a local terminal session.
---@param tool string
---@return boolean success
local function precreate_session(tool)
	local ok_session, Session = pcall(require, "sidekick.cli.session")
	if not ok_session then
		return false
	end

	dlog("pre-starting new local terminal session")
	local session = Session.new({ tool = tool })
	Session.attach(session)
	return true
end

--- Translate a single briefing token to its sidekick-ready string.
--- Returns nil when the token should be self-resolved inline instead.
---@param token briefing.Token
---@param prev_winid? integer
---@param tool? string
---@return string|nil
local function translate_token(token, prev_winid, tool)
	if token.name == "buffer" and not token.suboption then
		if tool == "opencode" then
			local winid = prev_winid and vim.api.nvim_win_is_valid(prev_winid) and prev_winid or nil
			if winid then
				local bufnr = vim.api.nvim_win_get_buf(winid)
				local path = vim.api.nvim_buf_get_name(bufnr)
				if path and path ~= "" then
					return "@" .. vim.fn.fnamemodify(path, ":.")
				end
			end
		end
	end

	-- Translate #buffers to @ references for all listed buffers for opencode
	if token.name == "buffers" and not token.suboption then
		if tool == "opencode" then
			local refs = {}
			for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
				if vim.bo[bufnr].buflisted then
					local path = vim.api.nvim_buf_get_name(bufnr)
					if path and path ~= "" then
						table.insert(refs, "@" .. vim.fn.fnamemodify(path, ":."))
					end
				end
			end
			if #refs > 0 then
				return table.concat(refs, " ")
			end
		end
	end

	-- Translate #file:path to @{path} for opencode
	if token.name == "file" and token.suboption then
		if tool == "opencode" then
			return "@" .. token.suboption
		end
	end

	return nil
end

--- Translate all recognised tokens and self-resolve any that have no
--- tool-specific equivalent, leaving them inline as resolved text.
---@param raw_text string
---@param tokens briefing.Token[]
---@param prev_winid? integer
---@return string
local function translate(raw_text, tokens, prev_winid)
	local context = require("briefing.context")
	local cfg = require("briefing.config").options
	local tool = cfg.adapter and cfg.adapter.sidekick and cfg.adapter.sidekick.tool or nil
	local result = raw_text

	dlog("translate: token_count=" .. #tokens .. " raw_text(80)=" .. raw_text:sub(1, 80):gsub("\n", "\\n"))

	for _, token in ipairs(tokens) do
		local escaped = token.raw:gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1")
		local translated = translate_token(token, prev_winid, tool)

		if translated then
			result = result:gsub(escaped, translated, 1)
		else
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

	local cfg = require("briefing.config").options
	local sidekick_cfg = cfg.adapter and cfg.adapter.sidekick or {}
	local translated = translate(raw_text, tokens, prev_winid)

	-- Check if translated text is empty or contains only whitespace
	if translated:match("^%s*$") then
		vim.notify("Briefing: prompt is empty after resolving tokens", vim.log.levels.WARN)
		return
	end

	local text = to_text(translated)
	local tool = sidekick_cfg.tool

	local ok_state, State = pcall(require, "sidekick.cli.state")

	if ok_state and tool then
		if has_local_session(tool) then
			-- A local session is already running. Use State.with() to attach
			-- and show it, then send inside the callback.
			dlog("taking State.with() chaining path")
			State.with(function()
				sidekick_cli.send({ text = text, name = tool, submit = sidekick_cfg.submit })
			end, { attach = true, filter = { name = tool, started = true, external = false }, show = true, focus = false })
			return
		end

		-- No local session is running. Pre-create one and send directly.
		if precreate_session(tool) then
			sidekick_cli.send({ text = text, name = tool, submit = sidekick_cfg.submit })
			return
		end
	end

	-- Fallback: send directly
	sidekick_cli.send({ text = text, name = tool, submit = sidekick_cfg.submit })
end

return M

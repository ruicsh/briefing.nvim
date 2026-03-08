local M = {}

local dlog = require("briefing.log").dlog

--- Translate a single briefing token to its sidekick-ready string.
--- Returns nil when the token should be self-resolved inline instead.
---@param token briefing.Token
---@param prev_winid? integer  window that was active before briefing opened
---@param tool? string         sidekick tool name, e.g. "opencode"
---@return string|nil
local function translate_token(token, prev_winid, tool)
	if token.name == "buffer" and not (token.suboption and token.suboption ~= "all") then
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
---@return string  translated prompt ready for sidekick_cli.send()
local function translate(raw_text, tokens, prev_winid)
	local context = require("briefing.context")
	local cfg = require("briefing.config").options
	local tool = cfg.adapter and cfg.adapter.sidekick and cfg.adapter.sidekick.tool or nil
	local result = raw_text

	dlog("translate: token_count=" .. #tokens .. " raw_text(80)=" .. raw_text:sub(1, 80):gsub("\n", "\\n"))

	for _, token in ipairs(tokens) do
		dlog("token: raw=" .. token.raw .. " name=" .. token.name .. " suboption=" .. tostring(token.suboption))
		local escaped = token.raw:gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1")
		local translated = translate_token(token, prev_winid, tool)

		dlog("translate_token result=" .. tostring(translated))

		if translated then
			result = result:gsub(escaped, translated, 1)
			dlog("result after translate gsub (80)=" .. result:sub(1, 80):gsub("\n", "\\n"))
		else
			-- Self-resolve tokens the tool cannot handle natively
			local resolved = context.resolve(token, prev_winid)
			dlog(
				"resolved type="
					.. type(resolved)
					.. " len="
					.. (resolved ~= nil and tostring(#resolved) or "nil")
					.. " val(80)="
					.. (resolved ~= nil and resolved:sub(1, 80):gsub("\n", "\\n") or "nil")
			)
			if resolved ~= nil then
				result = result:gsub(escaped, resolved, 1)
				dlog("result after resolve gsub (80)=" .. result:sub(1, 80):gsub("\n", "\\n"))
			end
		end
	end

	dlog("translate final (80)=" .. result:sub(1, 80):gsub("\n", "\\n"))
	return result
end

--- Convert a plain string to sidekick.Text[] so sidekick skips its template
--- renderer and sends the content verbatim (no `{token}` expansion).
---@param str string
---@return table
local function to_text(str)
	local ok, Text = pcall(require, "sidekick.text")
	if not ok then
		return {}
	end
	return Text.to_text(str)
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

	-- Pass as pre-rendered text so sidekick does not re-parse the content for
	-- {token} template expressions (which would misfire on Lua table literals
	-- or any other `{...}` present in resolved context blocks).
	local text = to_text(translated)
	local tool = sidekick_cfg.tool

	local ok_session, Session = pcall(require, "sidekick.cli.session")

	-- When a tool is configured and the State module is available, we manage
	-- session selection ourselves to avoid the picker UI that sidekick's
	-- internal State.with() would trigger when multiple entries exist (e.g. an
	-- external tmux session alongside an installed-but-not-started config entry).
	local ok_state, State = pcall(require, "sidekick.cli.state")
	dlog("ok_state=" .. tostring(ok_state) .. " ok_session=" .. tostring(ok_session) .. " tool=" .. tostring(tool))
	if ok_state and tool then
		local all_running = State.get({ name = tool, started = true })
		local dbg_all = {}
		for i, s in ipairs(all_running) do
			dbg_all[i] = "s"
				.. i
				.. "(external="
				.. tostring(s.external)
				.. " backend="
				.. tostring(s.session and s.session.backend or "nil")
				.. " terminal="
				.. tostring(s.terminal ~= nil)
				.. ")"
		end
		dlog("all started=" .. #all_running .. " [" .. table.concat(dbg_all, ", ") .. "]")

		local running = State.get({ name = tool, started = true, external = false })
		dlog("non-external started=" .. #running)

		if #running >= 1 then
			-- A local (non-external) session is already running.  Use
			-- State.with() to attach and show it, then send inside the
			-- callback so the prompt reaches the right terminal.
			dlog("taking State.with() chaining path")
			State.with(function()
				sidekick_cli.send({ text = text, name = tool, submit = sidekick_cfg.submit })
			end, { attach = true, filter = { name = tool, started = true, external = false }, show = true, focus = false })
			return
		end

		-- No local session is running (there may be external-only sessions).
		-- Pre-create and attach a local terminal session so that
		-- sidekick_cli.send()'s internal State.with() finds exactly one
		-- attached session and skips the picker UI entirely.
		if ok_session then
			dlog("pre-starting new local terminal session")
			local session = Session.new({ tool = tool })
			Session.attach(session)
			sidekick_cli.send({ text = text, name = tool, submit = sidekick_cfg.submit })
			return
		end
		dlog("falling through to sidekick_cli.send()")
	end

	sidekick_cli.send({ text = text, name = tool, submit = sidekick_cfg.submit })
end

return M

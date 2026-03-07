local config = require("briefing.config")

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function reset()
	config.setup()
	package.loaded["briefing.adapter"] = nil
	package.loaded["briefing.adapter.callback"] = nil
	package.loaded["briefing.adapter.sidekick"] = nil
	package.loaded["briefing.context"] = nil
	package.loaded["briefing.context.buffer"] = nil
	package.loaded["sidekick.cli"] = nil
	package.loaded["sidekick.cli.session"] = nil
	package.loaded["sidekick.cli.state"] = nil
	package.loaded["sidekick.text"] = nil
	package.preload["sidekick.cli"] = nil
	package.preload["sidekick.cli.session"] = nil
	package.preload["sidekick.cli.state"] = nil
	package.preload["sidekick.text"] = nil
	package.preload["briefing.context"] = nil
end

-- Minimal fake tokens list for tests that don't care about token content
local no_tokens = {}

-- Minimal sidekick.text stub: to_text(str) → sidekick.Text[] (one chunk per line)
local function stub_sidekick_text()
	package.preload["sidekick.text"] = function()
		return {
			to_text = function(data)
				if type(data) == "string" then
					if data == "" then
						return {}
					end
					local lines = vim.split(data, "\n", { plain = true })
					return vim.tbl_map(function(s)
						return { { s } }
					end, lines)
				end
				return data
			end,
		}
	end
end

-- Extract the plain string from a sidekick.Text[] (for assertions).
-- Each element is a line (sidekick.Text = sidekick.Chunk[]).
-- Joins lines with "\n" and concatenates all chunk strings per line.
local function text_to_string(text)
	if not text then
		return nil
	end
	local lines = {}
	for _, line in ipairs(text) do
		local parts = {}
		for _, chunk in ipairs(line) do
			parts[#parts + 1] = chunk[1]
		end
		lines[#lines + 1] = table.concat(parts)
	end
	return table.concat(lines, "\n")
end

-- ---------------------------------------------------------------------------
-- adapter.get() — factory dispatch
-- ---------------------------------------------------------------------------

describe("briefing.adapter.get()", function()
	before_each(function()
		reset()
	end)
	after_each(reset)

	it("returns the callback adapter when config.adapter.name = 'callback'", function()
		config.setup({ adapter = { name = "callback" } })
		package.loaded["briefing.adapter"] = nil
		local adapter_mod = require("briefing.adapter")
		local callback_mod = require("briefing.adapter.callback")
		assert.equals(callback_mod, adapter_mod.get())
	end)

	it("returns the sidekick adapter when config.adapter.name = 'sidekick'", function()
		config.setup({ adapter = { name = "sidekick" } })
		package.loaded["briefing.adapter"] = nil
		local adapter_mod = require("briefing.adapter")
		local sidekick_mod = require("briefing.adapter.sidekick")
		assert.equals(sidekick_mod, adapter_mod.get())
	end)

	it("returns a custom table adapter when adapter.name is a table", function()
		local custom = { send = function() end }
		config.setup({ adapter = { name = custom } })
		package.loaded["briefing.adapter"] = nil
		local adapter_mod = require("briefing.adapter")
		assert.equals(custom, adapter_mod.get())
	end)

	it("defaults to sidekick adapter when no adapter is configured", function()
		config.setup()
		package.loaded["briefing.adapter"] = nil
		local adapter_mod = require("briefing.adapter")
		local sidekick_mod = require("briefing.adapter.sidekick")
		assert.equals(sidekick_mod, adapter_mod.get())
	end)
end)

-- ---------------------------------------------------------------------------
-- callback adapter
-- ---------------------------------------------------------------------------

describe("briefing.adapter.callback", function()
	local callback_adapter

	before_each(function()
		reset()
		callback_adapter = require("briefing.adapter.callback")
	end)
	after_each(reset)

	it("calls the configured callback with the resolved text (no tokens)", function()
		local received = nil
		config.setup({
			adapter = {
				name = "callback",
				callback = function(text)
					received = text
				end,
			},
		})

		callback_adapter.send("hello world", no_tokens, nil)
		assert.equals("hello world", received)
	end)

	it("copies to clipboard when no callback is configured", function()
		config.setup({ adapter = { name = "callback" } })

		local setreg_called = false
		local orig_setreg = vim.fn.setreg
		vim.fn.setreg = function(reg, val)
			if reg == "+" then
				setreg_called = true
			end
			return orig_setreg(reg, val)
		end

		local orig_notify = vim.notify
		vim.notify = function() end

		callback_adapter.send("clip me", no_tokens, nil)

		vim.fn.setreg = orig_setreg
		vim.notify = orig_notify
		assert.is_true(setreg_called)
	end)

	it("notifies INFO when copying to clipboard", function()
		config.setup({ adapter = { name = "callback" } })

		local notified_level = nil
		local orig = vim.notify
		vim.notify = function(_, level)
			notified_level = level
		end

		local orig_setreg = vim.fn.setreg
		vim.fn.setreg = function() end

		callback_adapter.send("clip me", no_tokens, nil)

		vim.notify = orig
		vim.fn.setreg = orig_setreg
		assert.equals(vim.log.levels.INFO, notified_level)
	end)

	it("substitutes a #buffer token with its resolved content", function()
		-- Stub context resolver
		package.loaded["briefing.context"] = {
			resolve = function()
				return "BUFFER_CONTENT"
			end,
		}

		local received = nil
		config.setup({
			adapter = {
				callback = function(text)
					received = text
				end,
			},
		})

		local tokens = { { type = "context", name = "buffer", suboption = nil, raw = "#buffer" } }
		callback_adapter.send("Review: #buffer please", tokens, nil)

		assert.equals("Review: BUFFER_CONTENT please", received)
	end)

	it("leaves unresolvable tokens in place", function()
		package.loaded["briefing.context"] = {
			resolve = function()
				return nil
			end,
		}

		local received = nil
		config.setup({
			adapter = {
				callback = function(text)
					received = text
				end,
			},
		})

		local tokens = { { type = "context", name = "unknown", suboption = nil, raw = "#unknown" } }
		callback_adapter.send("see #unknown token", tokens, nil)

		assert.equals("see #unknown token", received)
	end)
end)

-- ---------------------------------------------------------------------------
-- sidekick adapter
-- ---------------------------------------------------------------------------

describe("briefing.adapter.sidekick", function()
	local sidekick_adapter

	before_each(function()
		reset()
		stub_sidekick_text()
		sidekick_adapter = require("briefing.adapter.sidekick")
	end)
	after_each(reset)

	it("self-resolves #buffer inline when tool is not opencode", function()
		local received = nil
		package.preload["sidekick.cli"] = function()
			return {
				send = function(opts)
					received = opts
				end,
			}
		end

		-- mock context.resolve to return a known string
		package.loaded["briefing.context"] = {
			resolve = function()
				return "INLINED"
			end,
		}

		local tokens = { { type = "context", name = "buffer", suboption = nil, raw = "#buffer" } }
		sidekick_adapter.send("Review: #buffer thanks", tokens, nil)

		assert.is_not_nil(received)
		assert.equals("Review: INLINED thanks", text_to_string(received.text))
		assert.is_nil(received.name)
	end)

	it("translates #buffer to @<path> when tool is opencode and prev_winid is valid", function()
		local received = nil
		package.preload["sidekick.cli"] = function()
			return {
				send = function(opts)
					received = opts
				end,
			}
		end

		config.setup({ adapter = { sidekick = { tool = "opencode" } } })
		package.loaded["briefing.adapter.sidekick"] = nil
		sidekick_adapter = require("briefing.adapter.sidekick")

		-- create a real named buffer and a window to use as prev_winid
		local bufnr = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(bufnr, "/tmp/test_briefing_file.lua")
		local winid = vim.api.nvim_open_win(bufnr, false, {
			relative = "editor",
			width = 10,
			height = 1,
			row = 0,
			col = 0,
		})

		local expected_path = vim.api.nvim_buf_get_name(bufnr)

		local tokens = { { type = "context", name = "buffer", suboption = nil, raw = "#buffer" } }
		sidekick_adapter.send("Review: #buffer thanks", tokens, winid)

		vim.api.nvim_win_close(winid, true)
		vim.api.nvim_buf_delete(bufnr, { force = true })

		assert.is_not_nil(received)
		assert.equals("Review: @" .. expected_path .. " thanks", text_to_string(received.text))
		assert.equals("opencode", received.name)
	end)

	it("translates #buffer:all to @<path> when tool is opencode", function()
		local received = nil
		package.preload["sidekick.cli"] = function()
			return {
				send = function(opts)
					received = opts
				end,
			}
		end

		config.setup({ adapter = { sidekick = { tool = "opencode" } } })
		package.loaded["briefing.adapter.sidekick"] = nil
		sidekick_adapter = require("briefing.adapter.sidekick")

		local bufnr = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(bufnr, "/tmp/test_briefing_file.lua")
		local winid = vim.api.nvim_open_win(bufnr, false, {
			relative = "editor",
			width = 10,
			height = 1,
			row = 0,
			col = 0,
		})

		local expected_path = vim.api.nvim_buf_get_name(bufnr)

		local tokens = { { type = "context", name = "buffer", suboption = "all", raw = "#buffer:all" } }
		sidekick_adapter.send("see #buffer:all", tokens, winid)

		vim.api.nvim_win_close(winid, true)
		vim.api.nvim_buf_delete(bufnr, { force = true })

		assert.is_not_nil(received)
		assert.equals("see @" .. expected_path, text_to_string(received.text))
	end)

	it("self-resolves #buffer:diff inline even when tool is opencode", function()
		local received = nil
		package.preload["sidekick.cli"] = function()
			return {
				send = function(opts)
					received = opts
				end,
			}
		end

		package.loaded["briefing.context"] = {
			resolve = function()
				return "DIFF_CONTENT"
			end,
		}

		config.setup({ adapter = { sidekick = { tool = "opencode" } } })
		package.loaded["briefing.adapter.sidekick"] = nil
		sidekick_adapter = require("briefing.adapter.sidekick")

		local tokens = { { type = "context", name = "buffer", suboption = "diff", raw = "#buffer:diff" } }
		sidekick_adapter.send("see #buffer:diff", tokens, nil)

		assert.is_not_nil(received)
		assert.equals("see DIFF_CONTENT", text_to_string(received.text))
	end)

	it("passes prompt unchanged when there are no tokens", function()
		local received = nil
		package.preload["sidekick.cli"] = function()
			return {
				send = function(opts)
					received = opts
				end,
			}
		end

		sidekick_adapter.send("plain prompt", no_tokens, nil)
		assert.equals("plain prompt", text_to_string(received.text))
		assert.is_nil(received.name)
	end)

	it("forwards adapter.sidekick.tool as name to sidekick_cli.send()", function()
		local received = nil
		package.preload["sidekick.cli"] = function()
			return {
				send = function(opts)
					received = opts
				end,
			}
		end

		config.setup({ adapter = { sidekick = { tool = "opencode" } } })
		package.loaded["briefing.adapter.sidekick"] = nil
		sidekick_adapter = require("briefing.adapter.sidekick")

		sidekick_adapter.send("plain prompt", no_tokens, nil)
		assert.equals("plain prompt", text_to_string(received.text))
		assert.equals("opencode", received.name)
		assert.is_true(received.submit)
	end)

	it("forwards submit = false when configured", function()
		local received = nil
		package.preload["sidekick.cli"] = function()
			return {
				send = function(opts)
					received = opts
				end,
			}
		end

		config.setup({ adapter = { sidekick = { tool = "opencode", submit = false } } })
		package.loaded["briefing.adapter.sidekick"] = nil
		sidekick_adapter = require("briefing.adapter.sidekick")

		sidekick_adapter.send("plain prompt", no_tokens, nil)
		assert.equals("plain prompt", text_to_string(received.text))
		assert.is_false(received.submit)
	end)

	it("notifies ERROR when sidekick.nvim is not installed", function()
		package.loaded["sidekick.cli"] = nil
		package.preload["sidekick.cli"] = nil

		local notified_level = nil
		local orig = vim.notify
		vim.notify = function(_, level)
			notified_level = level
		end

		sidekick_adapter.send("hello", no_tokens, nil)

		vim.notify = orig
		assert.equals(vim.log.levels.ERROR, notified_level)
	end)

	it("calls State.with() to attach-and-send when a running session exists", function()
		local with_called = false
		local with_opts = nil
		package.preload["sidekick.cli.state"] = function()
			return {
				get = function()
					return { { tool = { name = "opencode" }, session = { id = "s1" } } }
				end,
				with = function(_cb, opts)
					with_called = true
					with_opts = opts
					-- do NOT invoke _cb — mirrors real async behaviour
				end,
			}
		end
		package.preload["sidekick.cli"] = function()
			return { send = function() end }
		end

		config.setup({ adapter = { sidekick = { tool = "opencode" } } })
		package.loaded["briefing.adapter.sidekick"] = nil
		sidekick_adapter = require("briefing.adapter.sidekick")

		sidekick_adapter.send("prompt", no_tokens, nil)

		assert.is_true(with_called)
		assert.equals("opencode", with_opts.filter.name)
		assert.is_true(with_opts.filter.started)
		assert.is_false(with_opts.filter.external)
		assert.is_true(with_opts.attach)
		assert.is_true(with_opts.show)
		assert.is_false(with_opts.focus)
	end)

	it("State.with() callback calls sidekick_cli.send() with the translated prompt as text", function()
		local sent_opts = nil
		package.preload["sidekick.cli.state"] = function()
			return {
				get = function()
					return { { tool = { name = "opencode" }, session = { id = "s1" } } }
				end,
				with = function(cb, _opts)
					cb() -- invoke synchronously to simulate attach completing
				end,
			}
		end
		package.preload["sidekick.cli"] = function()
			return {
				send = function(opts)
					sent_opts = opts
				end,
			}
		end

		config.setup({ adapter = { sidekick = { tool = "opencode" } } })
		package.loaded["briefing.adapter.sidekick"] = nil
		sidekick_adapter = require("briefing.adapter.sidekick")

		sidekick_adapter.send("my prompt", no_tokens, nil)

		assert.is_not_nil(sent_opts)
		assert.equals("my prompt", text_to_string(sent_opts.text))
		assert.equals("opencode", sent_opts.name)
	end)

	it(
		"falls back to sidekick_cli.send() directly when no session is running and Session module is unavailable",
		function()
			local send_called = false
			local with_called = false
			package.preload["sidekick.cli.state"] = function()
				return {
					get = function()
						return {}
					end,
					with = function()
						with_called = true
					end,
				}
			end
			package.preload["sidekick.cli"] = function()
				return {
					send = function()
						send_called = true
					end,
				}
			end

			config.setup({ adapter = { sidekick = { tool = "opencode" } } })
			package.loaded["briefing.adapter.sidekick"] = nil
			sidekick_adapter = require("briefing.adapter.sidekick")

			sidekick_adapter.send("prompt", no_tokens, nil)

			assert.is_false(with_called)
			assert.is_true(send_called)
		end
	)

	it("pre-starts a local terminal session when no local session is running", function()
		local new_called_with = nil
		local attach_called_with = nil
		local send_called = false
		package.preload["sidekick.cli.session"] = function()
			return {
				attached = function()
					return {}
				end,
				detach = function() end,
				new = function(opts)
					new_called_with = opts
					return { tool = { name = opts.tool }, id = "new-session" }
				end,
				attach = function(session)
					attach_called_with = session
					return session
				end,
			}
		end
		package.preload["sidekick.cli.state"] = function()
			return {
				get = function()
					return {}
				end,
				with = function() end,
			}
		end
		package.preload["sidekick.cli"] = function()
			return {
				send = function()
					send_called = true
				end,
			}
		end

		config.setup({ adapter = { sidekick = { tool = "opencode" } } })
		package.loaded["briefing.adapter.sidekick"] = nil
		sidekick_adapter = require("briefing.adapter.sidekick")

		sidekick_adapter.send("prompt", no_tokens, nil)

		assert.is_not_nil(new_called_with)
		assert.equals("opencode", new_called_with.tool)
		assert.is_not_nil(attach_called_with)
		assert.equals("new-session", attach_called_with.id)
		assert.is_true(send_called)
	end)

	it(
		"falls back to sidekick_cli.send() directly when only external sessions exist and Session module is unavailable",
		function()
			local send_called = false
			local with_called = false
			-- State.get() returns empty (external=false filter excludes external sessions)
			package.preload["sidekick.cli.state"] = function()
				return {
					get = function()
						return {}
					end,
					with = function()
						with_called = true
					end,
				}
			end
			package.preload["sidekick.cli"] = function()
				return {
					send = function()
						send_called = true
					end,
				}
			end

			config.setup({ adapter = { sidekick = { tool = "opencode" } } })
			package.loaded["briefing.adapter.sidekick"] = nil
			sidekick_adapter = require("briefing.adapter.sidekick")

			sidekick_adapter.send("prompt", no_tokens, nil)

			assert.is_false(with_called)
			assert.is_true(send_called)
		end
	)

	it("falls back to sidekick_cli.send() directly when no tool is configured", function()
		local send_called = false
		local with_called = false
		package.preload["sidekick.cli.state"] = function()
			return {
				get = function()
					return { { tool = { name = "opencode" }, session = { id = "s1" } } }
				end,
				with = function()
					with_called = true
				end,
			}
		end
		package.preload["sidekick.cli"] = function()
			return {
				send = function()
					send_called = true
				end,
			}
		end

		config.setup({ adapter = { sidekick = {} } })
		package.loaded["briefing.adapter.sidekick"] = nil
		sidekick_adapter = require("briefing.adapter.sidekick")

		sidekick_adapter.send("prompt", no_tokens, nil)

		assert.is_false(with_called)
		assert.is_true(send_called)
	end)
end)

-- ---------------------------------------------------------------------------
-- adapter.send() — top-level dispatch
-- ---------------------------------------------------------------------------

describe("briefing.adapter.send()", function()
	before_each(reset)
	after_each(reset)

	it("dispatches to the configured adapter's send()", function()
		local called = false
		local custom = {
			send = function()
				called = true
			end,
		}
		config.setup({ adapter = { name = custom } })
		package.loaded["briefing.adapter"] = nil

		require("briefing.adapter").send("text", no_tokens, nil)
		assert.is_true(called)
	end)
end)

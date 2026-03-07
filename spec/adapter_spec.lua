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
	package.preload["sidekick.cli"] = nil
end

-- Minimal fake tokens list for tests that don't care about token content
local no_tokens = {}

-- ---------------------------------------------------------------------------
-- adapter.get() — factory dispatch
-- ---------------------------------------------------------------------------

describe("briefing.adapter.get()", function()
	before_each(function()
		reset()
	end)
	after_each(reset)

	it("returns the callback adapter when config.adapter = 'callback'", function()
		config.setup({ adapter = "callback" })
		package.loaded["briefing.adapter"] = nil
		local adapter_mod = require("briefing.adapter")
		local callback_mod = require("briefing.adapter.callback")
		assert.equals(callback_mod, adapter_mod.get())
	end)

	it("returns the sidekick adapter when config.adapter = 'sidekick'", function()
		config.setup({ adapter = "sidekick" })
		package.loaded["briefing.adapter"] = nil
		local adapter_mod = require("briefing.adapter")
		local sidekick_mod = require("briefing.adapter.sidekick")
		assert.equals(sidekick_mod, adapter_mod.get())
	end)

	it("returns a custom table adapter directly", function()
		local custom = { send = function() end }
		config.setup({ adapter = custom })
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
			adapter = "callback",
			adapter_config = {
				callback = function(text)
					received = text
				end,
			},
		})

		callback_adapter.send("hello world", no_tokens, nil)
		assert.equals("hello world", received)
	end)

	it("copies to clipboard when no callback is configured", function()
		config.setup({ adapter = "callback" })

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
		config.setup({ adapter = "callback" })

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
			adapter_config = {
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
			adapter_config = {
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
		sidekick_adapter = require("briefing.adapter.sidekick")
	end)
	after_each(reset)

	it("translates #buffer to {file} and calls sidekick_cli.send()", function()
		local received = nil
		package.preload["sidekick.cli"] = function()
			return {
				send = function(opts)
					received = opts
				end,
			}
		end

		local tokens = { { type = "context", name = "buffer", suboption = nil, raw = "#buffer" } }
		sidekick_adapter.send("Review: #buffer thanks", tokens, nil)

		assert.is_not_nil(received)
		assert.equals("Review: {file} thanks", received.msg)
		assert.is_nil(received.name)
	end)

	it("translates #buffer:all to {file}", function()
		local received = nil
		package.preload["sidekick.cli"] = function()
			return {
				send = function(opts)
					received = opts
				end,
			}
		end

		local tokens = { { type = "context", name = "buffer", suboption = "all", raw = "#buffer:all" } }
		sidekick_adapter.send("see #buffer:all", tokens, nil)

		assert.is_not_nil(received)
		assert.equals("see {file}", received.msg)
		assert.is_nil(received.name)
	end)

	it("translates #buffer:diff to {file} and emits a WARN", function()
		local received = nil
		local notified_level = nil
		package.preload["sidekick.cli"] = function()
			return {
				send = function(opts)
					received = opts
				end,
			}
		end

		local orig = vim.notify
		vim.notify = function(_, level)
			notified_level = level
		end

		local tokens = { { type = "context", name = "buffer", suboption = "diff", raw = "#buffer:diff" } }
		sidekick_adapter.send("see #buffer:diff", tokens, nil)

		vim.notify = orig

		assert.equals("see {file}", received.msg)
		assert.equals(vim.log.levels.WARN, notified_level)
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
		assert.equals("plain prompt", received.msg)
		assert.is_nil(received.name)
	end)

	it("forwards adapter_config.sidekick.tool as name to sidekick_cli.send()", function()
		local received = nil
		package.preload["sidekick.cli"] = function()
			return {
				send = function(opts)
					received = opts
				end,
			}
		end

		config.setup({ adapter_config = { sidekick = { tool = "opencode" } } })
		package.loaded["briefing.adapter.sidekick"] = nil
		sidekick_adapter = require("briefing.adapter.sidekick")

		sidekick_adapter.send("plain prompt", no_tokens, nil)
		assert.equals("plain prompt", received.msg)
		assert.equals("opencode", received.name)
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
		config.setup({ adapter = custom })
		package.loaded["briefing.adapter"] = nil

		require("briefing.adapter").send("text", no_tokens, nil)
		assert.is_true(called)
	end)
end)

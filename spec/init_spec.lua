local config = require("briefing.config")
local briefing = require("briefing")

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

--- Clean up window / buffer / config between tests.
local function reset()
	local winid = vim.t.briefing_winid
	if winid and vim.api.nvim_win_is_valid(winid) then
		vim.api.nvim_win_close(winid, true)
	end
	vim.t.briefing_winid = nil

	local bufnr = vim.t.briefing_bufnr
	if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
		vim.api.nvim_buf_delete(bufnr, { force = true })
	end
	vim.t.briefing_bufnr = nil

	config.setup()

	-- Remove any injected mock modules from the package cache so tests that
	-- install or remove sidekick don't bleed into each other.
	package.loaded["sidekick.cli"] = nil
	package.preload["sidekick.cli"] = nil
	package.loaded["sidekick.cli.session"] = nil
	package.preload["sidekick.cli.session"] = nil
	package.loaded["sidekick.cli.state"] = nil
	package.preload["sidekick.cli.state"] = nil
	package.loaded["sidekick.text"] = nil
	package.preload["sidekick.text"] = nil
	package.loaded["briefing.adapter"] = nil
	package.loaded["briefing.adapter.callback"] = nil
	package.loaded["briefing.adapter.sidekick"] = nil
	package.loaded["briefing.context"] = nil
end

-- Minimal sidekick.text stub used by tests that exercise the sidekick adapter.
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

-- Extract a plain string from a sidekick.Text[] (reverses to_text).
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
-- setup()
-- ---------------------------------------------------------------------------

describe("briefing.setup()", function()
	before_each(reset)
	after_each(reset)

	it("delegates to config and updates options", function()
		briefing.setup({ window = { width = 55 } })
		assert.equals(55, config.options.window.width)
	end)

	it("preserves other defaults when called with partial opts", function()
		briefing.setup({ window = { border = "single" } })
		assert.equals("single", config.options.window.border)
		assert.equals(100, config.options.window.width)
	end)
end)

-- ---------------------------------------------------------------------------
-- open() / close()
-- ---------------------------------------------------------------------------

describe("briefing.open() / close()", function()
	before_each(reset)
	after_each(reset)

	it("open() creates a valid floating window", function()
		briefing.open()
		assert.is_true(vim.api.nvim_win_is_valid(vim.t.briefing_winid))
	end)

	it("close() hides the window", function()
		briefing.open()
		local winid = vim.t.briefing_winid
		briefing.close()
		assert.is_false(vim.api.nvim_win_is_valid(winid))
	end)

	it("close() sets briefing_winid to nil", function()
		briefing.open()
		briefing.close()
		assert.is_nil(vim.t.briefing_winid)
	end)

	it("close() preserves buffer content", function()
		briefing.open()
		local bufnr = vim.t.briefing_bufnr
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "persist me" })
		briefing.close()
		assert.is_true(vim.api.nvim_buf_is_valid(bufnr))
	end)
end)

-- ---------------------------------------------------------------------------
-- send()
-- ---------------------------------------------------------------------------

describe("briefing.send()", function()
	before_each(reset)
	after_each(reset)

	-- Helper: set the briefing buffer to the given lines.
	local function set_buffer_text(lines)
		briefing.open()
		local bufnr = vim.t.briefing_bufnr
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	end

	it("notifies WARN when the buffer is empty", function()
		briefing.open()

		local notified_level = nil
		local orig = vim.notify
		vim.notify = function(_, level)
			notified_level = level
		end

		briefing.send()

		vim.notify = orig
		assert.equals(vim.log.levels.WARN, notified_level)
	end)

	it("notifies WARN when the buffer contains only whitespace", function()
		set_buffer_text({ "   ", "\t", "" })

		local notified_level = nil
		local orig = vim.notify
		vim.notify = function(_, level)
			notified_level = level
		end

		briefing.send()

		vim.notify = orig
		assert.equals(vim.log.levels.WARN, notified_level)
	end)

	it("notifies WARN when the buffer contains only empty lines", function()
		set_buffer_text({ "", "", "" })

		local notified_level = nil
		local notified_message = nil
		local orig = vim.notify
		vim.notify = function(msg, level)
			notified_message = msg
			notified_level = level
		end

		briefing.send()

		vim.notify = orig
		assert.equals(vim.log.levels.WARN, notified_level)
		assert.equals("Briefing: prompt is empty", notified_message)
	end)

	it("notifies ERROR when using the sidekick adapter and sidekick.nvim is not installed", function()
		set_buffer_text({ "hello" })
		-- Configure the sidekick adapter
		config.setup({ adapter = { name = "sidekick" } })
		-- Ensure sidekick.cli is absent
		package.loaded["sidekick.cli"] = nil
		package.preload["sidekick.cli"] = nil

		local notified_level = nil
		local orig = vim.notify
		vim.notify = function(_, level)
			notified_level = level
		end

		briefing.send()

		vim.notify = orig
		assert.equals(vim.log.levels.ERROR, notified_level)
	end)

	it("sends via sidekick adapter with the trimmed buffer text", function()
		set_buffer_text({ "  hello world  " })
		config.setup({ adapter = { name = "sidekick" } })
		stub_sidekick_text()

		local received = nil
		package.preload["sidekick.cli"] = function()
			return {
				send = function(opts)
					received = opts
				end,
			}
		end
		-- Force reload to pick up the preload stub
		package.loaded["sidekick.cli"] = nil

		briefing.send()

		assert.is_not_nil(received)
		assert.equals("hello world", text_to_string(received.text))
	end)

	it("sends via sidekick adapter with multi-line text intact", function()
		set_buffer_text({ "line one", "line two" })
		config.setup({ adapter = { name = "sidekick" } })
		stub_sidekick_text()

		local received = nil
		package.preload["sidekick.cli"] = function()
			return {
				send = function(opts)
					received = opts
				end,
			}
		end
		package.loaded["sidekick.cli"] = nil

		briefing.send()

		assert.is_not_nil(received)
		assert.equals("line one\nline two", text_to_string(received.text))
	end)

	it("closes the window after a successful send", function()
		set_buffer_text({ "send this" })
		-- Use callback adapter with a no-op callback to avoid clipboard side effects
		config.setup({
			adapter = {
				name = "callback",
				callback = function() end,
			},
		})

		briefing.send()

		assert.is_nil(vim.t.briefing_winid)
	end)

	it("does NOT close the window when the buffer is empty", function()
		briefing.open()
		local winid = vim.t.briefing_winid

		local orig = vim.notify
		vim.notify = function() end

		briefing.send()

		vim.notify = orig
		-- Window should still be open
		assert.is_true(vim.api.nvim_win_is_valid(winid))
	end)
end)

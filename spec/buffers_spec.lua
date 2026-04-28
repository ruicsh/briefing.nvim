local config = require("briefing.config")

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function reset()
	config.setup()
	package.loaded["briefing.context"] = nil
	package.loaded["briefing.context.buffers"] = nil
	package.loaded["briefing.context.util"] = nil
end

-- ---------------------------------------------------------------------------
-- context/buffers.lua
-- ---------------------------------------------------------------------------

describe("briefing.context.buffers.resolve() #buffers", function()
	local buffers_resolver
	local test_bufs = {}
	local test_wins = {}

	before_each(function()
		package.loaded["briefing.context.buffers"] = nil
		package.loaded["briefing.context.util"] = nil
		buffers_resolver = require("briefing.context.buffers")

		-- Clear any leftover test buffers/windows
		test_bufs = {}
		test_wins = {}
	end)

	after_each(function()
		for _, winid in ipairs(test_wins) do
			if vim.api.nvim_win_is_valid(winid) then
				vim.api.nvim_win_close(winid, true)
			end
		end
		for _, bufnr in ipairs(test_bufs) do
			if vim.api.nvim_buf_is_valid(bufnr) then
				vim.api.nvim_buf_delete(bufnr, { force = true })
			end
		end
		reset()
	end)

	it("returns empty string and warns when no listed buffers exist", function()
		-- Create an unlisted buffer only
		local bufnr = vim.api.nvim_create_buf(false, true)
		vim.bo[bufnr].buflisted = false
		table.insert(test_bufs, bufnr)

		local notified_level = nil
		local orig = vim.notify
		vim.notify = function(_, level)
			notified_level = level
		end

		local result = buffers_resolver.resolve()

		vim.notify = orig
		assert.equals("", result)
		assert.equals(vim.log.levels.WARN, notified_level)
	end)

	it("includes content from a single listed buffer", function()
		local bufnr = vim.api.nvim_create_buf(true, false)
		vim.bo[bufnr].filetype = "lua"
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "local x = 1", "return x" })
		vim.api.nvim_buf_set_name(bufnr, vim.fn.getcwd() .. "/test_buffer.lua")
		table.insert(test_bufs, bufnr)

		local result = buffers_resolver.resolve()

		assert.is_true(result:find("test_buffer.lua") ~= nil)
		assert.is_true(result:find("local x = 1") ~= nil)
		assert.is_true(result:find("return x") ~= nil)
		assert.is_true(result:find("```lua") ~= nil)
	end)

	it("includes content from multiple listed buffers", function()
		local buf1 = vim.api.nvim_create_buf(true, false)
		vim.bo[buf1].filetype = "lua"
		vim.api.nvim_buf_set_lines(buf1, 0, -1, false, { "-- buffer 1" })
		vim.api.nvim_buf_set_name(buf1, vim.fn.getcwd() .. "/buf1.lua")
		table.insert(test_bufs, buf1)

		local buf2 = vim.api.nvim_create_buf(true, false)
		vim.bo[buf2].filetype = "python"
		vim.api.nvim_buf_set_lines(buf2, 0, -1, false, { "# buffer 2" })
		vim.api.nvim_buf_set_name(buf2, vim.fn.getcwd() .. "/buf2.py")
		table.insert(test_bufs, buf2)

		local result = buffers_resolver.resolve()

		assert.is_true(result:find("buf1.lua") ~= nil)
		assert.is_true(result:find("buf2.py") ~= nil)
		assert.is_true(result:find("-- buffer 1") ~= nil)
		assert.is_true(result:find("# buffer 2") ~= nil)
	end)

	it("excludes unlisted buffers", function()
		local listed_buf = vim.api.nvim_create_buf(true, false)
		vim.bo[listed_buf].filetype = "lua"
		vim.api.nvim_buf_set_lines(listed_buf, 0, -1, false, { "-- listed" })
		vim.api.nvim_buf_set_name(listed_buf, vim.fn.getcwd() .. "/listed.lua")
		table.insert(test_bufs, listed_buf)

		local unlisted_buf = vim.api.nvim_create_buf(false, true)
		vim.bo[unlisted_buf].filetype = "python"
		vim.api.nvim_buf_set_lines(unlisted_buf, 0, -1, false, { "# unlisted" })
		vim.api.nvim_buf_set_name(unlisted_buf, vim.fn.getcwd() .. "/unlisted.py")
		table.insert(test_bufs, unlisted_buf)

		local result = buffers_resolver.resolve()

		assert.is_true(result:find("listed.lua") ~= nil)
		assert.is_true(result:find("-- listed") ~= nil)
		assert.is_false(result:find("unlisted.py") ~= nil)
		assert.is_false(result:find("# unlisted") ~= nil)
	end)

	it("excludes buffers with empty names", function()
		local bufnr = vim.api.nvim_create_buf(true, false)
		vim.bo[bufnr].filetype = "lua"
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "-- has content" })
		-- Don't set a name, so name is empty
		table.insert(test_bufs, bufnr)

		local result = buffers_resolver.resolve()

		-- Since the buffer has no name, format_buf_content returns nil
		-- and the buffer should not appear in output
		assert.is_true(result == "" or result:find("has content") == nil)
	end)

	it("excludes the briefing buffer itself", function()
		local briefing_buf = vim.api.nvim_create_buf(true, false)
		vim.bo[briefing_buf].filetype = "briefing"
		vim.api.nvim_buf_set_lines(briefing_buf, 0, -1, false, { "-- briefing content" })
		vim.api.nvim_buf_set_name(briefing_buf, vim.fn.getcwd() .. "/briefing.md")
		table.insert(test_bufs, briefing_buf)

		local other_buf = vim.api.nvim_create_buf(true, false)
		vim.bo[other_buf].filetype = "lua"
		vim.api.nvim_buf_set_lines(other_buf, 0, -1, false, { "-- other content" })
		vim.api.nvim_buf_set_name(other_buf, vim.fn.getcwd() .. "/other.lua")
		table.insert(test_bufs, other_buf)

		local result = buffers_resolver.resolve()

		assert.is_true(result:find("other.lua") ~= nil)
		assert.is_false(result:find("briefing.md") ~= nil)
		assert.is_false(result:find("briefing content") ~= nil)
	end)

	it("includes line count for each buffer", function()
		local bufnr = vim.api.nvim_create_buf(true, false)
		vim.bo[bufnr].filetype = "lua"
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line1", "line2", "line3" })
		vim.api.nvim_buf_set_name(bufnr, vim.fn.getcwd() .. "/lines.lua")
		table.insert(test_bufs, bufnr)

		local result = buffers_resolver.resolve()

		assert.is_true(result:find("lines 1%-3") ~= nil)
	end)
end)

-- ---------------------------------------------------------------------------
-- context.resolve() delegation
-- ---------------------------------------------------------------------------

describe("briefing.context.resolve() #buffers", function()
	local context

	before_each(function()
		reset()
		context = require("briefing.context")
	end)

	after_each(reset)

	it("delegates #buffers to buffers.resolve()", function()
		local called = false
		package.loaded["briefing.context.buffers"] = {
			resolve = function()
				called = true
				return "all buffers"
			end,
		}
		context = require("briefing.context")
		local token = { type = "context", name = "buffers", suboption = nil, raw = "#buffers" }
		local result = context.resolve(token, nil)

		assert.equals("all buffers", result)
		assert.is_true(called)
	end)
end)

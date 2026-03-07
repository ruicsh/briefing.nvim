local context = require("briefing.context")
local buffer_resolver = require("briefing.context.buffer")
local config = require("briefing.config")

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function reset()
	config.setup()
	package.loaded["briefing.context"] = nil
	package.loaded["briefing.context.buffer"] = nil
end

-- ---------------------------------------------------------------------------
-- context.parse()
-- ---------------------------------------------------------------------------

describe("briefing.context.parse()", function()
	before_each(function()
		package.loaded["briefing.context"] = nil
		context = require("briefing.context")
	end)
	after_each(reset)

	it("returns an empty table for an empty string", function()
		assert.same({}, context.parse(""))
	end)

	it("returns an empty table when no tokens present", function()
		assert.same({}, context.parse("hello world"))
	end)

	it("parses a bare #buffer token", function()
		local tokens = context.parse("#buffer")
		assert.equals(1, #tokens)
		assert.equals("context", tokens[1].type)
		assert.equals("buffer", tokens[1].name)
		assert.is_nil(tokens[1].suboption)
		assert.equals("#buffer", tokens[1].raw)
	end)

	it("parses #buffer:diff suboption", function()
		local tokens = context.parse("#buffer:diff")
		assert.equals(1, #tokens)
		assert.equals("buffer", tokens[1].name)
		assert.equals("diff", tokens[1].suboption)
		assert.equals("#buffer:diff", tokens[1].raw)
	end)

	it("parses #buffer:all suboption", function()
		local tokens = context.parse("#buffer:all")
		assert.equals(1, #tokens)
		assert.equals("all", tokens[1].suboption)
		assert.equals("#buffer:all", tokens[1].raw)
	end)

	it("parses a token in the middle of a sentence", function()
		local tokens = context.parse("Please review #buffer and let me know")
		assert.equals(1, #tokens)
		assert.equals("buffer", tokens[1].name)
	end)

	it("parses a token at the start of a line", function()
		local tokens = context.parse("intro\n#buffer\nend")
		assert.equals(1, #tokens)
		assert.equals("buffer", tokens[1].name)
	end)

	it("parses multiple tokens in order", function()
		local tokens = context.parse("#buffer:diff fix and #buffer")
		assert.equals(2, #tokens)
		assert.equals("diff", tokens[1].suboption)
		assert.is_nil(tokens[2].suboption)
	end)

	it("does NOT parse a token that is not preceded by whitespace or start", function()
		local tokens = context.parse("foo#buffer")
		assert.same({}, tokens)
	end)

	it("parses #bufferfoo as a single token named 'bufferfoo', not as #buffer", function()
		local tokens = context.parse("#bufferfoo")
		assert.equals(1, #tokens)
		assert.equals("bufferfoo", tokens[1].name)
	end)

	it("is case-sensitive: #Buffer is not parsed as #buffer", function()
		local tokens = context.parse("#Buffer")
		-- #Buffer parses as a token with name "Buffer", not "buffer"
		assert.equals(1, #tokens)
		assert.equals("Buffer", tokens[1].name)
	end)

	it("parses unknown token names without error", function()
		local tokens = context.parse("#unknownvar")
		assert.equals(1, #tokens)
		assert.equals("unknownvar", tokens[1].name)
	end)
end)

-- ---------------------------------------------------------------------------
-- context.resolve()
-- ---------------------------------------------------------------------------

describe("briefing.context.resolve()", function()
	before_each(function()
		package.loaded["briefing.context"] = nil
		package.loaded["briefing.context.buffer"] = nil
		context = require("briefing.context")
	end)
	after_each(reset)

	it("returns nil for an unknown token name", function()
		local token = { type = "context", name = "unknown", suboption = nil, raw = "#unknown" }
		assert.is_nil(context.resolve(token, nil))
	end)

	it("delegates #buffer to buffer.resolve()", function()
		local called_with = nil
		package.loaded["briefing.context.buffer"] = {
			resolve = function(suboption, prev_winid)
				called_with = { suboption = suboption, prev_winid = prev_winid }
				return "resolved"
			end,
		}

		local token = { type = "context", name = "buffer", suboption = nil, raw = "#buffer" }
		local result = context.resolve(token, 42)

		assert.equals("resolved", result)
		assert.is_nil(called_with.suboption)
		assert.equals(42, called_with.prev_winid)
	end)

	it("passes suboption to buffer.resolve()", function()
		local received_suboption = nil
		package.loaded["briefing.context.buffer"] = {
			resolve = function(suboption)
				received_suboption = suboption
				return ""
			end,
		}

		local token = { type = "context", name = "buffer", suboption = "diff", raw = "#buffer:diff" }
		context.resolve(token, nil)

		assert.equals("diff", received_suboption)
	end)
end)

-- ---------------------------------------------------------------------------
-- context.buffer.resolve() — #buffer:all (default)
-- ---------------------------------------------------------------------------

describe("briefing.context.buffer.resolve() #buffer:all", function()
	local test_bufnr
	local test_winid

	before_each(function()
		package.loaded["briefing.context.buffer"] = nil
		buffer_resolver = require("briefing.context.buffer")

		-- Create a scratch buffer with known content
		test_bufnr = vim.api.nvim_create_buf(false, true)
		vim.bo[test_bufnr].filetype = "lua"
		vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, { "local x = 1", "return x" })

		-- Open it in a window so we can pass a valid winid
		test_winid = vim.api.nvim_open_win(test_bufnr, false, {
			relative = "editor",
			width = 10,
			height = 2,
			col = 0,
			row = 0,
			style = "minimal",
		})
	end)

	after_each(function()
		if test_winid and vim.api.nvim_win_is_valid(test_winid) then
			vim.api.nvim_win_close(test_winid, true)
		end
		if test_bufnr and vim.api.nvim_buf_is_valid(test_bufnr) then
			vim.api.nvim_buf_delete(test_bufnr, { force = true })
		end
		package.loaded["briefing.context.buffer"] = nil
	end)

	it("returns a non-empty string", function()
		local result = buffer_resolver.resolve(nil, test_winid)
		assert.is_not_nil(result)
		assert.is_true(#result > 0)
	end)

	it("includes the buffer content", function()
		local result = buffer_resolver.resolve(nil, test_winid)
		assert.is_true(result:find("local x = 1") ~= nil)
		assert.is_true(result:find("return x") ~= nil)
	end)

	it("includes the line count", function()
		local result = buffer_resolver.resolve(nil, test_winid)
		assert.is_true(result:find("lines 1%-2") ~= nil)
	end)

	it("includes the filetype as fenced code language", function()
		local result = buffer_resolver.resolve(nil, test_winid)
		assert.is_true(result:find("```lua") ~= nil)
	end)

	it("treats suboption 'all' the same as nil", function()
		local r_nil = buffer_resolver.resolve(nil, test_winid)
		local r_all = buffer_resolver.resolve("all", test_winid)
		assert.equals(r_nil, r_all)
	end)

	it("uses the current window buffer when prev_winid is nil", function()
		-- The current window shows test_bufnr (we opened it); set it as current
		vim.api.nvim_set_current_win(test_winid)
		local result = buffer_resolver.resolve(nil, nil)
		assert.is_true(result:find("local x = 1") ~= nil)
	end)

	it("uses the current window buffer when prev_winid is invalid", function()
		vim.api.nvim_set_current_win(test_winid)
		local result = buffer_resolver.resolve(nil, 99999)
		assert.is_true(result:find("local x = 1") ~= nil)
	end)
end)

-- ---------------------------------------------------------------------------
-- context.buffer.resolve() — #buffer:diff
-- ---------------------------------------------------------------------------

describe("briefing.context.buffer.resolve() #buffer:diff", function()
	local test_bufnr
	local test_winid
	local orig_system

	before_each(function()
		package.loaded["briefing.context.buffer"] = nil
		buffer_resolver = require("briefing.context.buffer")

		test_bufnr = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(test_bufnr, "/tmp/briefing_test_fake.lua")
		vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, { "-- fake" })

		test_winid = vim.api.nvim_open_win(test_bufnr, false, {
			relative = "editor",
			width = 10,
			height = 1,
			col = 0,
			row = 0,
			style = "minimal",
		})

		orig_system = vim.system
	end)

	after_each(function()
		if test_winid and vim.api.nvim_win_is_valid(test_winid) then
			vim.api.nvim_win_close(test_winid, true)
		end
		if test_bufnr and vim.api.nvim_buf_is_valid(test_bufnr) then
			vim.api.nvim_buf_delete(test_bufnr, { force = true })
		end
		vim.system = orig_system
		package.loaded["briefing.context.buffer"] = nil
	end)

	-- Helper: stub vim.system to return a fake completed-process object
	local function stub_system(stdout, code, stderr)
		vim.system = function()
			return {
				wait = function()
					return { code = code, stdout = stdout, stderr = stderr or "" }
				end,
			}
		end
	end

	it("returns diff output wrapped in a diff code block", function()
		stub_system("diff output here\n", 0)
		local result = buffer_resolver.resolve("diff", test_winid)
		assert.is_true(result:find("```diff") ~= nil)
		assert.is_true(result:find("diff output here") ~= nil)
	end)

	it("includes 'diff' in the File: header", function()
		stub_system("diff output\n", 0)
		local result = buffer_resolver.resolve("diff", test_winid)
		assert.is_true(result:find("%(diff%)") ~= nil)
	end)

	it("returns empty string when git diff returns nothing", function()
		stub_system("", 0)
		local result = buffer_resolver.resolve("diff", test_winid)
		assert.equals("", result)
	end)

	it("returns empty string and warns when git exits non-zero", function()
		stub_system(nil, 128, "fatal: not a git repo\n")

		local notified_level = nil
		local orig = vim.notify
		vim.notify = function(_, level)
			notified_level = level
		end

		local result = buffer_resolver.resolve("diff", test_winid)

		vim.notify = orig
		assert.equals("", result)
		assert.equals(vim.log.levels.WARN, notified_level)
	end)

	it("returns empty string and warns for a buffer with no file path", function()
		local unnamed_buf = vim.api.nvim_create_buf(false, true)
		local unnamed_win = vim.api.nvim_open_win(unnamed_buf, false, {
			relative = "editor",
			width = 5,
			height = 1,
			col = 0,
			row = 0,
			style = "minimal",
		})

		local notified_level = nil
		local orig = vim.notify
		vim.notify = function(_, level)
			notified_level = level
		end

		local result = buffer_resolver.resolve("diff", unnamed_win)

		vim.notify = orig
		vim.api.nvim_win_close(unnamed_win, true)
		vim.api.nvim_buf_delete(unnamed_buf, { force = true })

		assert.equals("", result)
		assert.equals(vim.log.levels.WARN, notified_level)
	end)
end)

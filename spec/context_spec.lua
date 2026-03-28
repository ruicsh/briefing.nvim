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

	it("parses #diff:buffer suboption", function()
		local tokens = context.parse("#diff:buffer")
		assert.equals(1, #tokens)
		assert.equals("diff", tokens[1].name)
		assert.equals("buffer", tokens[1].suboption)
		assert.equals("#diff:buffer", tokens[1].raw)
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
		local tokens = context.parse("#diff:buffer fix and #buffer")
		assert.equals(2, #tokens)
		assert.equals("buffer", tokens[1].suboption)
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
			resolve = function(prev_winid)
				called_with = { prev_winid = prev_winid }
				return "resolved"
			end,
		}

		local token = { type = "context", name = "buffer", suboption = nil, raw = "#buffer" }
		local result = context.resolve(token, 42)

		assert.equals("resolved", result)
		assert.equals(42, called_with.prev_winid)
	end)
end)

-- ---------------------------------------------------------------------------
-- context.buffer.resolve() — #buffer
-- ---------------------------------------------------------------------------

describe("briefing.context.buffer.resolve() #buffer", function()
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
		local result = buffer_resolver.resolve(test_winid)
		assert.is_not_nil(result)
		assert.is_true(#result > 0)
	end)

	it("includes the buffer content", function()
		local result = buffer_resolver.resolve(test_winid)
		assert.is_true(result:find("local x = 1") ~= nil)
		assert.is_true(result:find("return x") ~= nil)
	end)

	it("includes the line count", function()
		local result = buffer_resolver.resolve(test_winid)
		assert.is_true(result:find("lines 1%-2") ~= nil)
	end)

	it("includes the filetype as fenced code language", function()
		local result = buffer_resolver.resolve(test_winid)
		assert.is_true(result:find("```lua") ~= nil)
	end)

	it("uses the current window buffer when prev_winid is nil", function()
		-- The current window shows test_bufnr (we opened it); set it as current
		vim.api.nvim_set_current_win(test_winid)
		local result = buffer_resolver.resolve(nil)
		assert.is_true(result:find("local x = 1") ~= nil)
	end)

	it("uses the current window buffer when prev_winid is invalid", function()
		vim.api.nvim_set_current_win(test_winid)
		local result = buffer_resolver.resolve(99999)
		assert.is_true(result:find("local x = 1") ~= nil)
	end)
end)

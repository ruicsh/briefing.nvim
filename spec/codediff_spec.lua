local codediff = require("briefing.context.codediff")

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function create_test_buffer(lines, filename, filetype)
	local bufnr = vim.api.nvim_create_buf(false, true)
	if filename then
		vim.api.nvim_buf_set_name(bufnr, filename)
	end
	if filetype then
		vim.bo[bufnr].filetype = filetype
	end
	if lines then
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	end
	return bufnr
end

local function create_test_window(bufnr)
	return vim.api.nvim_open_win(bufnr, false, {
		relative = "editor",
		width = 10,
		height = 10,
		col = 0,
		row = 0,
		style = "minimal",
	})
end

local function cleanup(bufnr, winid)
	if winid and vim.api.nvim_win_is_valid(winid) then
		vim.api.nvim_win_close(winid, true)
	end
	if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
		vim.api.nvim_buf_delete(bufnr, { force = true })
	end
end

-- Mock codediff lifecycle module
local function mock_codediff_lifecycle(session_data)
	local mock = {
		get_session = function(_tabpage)
			return session_data
		end,
	}
	package.loaded["codediff.ui.lifecycle"] = mock
end

local function clear_codediff_mock()
	package.loaded["codediff.ui.lifecycle"] = nil
end

-- ---------------------------------------------------------------------------
-- is_codediff() tests
-- ---------------------------------------------------------------------------

describe("briefing.context.codediff.is_codediff()", function()
	local test_bufnr
	local test_winid

	before_each(function()
		package.loaded["briefing.context.codediff"] = nil
		codediff = require("briefing.context.codediff")
		clear_codediff_mock()
	end)

	after_each(function()
		cleanup(test_bufnr, test_winid)
		package.loaded["briefing.context.codediff"] = nil
		clear_codediff_mock()
	end)

	it("returns false when codediff module is not installed", function()
		test_bufnr = create_test_buffer({ "some content" }, "/path/to/file.lua", "lua")
		test_winid = create_test_window(test_bufnr)

		-- Ensure codediff module is not loaded
		package.loaded["codediff.ui.lifecycle"] = nil

		assert.is_false(codediff.is_codediff(test_winid))
	end)

	it("returns false when there is no codediff session", function()
		test_bufnr = create_test_buffer({ "some content" }, "/path/to/file.lua", "lua")
		test_winid = create_test_window(test_bufnr)

		mock_codediff_lifecycle(nil)

		assert.is_false(codediff.is_codediff(test_winid))
	end)

	it("returns true when buffer is the original buffer in session", function()
		test_bufnr = create_test_buffer({ "original content" }, "/path/to/original.lua", "lua")
		test_winid = create_test_window(test_bufnr)

		mock_codediff_lifecycle({
			original_bufnr = test_bufnr,
			modified_bufnr = 99999,
		})

		assert.is_true(codediff.is_codediff(test_winid))
	end)

	it("returns true when buffer is the modified buffer in session", function()
		test_bufnr = create_test_buffer({ "modified content" }, "/path/to/modified.lua", "lua")
		test_winid = create_test_window(test_bufnr)

		mock_codediff_lifecycle({
			original_bufnr = 99999,
			modified_bufnr = test_bufnr,
		})

		assert.is_true(codediff.is_codediff(test_winid))
	end)

	it("returns false when buffer is not part of codediff session", function()
		test_bufnr = create_test_buffer({ "some content" }, "/path/to/file.lua", "lua")
		test_winid = create_test_window(test_bufnr)

		mock_codediff_lifecycle({
			original_bufnr = 99998,
			modified_bufnr = 99999,
		})

		assert.is_false(codediff.is_codediff(test_winid))
	end)

	it("defaults to current window when winid is nil", function()
		test_bufnr = create_test_buffer({ "some content" }, "/path/to/file.lua", "lua")
		test_winid = create_test_window(test_bufnr)
		vim.api.nvim_set_current_win(test_winid)

		mock_codediff_lifecycle({
			original_bufnr = test_bufnr,
			modified_bufnr = 99999,
		})

		assert.is_true(codediff.is_codediff())
	end)

	it("handles invalid window gracefully", function()
		mock_codediff_lifecycle({
			original_bufnr = 1,
			modified_bufnr = 2,
		})

		assert.has_no.errors(function()
			codediff.is_codediff(99999)
		end)
	end)
end)

-- ---------------------------------------------------------------------------
-- get_context() tests
-- ---------------------------------------------------------------------------

describe("briefing.context.codediff.get_context()", function()
	local test_bufnr
	local test_winid

	before_each(function()
		package.loaded["briefing.context.codediff"] = nil
		codediff = require("briefing.context.codediff")
		clear_codediff_mock()
	end)

	after_each(function()
		cleanup(test_bufnr, test_winid)
		package.loaded["briefing.context.codediff"] = nil
		clear_codediff_mock()
	end)

	it("returns nil when codediff module is not installed", function()
		test_bufnr = create_test_buffer({ "some content" }, "/path/to/file.lua", "lua")
		test_winid = create_test_window(test_bufnr)

		package.loaded["codediff.ui.lifecycle"] = nil

		local ctx = codediff.get_context(test_winid)
		assert.is_nil(ctx)
	end)

	it("returns nil when there is no session", function()
		test_bufnr = create_test_buffer({ "some content" }, "/path/to/file.lua", "lua")
		test_winid = create_test_window(test_bufnr)

		mock_codediff_lifecycle(nil)

		local ctx = codediff.get_context(test_winid)
		assert.is_nil(ctx)
	end)

	it("returns nil when buffer is not in session", function()
		test_bufnr = create_test_buffer({ "some content" }, "/path/to/file.lua", "lua")
		test_winid = create_test_window(test_bufnr)

		mock_codediff_lifecycle({
			original_bufnr = 99998,
			modified_bufnr = 99999,
		})

		local ctx = codediff.get_context(test_winid)
		assert.is_nil(ctx)
	end)

	it("returns hunk context with modified_path when in original buffer", function()
		test_bufnr = create_test_buffer({ "original content" }, "/path/to/original.lua", "lua")
		test_winid = create_test_window(test_bufnr)

		mock_codediff_lifecycle({
			original_bufnr = test_bufnr,
			modified_bufnr = 99999,
			modified_path = "lua/modified.lua",
			original_path = "lua/original.lua",
		})

		local ctx = codediff.get_context(test_winid)
		assert.is_not_nil(ctx)
		assert.equals("hunk", ctx.type)
		assert.equals("lua/modified.lua", ctx.path)
	end)

	it("returns hunk context with modified_path when in modified buffer", function()
		test_bufnr = create_test_buffer({ "modified content" }, "/path/to/modified.lua", "lua")
		test_winid = create_test_window(test_bufnr)

		mock_codediff_lifecycle({
			original_bufnr = 99999,
			modified_bufnr = test_bufnr,
			modified_path = "lua/modified.lua",
			original_path = "lua/original.lua",
		})

		local ctx = codediff.get_context(test_winid)
		assert.is_not_nil(ctx)
		assert.equals("hunk", ctx.type)
		assert.equals("lua/modified.lua", ctx.path)
	end)

	it("falls back to original_path when modified_path is empty", function()
		test_bufnr = create_test_buffer({ "content" }, "/path/to/file.lua", "lua")
		test_winid = create_test_window(test_bufnr)

		mock_codediff_lifecycle({
			original_bufnr = test_bufnr,
			modified_bufnr = 99999,
			modified_path = "",
			original_path = "lua/original.lua",
		})

		local ctx = codediff.get_context(test_winid)
		assert.is_not_nil(ctx)
		assert.equals("hunk", ctx.type)
		assert.equals("lua/original.lua", ctx.path)
	end)

	it("falls back to original_path when modified_path is nil", function()
		test_bufnr = create_test_buffer({ "content" }, "/path/to/file.lua", "lua")
		test_winid = create_test_window(test_bufnr)

		mock_codediff_lifecycle({
			original_bufnr = test_bufnr,
			modified_bufnr = 99999,
			modified_path = nil,
			original_path = "lua/original.lua",
		})

		local ctx = codediff.get_context(test_winid)
		assert.is_not_nil(ctx)
		assert.equals("hunk", ctx.type)
		assert.equals("lua/original.lua", ctx.path)
	end)
end)

-- ---------------------------------------------------------------------------
-- get_file_info_for_hunk() tests
-- ---------------------------------------------------------------------------

describe("briefing.context.codediff.get_file_info_for_hunk()", function()
	local test_bufnr
	local test_winid

	before_each(function()
		package.loaded["briefing.context.codediff"] = nil
		codediff = require("briefing.context.codediff")
		clear_codediff_mock()
	end)

	after_each(function()
		cleanup(test_bufnr, test_winid)
		package.loaded["briefing.context.codediff"] = nil
		clear_codediff_mock()
	end)

	it("returns nil when codediff module is not installed", function()
		test_bufnr = create_test_buffer({ "some content" }, "/path/to/file.lua", "lua")
		test_winid = create_test_window(test_bufnr)

		package.loaded["codediff.ui.lifecycle"] = nil

		local filename, file_line = codediff.get_file_info_for_hunk(test_winid)
		assert.is_nil(filename)
		assert.is_nil(file_line)
	end)

	it("returns nil when there is no session", function()
		test_bufnr = create_test_buffer({ "some content" }, "/path/to/file.lua", "lua")
		test_winid = create_test_window(test_bufnr)

		mock_codediff_lifecycle(nil)

		local filename, file_line = codediff.get_file_info_for_hunk(test_winid)
		assert.is_nil(filename)
		assert.is_nil(file_line)
	end)

	it("returns nil when buffer is not in session", function()
		test_bufnr = create_test_buffer({ "some content" }, "/path/to/file.lua", "lua")
		test_winid = create_test_window(test_bufnr)

		mock_codediff_lifecycle({
			original_bufnr = 99998,
			modified_bufnr = 99999,
		})

		local filename, file_line = codediff.get_file_info_for_hunk(test_winid)
		assert.is_nil(filename)
		assert.is_nil(file_line)
	end)

	it("returns modified_path and cursor line when in session", function()
		test_bufnr = create_test_buffer({
			"line 1",
			"line 2",
			"line 3",
		}, "/path/to/file.lua", "lua")
		test_winid = create_test_window(test_bufnr)
		vim.api.nvim_win_set_cursor(test_winid, { 2, 0 })

		mock_codediff_lifecycle({
			original_bufnr = 99999,
			modified_bufnr = test_bufnr,
			modified_path = "lua/file.lua",
			original_path = "lua/original.lua",
			stored_diff_result = nil,
		})

		local filename, file_line = codediff.get_file_info_for_hunk(test_winid)
		assert.equals("lua/file.lua", filename)
		assert.equals(2, file_line)
	end)

	it("returns file line from hunk when cursor is in a hunk", function()
		test_bufnr = create_test_buffer({
			"context line",
			"added line",
			"context line",
		}, "/path/to/file.lua", "lua")
		test_winid = create_test_window(test_bufnr)
		vim.api.nvim_win_set_cursor(test_winid, { 2, 0 })

		mock_codediff_lifecycle({
			original_bufnr = 99999,
			modified_bufnr = test_bufnr,
			modified_path = "lua/file.lua",
			original_path = "lua/original.lua",
			stored_diff_result = {
				changes = {
					{
						original = { start_line = 1, end_line = 2 },
						modified = { start_line = 1, end_line = 3 },
					},
				},
			},
		})

		local filename, file_line = codediff.get_file_info_for_hunk(test_winid)
		assert.equals("lua/file.lua", filename)
		assert.equals(2, file_line)
	end)

	it("returns nil when both paths are empty", function()
		test_bufnr = create_test_buffer({ "content" }, "/path/to/file.lua", "lua")
		test_winid = create_test_window(test_bufnr)

		mock_codediff_lifecycle({
			original_bufnr = test_bufnr,
			modified_bufnr = 99999,
			modified_path = "",
			original_path = "",
		})

		local filename, file_line = codediff.get_file_info_for_hunk(test_winid)
		assert.is_nil(filename)
		assert.is_nil(file_line)
	end)
end)

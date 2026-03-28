local fugitive = require("briefing.context.fugitive")

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

-- ---------------------------------------------------------------------------
-- is_git_diff() tests
-- ---------------------------------------------------------------------------

describe("briefing.context.fugitive.is_git_diff()", function()
	local test_bufnr
	local test_winid

	before_each(function()
		package.loaded["briefing.context.fugitive"] = nil
		fugitive = require("briefing.context.fugitive")
	end)

	after_each(function()
		cleanup(test_bufnr, test_winid)
		package.loaded["briefing.context.fugitive"] = nil
	end)

	it("returns true for git filetype buffers", function()
		test_bufnr = create_test_buffer({ "some diff content" }, "/tmp/git-diff-buffer", "git")
		test_winid = create_test_window(test_bufnr)

		assert.is_true(fugitive.is_git_diff(test_winid))
	end)

	it("returns false for non-git filetype buffers", function()
		test_bufnr = create_test_buffer({ "some content" }, "/path/to/file.lua", "lua")
		test_winid = create_test_window(test_bufnr)

		assert.is_false(fugitive.is_git_diff(test_winid))
	end)

	it("returns false for fugitive filetype buffers", function()
		test_bufnr = create_test_buffer({ "some content" }, "/path/to/repo/.git/index", "fugitive")
		test_winid = create_test_window(test_bufnr)

		assert.is_false(fugitive.is_git_diff(test_winid))
	end)
end)

-- ---------------------------------------------------------------------------
-- is_fugitive() tests
-- ---------------------------------------------------------------------------

describe("briefing.context.fugitive.is_fugitive()", function()
	local test_bufnr
	local test_winid

	before_each(function()
		package.loaded["briefing.context.fugitive"] = nil
		fugitive = require("briefing.context.fugitive")
	end)

	after_each(function()
		cleanup(test_bufnr, test_winid)
		package.loaded["briefing.context.fugitive"] = nil
	end)

	it("returns true for fugitive:// buffers", function()
		test_bufnr = create_test_buffer({ "some content" }, "fugitive:///path/to/repo//commit123/lua/file.lua")
		test_winid = create_test_window(test_bufnr)

		assert.is_true(fugitive.is_fugitive(test_winid))
	end)

	it("returns true for fugitive filetype summary buffers", function()
		test_bufnr = create_test_buffer({ "some content" }, "/path/to/repo/.git/index", "fugitive")
		test_winid = create_test_window(test_bufnr)

		assert.is_true(fugitive.is_fugitive(test_winid))
	end)

	it("returns false for regular buffers", function()
		test_bufnr = create_test_buffer({ "some content" }, "/path/to/file.lua", "lua")
		test_winid = create_test_window(test_bufnr)

		assert.is_false(fugitive.is_fugitive(test_winid))
	end)

	it("returns true for fugitive filetype even without index in name", function()
		-- Any fugitive filetype buffer is considered a fugitive summary buffer
		test_bufnr = create_test_buffer({ "some content" }, "/path/to/repo/.git/config", "fugitive")
		test_winid = create_test_window(test_bufnr)

		assert.is_true(fugitive.is_fugitive(test_winid))
	end)
end)

-- ---------------------------------------------------------------------------
-- get_filename() tests
-- ---------------------------------------------------------------------------

describe("briefing.context.fugitive.get_filename()", function()
	local test_bufnr
	local test_winid
	local orig_current_win

	before_each(function()
		package.loaded["briefing.context.fugitive"] = nil
		fugitive = require("briefing.context.fugitive")
		orig_current_win = vim.api.nvim_get_current_win
	end)

	after_each(function()
		cleanup(test_bufnr, test_winid)
		vim.api.nvim_get_current_win = orig_current_win
		package.loaded["briefing.context.fugitive"] = nil
	end)

	it("extracts filename from fugitive:// URL", function()
		test_bufnr = create_test_buffer({ "some content" }, "fugitive:///path/to/repo//commit123/lua/file.lua")
		test_winid = create_test_window(test_bufnr)

		local filename = fugitive.get_filename(test_winid)
		assert.equals("lua/file.lua", filename)
	end)

	it("returns nil for non-fugitive buffer", function()
		test_bufnr = create_test_buffer({ "some content" }, "/path/to/file.lua", "lua")
		test_winid = create_test_window(test_bufnr)

		local filename = fugitive.get_filename(test_winid)
		assert.is_nil(filename)
	end)
end)

-- ---------------------------------------------------------------------------
-- get_context() tests
-- ---------------------------------------------------------------------------

describe("briefing.context.fugitive.get_context()", function()
	local test_bufnr
	local test_winid

	before_each(function()
		package.loaded["briefing.context.fugitive"] = nil
		fugitive = require("briefing.context.fugitive")
	end)

	after_each(function()
		cleanup(test_bufnr, test_winid)
		package.loaded["briefing.context.fugitive"] = nil
	end)

	it("returns hunk context with path for fugitive:// buffers", function()
		test_bufnr = create_test_buffer({ "some content" }, "fugitive:///path/to/repo//commit123/lua/file.lua")
		test_winid = create_test_window(test_bufnr)

		local ctx = fugitive.get_context(test_winid)
		assert.is_not_nil(ctx)
		assert.equals("hunk", ctx.type)
		assert.equals("lua/file.lua", ctx.path)
	end)

	it("returns hunk context with path for diff lines in summary buffer", function()
		test_bufnr = create_test_buffer({
			"Unstaged changes:",
			"M lua/file.lua",
			" +added line",
			" -removed line",
		}, "/path/to/repo/.git/index", "fugitive")
		test_winid = create_test_window(test_bufnr)
		vim.api.nvim_win_set_cursor(test_winid, { 3, 0 }) -- On the + line

		local ctx = fugitive.get_context(test_winid)
		assert.is_not_nil(ctx)
		assert.equals("hunk", ctx.type)
		assert.equals("lua/file.lua", ctx.path)
	end)

	it("returns hunk context for diff lines without leading space", function()
		test_bufnr = create_test_buffer({
			"M lua/file.lua",
			"+added line", -- No leading space
		}, "/path/to/repo/.git/index", "fugitive")
		test_winid = create_test_window(test_bufnr)
		vim.api.nvim_win_set_cursor(test_winid, { 2, 0 }) -- On the + line

		local ctx = fugitive.get_context(test_winid)
		assert.is_not_nil(ctx)
		assert.equals("hunk", ctx.type)
		assert.equals("lua/file.lua", ctx.path)
	end)

	it("returns hunk context for removed lines without leading space", function()
		test_bufnr = create_test_buffer({
			"M lua/file.lua",
			"-removed line", -- No leading space
		}, "/path/to/repo/.git/index", "fugitive")
		test_winid = create_test_window(test_bufnr)
		vim.api.nvim_win_set_cursor(test_winid, { 2, 0 }) -- On the - line

		local ctx = fugitive.get_context(test_winid)
		assert.is_not_nil(ctx)
		assert.equals("hunk", ctx.type)
		assert.equals("lua/file.lua", ctx.path)
	end)

	it("returns hunk context for fugitive:// summary buffer with no-space diff lines", function()
		test_bufnr = create_test_buffer({
			"M lua/file.lua",
			"+added line", -- No leading space
		}, "fugitive:///path/to/repo/.git//", "fugitive")
		test_winid = create_test_window(test_bufnr)
		vim.api.nvim_win_set_cursor(test_winid, { 2, 0 }) -- On the + line

		local ctx = fugitive.get_context(test_winid)
		assert.is_not_nil(ctx)
		assert.equals("hunk", ctx.type)
		assert.equals("lua/file.lua", ctx.path)
	end)

	it("returns file context for filename lines in summary buffer", function()
		-- Mock expand('<cfile>') to return the filename
		local orig_expand = vim.fn.expand
		vim.fn.expand = function(what)
			if what == "<cfile>" then
				return "lua/file.lua"
			end
			return orig_expand(what)
		end

		test_bufnr = create_test_buffer({
			"Unstaged changes:",
			"M lua/file.lua",
		}, "/path/to/repo/.git/index", "fugitive")
		test_winid = create_test_window(test_bufnr)
		vim.api.nvim_win_set_cursor(test_winid, { 2, 0 }) -- On the filename line

		local ctx = fugitive.get_context(test_winid)

		vim.fn.expand = orig_expand -- Restore

		assert.is_not_nil(ctx)
		assert.equals("file", ctx.type)
		assert.equals("lua/file.lua", ctx.path)
	end)

	it("returns nil for regular buffers", function()
		test_bufnr = create_test_buffer({ "some content" }, "/path/to/file.lua", "lua")
		test_winid = create_test_window(test_bufnr)

		local ctx = fugitive.get_context(test_winid)
		assert.is_nil(ctx)
	end)
end)

-- ---------------------------------------------------------------------------
-- get_context() tests for git diff buffers (filetype=git)
-- ---------------------------------------------------------------------------

describe("briefing.context.fugitive.get_context() git diff buffers", function()
	local test_bufnr
	local test_winid

	before_each(function()
		package.loaded["briefing.context.fugitive"] = nil
		fugitive = require("briefing.context.fugitive")
	end)

	after_each(function()
		cleanup(test_bufnr, test_winid)
		package.loaded["briefing.context.fugitive"] = nil
	end)

	it("returns hunk context when cursor is on a diff line in git buffer", function()
		test_bufnr = create_test_buffer({
			"diff --git a/lua/file.lua b/lua/file.lua",
			"index abc123..def456 100644",
			"--- a/lua/file.lua",
			"+++ b/lua/file.lua",
			"@@ -1,3 +1,3 @@",
			" context line",
			"-removed line",
			"+added line",
			" context line",
		}, "/tmp/git-diff", "git")
		test_winid = create_test_window(test_bufnr)
		vim.api.nvim_win_set_cursor(test_winid, { 8, 0 }) -- On "+added line"

		local ctx = fugitive.get_context(test_winid)
		assert.is_not_nil(ctx)
		assert.equals("hunk", ctx.type)
		assert.equals("lua/file.lua", ctx.path)
	end)

	it("returns hunk context when cursor is on a removed line", function()
		test_bufnr = create_test_buffer({
			"diff --git a/lua/file.lua b/lua/file.lua",
			"--- a/lua/file.lua",
			"+++ b/lua/file.lua",
			"@@ -1,3 +1,3 @@",
			" context line",
			"-removed line",
			"+added line",
		}, "/tmp/git-diff", "git")
		test_winid = create_test_window(test_bufnr)
		vim.api.nvim_win_set_cursor(test_winid, { 6, 0 }) -- On "-removed line"

		local ctx = fugitive.get_context(test_winid)
		assert.is_not_nil(ctx)
		assert.equals("hunk", ctx.type)
		assert.equals("lua/file.lua", ctx.path)
	end)

	it("returns diff context when cursor is not on a hunk line", function()
		test_bufnr = create_test_buffer({
			"diff --git a/lua/file.lua b/lua/file.lua",
			"--- a/lua/file.lua",
			"+++ b/lua/file.lua",
			"@@ -1,3 +1,3 @@",
			" context line",
		}, "/tmp/git-diff", "git")
		test_winid = create_test_window(test_bufnr)
		vim.api.nvim_win_set_cursor(test_winid, { 1, 0 }) -- On "diff --git" line

		local ctx = fugitive.get_context(test_winid)
		assert.is_not_nil(ctx)
		assert.equals("diff", ctx.type)
		assert.equals("lua/file.lua", ctx.path)
	end)

	it("returns hunk context without path when filename cannot be determined", function()
		test_bufnr = create_test_buffer({
			"@@ -1,3 +1,3 @@",
			" context line",
			"+added line",
		}, "/tmp/git-diff", "git")
		test_winid = create_test_window(test_bufnr)
		vim.api.nvim_win_set_cursor(test_winid, { 3, 0 }) -- On "+added line"

		local ctx = fugitive.get_context(test_winid)
		assert.is_not_nil(ctx)
		assert.equals("hunk", ctx.type)
		assert.is_nil(ctx.path)
	end)

	it("returns diff context without path when filename cannot be determined", function()
		test_bufnr = create_test_buffer({
			"@@ -1,3 +1,3 @@",
			" context line",
		}, "/tmp/git-diff", "git")
		test_winid = create_test_window(test_bufnr)
		vim.api.nvim_win_set_cursor(test_winid, { 1, 0 }) -- On header line

		local ctx = fugitive.get_context(test_winid)
		assert.is_not_nil(ctx)
		assert.equals("diff", ctx.type)
		assert.is_nil(ctx.path)
	end)
end)

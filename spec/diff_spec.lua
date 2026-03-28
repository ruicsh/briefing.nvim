local diff_resolver = require("briefing.context.diff")

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function create_test_buffer(lines, filename)
	local bufnr = vim.api.nvim_create_buf(false, true)
	if filename then
		vim.api.nvim_buf_set_name(bufnr, filename)
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
-- Mock git command helper
-- ---------------------------------------------------------------------------

local orig_system
local mock_git_output = nil
local mock_git_code = 0

local function setup_mock_git()
	orig_system = vim.system
	vim.system = function(args, opts)
		return {
			wait = function()
				return {
					code = mock_git_code,
					stdout = mock_git_output or "",
					stderr = "",
				}
			end,
		}
	end
end

local function teardown_mock_git()
	vim.system = orig_system
	mock_git_output = nil
	mock_git_code = 0
end

-- ---------------------------------------------------------------------------
-- #diff:hunk tests
-- ---------------------------------------------------------------------------

describe("briefing.context.diff.resolve() #diff:hunk", function()
	local test_bufnr
	local test_winid
	local orig_notify
	local notifications = {}

	before_each(function()
		package.loaded["briefing.context.diff"] = nil
		diff_resolver = require("briefing.context.diff")
		test_bufnr = create_test_buffer({ "line1", "line2", "line3" }, "/tmp/briefing_diff_test.lua")
		test_winid = create_test_window(test_bufnr)
		vim.api.nvim_set_current_win(test_winid)
		orig_notify = vim.notify
		notifications = {}
		vim.notify = function(msg, level)
			table.insert(notifications, { msg = msg, level = level })
		end
		setup_mock_git()
	end)

	after_each(function()
		cleanup(test_bufnr, test_winid)
		vim.notify = orig_notify
		teardown_mock_git()
		package.loaded["briefing.context.diff"] = nil
	end)

	it("returns empty string for buffer with no filename", function()
		local unnamed_buf = create_test_buffer({ "line1" })
		local unnamed_win = create_test_window(unnamed_buf)
		vim.api.nvim_set_current_win(unnamed_win)

		local result = diff_resolver.resolve("hunk", unnamed_win)

		cleanup(unnamed_buf, unnamed_win)

		assert.equals("", result)
		assert.equals(1, #notifications)
		assert.is_true(notifications[1].msg:find("buffer has no filename") ~= nil)
		assert.equals(vim.log.levels.WARN, notifications[1].level)
	end)

	it("returns empty string and warns when git diff fails", function()
		mock_git_code = 128
		mock_git_output = "fatal: not a git repo"

		local result = diff_resolver.resolve("hunk", test_winid)

		assert.equals("", result)
		assert.is_true(#notifications > 0)
		assert.is_true(notifications[#notifications].msg:find("git diff failed") ~= nil)
	end)

	it("returns empty string when no changes found", function()
		mock_git_output = ""

		local result = diff_resolver.resolve("hunk", test_winid)

		assert.equals("", result)
		assert.equals(1, #notifications)
		assert.is_true(notifications[1].msg:find("no changes found") ~= nil)
	end)

	it("returns wrapped diff when cursor is in a hunk", function()
		mock_git_output = [[diff --git a/file.lua b/file.lua
--- a/file.lua
+++ b/file.lua
@@ -1,3 +1,3 @@
 line1
-line2
+line2_modified
 line3
]]
		vim.api.nvim_win_set_cursor(test_winid, { 2, 0 }) -- Cursor on line 2

		local result = diff_resolver.resolve("hunk", test_winid)

		assert.is_true(result:find("```diff") ~= nil)
		assert.is_true(result:find("line2_modified") ~= nil)
	end)

	it("warns when cursor is not in any hunk", function()
		local large_bufnr =
			create_test_buffer({ "line1", "line2", "line3", "line4", "line5" }, "/tmp/briefing_diff_test2.lua")
		local large_winid = create_test_window(large_bufnr)
		vim.api.nvim_set_current_win(large_winid)

		mock_git_output = [[diff --git a/file.lua b/file.lua
--- a/file.lua
+++ b/file.lua
@@ -1,3 +1,3 @@
 line1
-line2
+line2_modified
 line3
]]
		vim.api.nvim_win_set_cursor(large_winid, { 5, 0 }) -- Cursor on line 5 (outside hunk 1-3)

		local result = diff_resolver.resolve("hunk", large_winid)

		cleanup(large_bufnr, large_winid)

		assert.equals("", result)
		assert.is_true(#notifications > 0)
		assert.is_true(notifications[#notifications].msg:find("cursor not in any hunk") ~= nil)
	end)
end)

-- ---------------------------------------------------------------------------
-- #diff:<filename> tests
-- ---------------------------------------------------------------------------

describe("briefing.context.diff.resolve() #diff:<filename>", function()
	local orig_notify
	local notifications = {}

	before_each(function()
		package.loaded["briefing.context.diff"] = nil
		diff_resolver = require("briefing.context.diff")
		orig_notify = vim.notify
		notifications = {}
		vim.notify = function(msg, level)
			table.insert(notifications, { msg = msg, level = level })
		end
		setup_mock_git()
	end)

	after_each(function()
		vim.notify = orig_notify
		teardown_mock_git()
		package.loaded["briefing.context.diff"] = nil
	end)

	it("returns file diff for tracked file", function()
		mock_git_output = [[diff --git a/lua/file.lua b/lua/file.lua
--- a/lua/file.lua
+++ b/lua/file.lua
@@ -1,3 +1,3 @@
 line1
-line2
+line2_modified
 line3
]]

		local result = diff_resolver.resolve("lua/file.lua")

		assert.is_true(result:find("```diff") ~= nil)
		assert.is_true(result:find("line2_modified") ~= nil)
	end)

	it("handles untracked files", function()
		-- First call returns empty (untracked, no diff in index)
		local call_count = 0
		vim.system = function(args, opts)
			call_count = call_count + 1
			if call_count == 1 then
				-- unstaged diff - empty for untracked
				return {
					wait = function()
						return { code = 0, stdout = "", stderr = "" }
					end,
				}
			elseif call_count == 2 then
				-- staged diff - also empty
				return {
					wait = function()
						return { code = 0, stdout = "", stderr = "" }
					end,
				}
			else
				-- --no-index diff - full file as new
				return {
					wait = function()
						return {
							code = 0,
							stdout = [[diff --git /dev/null b/.gitignore
new file mode 100644
index 0000000..f1367a7
--- /dev/null
+++ b/.gitignore
@@ -0,0 +1,3 @@
+.spec/
+.nvim-dev/
+
]],
							stderr = "",
						}
					end,
				}
			end
		end

		local result = diff_resolver.resolve(".gitignore")

		assert.is_true(result:find("```diff") ~= nil)
		assert.is_true(result:find("new file mode") ~= nil or result:find("%+") ~= nil)
	end)

	it("returns empty string when git diff fails", function()
		mock_git_code = 128
		mock_git_output = "fatal: not a git repo"

		local result = diff_resolver.resolve("lua/file.lua")

		assert.equals("", result)
		assert.is_true(#notifications > 0)
		assert.is_true(notifications[#notifications].msg:find("git diff failed") ~= nil)
	end)
end)

-- ---------------------------------------------------------------------------
-- #diff:unstaged tests
-- ---------------------------------------------------------------------------

describe("briefing.context.diff.resolve() #diff:unstaged", function()
	local orig_notify
	local notifications = {}

	before_each(function()
		package.loaded["briefing.context.diff"] = nil
		diff_resolver = require("briefing.context.diff")
		orig_notify = vim.notify
		notifications = {}
		vim.notify = function(msg, level)
			table.insert(notifications, { msg = msg, level = level })
		end
		setup_mock_git()
	end)

	after_each(function()
		vim.notify = orig_notify
		teardown_mock_git()
		package.loaded["briefing.context.diff"] = nil
	end)

	it("returns all unstaged changes", function()
		mock_git_output = [[diff --git a/file1.lua b/file1.lua
--- a/file1.lua
+++ b/file1.lua
@@ -1 +1 @@
-old
+new

diff --git a/file2.lua b/file2.lua
--- a/file2.lua
+++ b/file2.lua
@@ -1 +1 @@
-old2
+new2
]]

		local result = diff_resolver.resolve("unstaged")

		assert.is_true(result:find("```diff") ~= nil)
		assert.is_true(result:find("file1.lua") ~= nil)
		assert.is_true(result:find("file2.lua") ~= nil)
	end)

	it("defaults to unstaged when suboption is nil", function()
		mock_git_output = "diff --git a/file.lua b/file.lua"

		local result = diff_resolver.resolve(nil)

		assert.is_true(result:find("```diff") ~= nil)
	end)

	it("warns when no unstaged changes", function()
		mock_git_output = ""

		local result = diff_resolver.resolve("unstaged")

		assert.equals("", result)
		assert.equals(1, #notifications)
		assert.is_true(notifications[1].msg:find("no unstaged changes") ~= nil)
	end)
end)

-- ---------------------------------------------------------------------------
-- #diff:staged tests
-- ---------------------------------------------------------------------------

describe("briefing.context.diff.resolve() #diff:staged", function()
	local orig_notify
	local notifications = {}

	before_each(function()
		package.loaded["briefing.context.diff"] = nil
		diff_resolver = require("briefing.context.diff")
		orig_notify = vim.notify
		notifications = {}
		vim.notify = function(msg, level)
			table.insert(notifications, { msg = msg, level = level })
		end
		setup_mock_git()
	end)

	after_each(function()
		vim.notify = orig_notify
		teardown_mock_git()
		package.loaded["briefing.context.diff"] = nil
	end)

	it("returns all staged changes", function()
		mock_git_output = [[diff --git a/file1.lua b/file1.lua
--- a/file1.lua
+++ b/file1.lua
@@ -1 +1 @@
-old
+new
]]

		local result = diff_resolver.resolve("staged")

		assert.is_true(result:find("```diff") ~= nil)
	end)

	it("warns when no staged changes", function()
		mock_git_output = ""

		local result = diff_resolver.resolve("staged")

		assert.equals("", result)
		assert.equals(1, #notifications)
		assert.is_true(notifications[1].msg:find("no staged changes") ~= nil)
	end)
end)

-- ---------------------------------------------------------------------------
-- #diff:<sha> tests
-- ---------------------------------------------------------------------------

describe("briefing.context.diff.resolve() #diff:<sha>", function()
	local orig_notify
	local notifications = {}

	before_each(function()
		package.loaded["briefing.context.diff"] = nil
		diff_resolver = require("briefing.context.diff")
		orig_notify = vim.notify
		notifications = {}
		vim.notify = function(msg, level)
			table.insert(notifications, { msg = msg, level = level })
		end
		setup_mock_git()
	end)

	after_each(function()
		vim.notify = orig_notify
		teardown_mock_git()
		package.loaded["briefing.context.diff"] = nil
	end)

	it("returns commit diff for SHA", function()
		mock_git_output = [[commit abc123
Author: Test User <test@example.com>
Date: Mon Jan 1 00:00:00 2024

    Test commit

diff --git a/file.lua b/file.lua
--- a/file.lua
+++ b/file.lua
@@ -1 +1 @@
-old
+new
]]

		local result = diff_resolver.resolve("abc123")

		assert.is_true(result:find("```diff") ~= nil)
		assert.is_true(result:find("Test commit") ~= nil)
	end)

	it("warns when git show fails", function()
		mock_git_code = 128
		mock_git_output = "fatal: bad object"

		local result = diff_resolver.resolve("invalidsha")

		assert.equals("", result)
		assert.is_true(#notifications > 0)
		assert.is_true(notifications[#notifications].msg:find("git show failed") ~= nil)
	end)
end)

local config = require("briefing.config")

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function reset()
	config.setup()
	package.loaded["briefing.context"] = nil
	package.loaded["briefing.context.selection"] = nil
	package.loaded["briefing.context.diagnostics"] = nil
	package.loaded["briefing.context.diff"] = nil
	package.loaded["briefing.context.file"] = nil
	package.loaded["briefing.context.quickfix"] = nil
	vim.t.briefing_prev_vis_anchor = nil
	vim.t.briefing_prev_vis_cursor = nil
end

-- ---------------------------------------------------------------------------
-- context/init.lua — resolve() delegation for new tokens
-- ---------------------------------------------------------------------------

describe("briefing.context.resolve() new tokens", function()
	local context

	before_each(function()
		reset()
		context = require("briefing.context")
	end)
	after_each(reset)

	it("delegates #selection to selection.resolve()", function()
		local called = false
		package.loaded["briefing.context.selection"] = {
			resolve = function()
				called = true
				return "sel"
			end,
		}
		context = require("briefing.context")
		local token = { type = "context", name = "selection", suboption = nil, raw = "#selection" }
		local result = context.resolve(token, nil)
		assert.equals("sel", result)
		assert.is_true(called)
	end)

	it("delegates #diagnostics to diagnostics.resolve()", function()
		local called_sub = nil
		package.loaded["briefing.context.diagnostics"] = {
			resolve = function(sub)
				called_sub = sub
				return "diags"
			end,
		}
		context = require("briefing.context")
		local token = { type = "context", name = "diagnostics", suboption = "all", raw = "#diagnostics:all" }
		local result = context.resolve(token, nil)
		assert.equals("diags", result)
		assert.equals("all", called_sub)
	end)

	it("delegates #diff to diff.resolve()", function()
		local called_sub = nil
		package.loaded["briefing.context.diff"] = {
			resolve = function(sub)
				called_sub = sub
				return "diffout"
			end,
		}
		context = require("briefing.context")
		local token = { type = "context", name = "diff", suboption = "staged", raw = "#diff:staged" }
		local result = context.resolve(token, nil)
		assert.equals("diffout", result)
		assert.equals("staged", called_sub)
	end)

	it("delegates #file to file.resolve()", function()
		local called_path = nil
		package.loaded["briefing.context.file"] = {
			resolve = function(path)
				called_path = path
				return "filecontent"
			end,
		}
		context = require("briefing.context")
		local token = { type = "context", name = "file", suboption = "src/foo.lua", raw = "#file:src/foo.lua" }
		local result = context.resolve(token, nil)
		assert.equals("filecontent", result)
		assert.equals("src/foo.lua", called_path)
	end)

	it("delegates #quickfix to quickfix.resolve()", function()
		local called = false
		package.loaded["briefing.context.quickfix"] = {
			resolve = function()
				called = true
				return "qfout"
			end,
		}
		context = require("briefing.context")
		local token = { type = "context", name = "quickfix", suboption = nil, raw = "#quickfix" }
		local result = context.resolve(token, nil)
		assert.equals("qfout", result)
		assert.is_true(called)
	end)
end)

-- ---------------------------------------------------------------------------
-- context/selection.lua
-- ---------------------------------------------------------------------------

describe("briefing.context.selection.resolve()", function()
	local selection_resolver
	local test_bufnr
	local test_winid

	before_each(function()
		package.loaded["briefing.context.selection"] = nil
		selection_resolver = require("briefing.context.selection")

		-- Create a scratch buffer with known content
		test_bufnr = vim.api.nvim_create_buf(false, true)
		vim.bo[test_bufnr].filetype = "lua"
		vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
			"local a = 1",
			"local b = 2",
			"local c = 3",
		})

		test_winid = vim.api.nvim_open_win(test_bufnr, false, {
			relative = "editor",
			width = 20,
			height = 3,
			col = 0,
			row = 0,
			style = "minimal",
		})

		vim.t.briefing_prev_vis_anchor = nil
		vim.t.briefing_prev_vis_cursor = nil
		vim.t.briefing_prev_filetype = "lua"
	end)

	after_each(function()
		if test_winid and vim.api.nvim_win_is_valid(test_winid) then
			vim.api.nvim_win_close(test_winid, true)
		end
		if test_bufnr and vim.api.nvim_buf_is_valid(test_bufnr) then
			vim.api.nvim_buf_delete(test_bufnr, { force = true })
		end
		-- Clear register z
		vim.fn.setreg("z", "")
		vim.t.briefing_prev_filetype = nil
		package.loaded["briefing.context.selection"] = nil
	end)

	it("returns empty string and warns when register z is empty", function()
		local notified_level = nil
		local orig = vim.notify
		vim.notify = function(_, level)
			notified_level = level
		end

		-- Clear register z
		vim.fn.setreg("z", "")

		local result = selection_resolver.resolve(test_winid)

		vim.notify = orig
		assert.equals("", result)
		assert.equals(vim.log.levels.WARN, notified_level)
	end)

	it("returns selected content wrapped in a fenced code block", function()
		-- Set register z with simulated selection content
		vim.fn.setreg("z", "local a = 1\nlocal b = 2")

		local result = selection_resolver.resolve(test_winid)
		assert.is_true(result:find("```lua") ~= nil)
		assert.is_true(result:find("local a = 1") ~= nil)
	end)

	it("includes the filetype in the fenced code block header", function()
		vim.fn.setreg("z", "local a = 1")

		local result = selection_resolver.resolve(test_winid)
		assert.is_true(result:find("```lua") ~= nil)
	end)

	it("strips trailing newline from yanked content", function()
		-- Yank adds a trailing newline, verify it's stripped
		vim.fn.setreg("z", "local a = 1\n")

		local result = selection_resolver.resolve(test_winid)
		-- Should have exactly one newline (between header and content) plus closing fence
		assert.is_true(result:find("```lua\nlocal a = 1\n```") ~= nil)
	end)

	it("handles multi-line selection", function()
		vim.fn.setreg("z", "line one\nline two\nline three")

		local result = selection_resolver.resolve(test_winid)
		assert.is_true(result:find("line one") ~= nil)
		assert.is_true(result:find("line two") ~= nil)
		assert.is_true(result:find("line three") ~= nil)
	end)
end)

-- ---------------------------------------------------------------------------
-- context/diagnostics.lua
-- ---------------------------------------------------------------------------

describe("briefing.context.diagnostics.resolve()", function()
	local diag_resolver
	local test_bufnr
	local test_winid

	before_each(function()
		package.loaded["briefing.context.diagnostics"] = nil
		diag_resolver = require("briefing.context.diagnostics")

		test_bufnr = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(test_bufnr, "/tmp/briefing_diag_test.lua")
		vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, { "local x = nil" })

		test_winid = vim.api.nvim_open_win(test_bufnr, false, {
			relative = "editor",
			width = 20,
			height = 1,
			col = 0,
			row = 0,
			style = "minimal",
		})

		-- Clear any pre-existing diagnostics on this buffer
		vim.diagnostic.reset(nil, test_bufnr)
	end)

	after_each(function()
		vim.diagnostic.reset(nil, test_bufnr)
		if test_winid and vim.api.nvim_win_is_valid(test_winid) then
			vim.api.nvim_win_close(test_winid, true)
		end
		if test_bufnr and vim.api.nvim_buf_is_valid(test_bufnr) then
			vim.api.nvim_buf_delete(test_bufnr, { force = true })
		end
		package.loaded["briefing.context.diagnostics"] = nil
	end)

	it("returns empty string and warns when no diagnostics in buffer", function()
		local notified_level = nil
		local orig = vim.notify
		vim.notify = function(_, level)
			notified_level = level
		end

		local result = diag_resolver.resolve(nil, test_winid)

		vim.notify = orig
		assert.equals("", result)
		assert.equals(vim.log.levels.WARN, notified_level)
	end)

	it("returns formatted diagnostics for the buffer", function()
		vim.diagnostic.set(vim.api.nvim_create_namespace("briefing_test"), test_bufnr, {
			{
				lnum = 0,
				col = 0,
				message = "test error",
				severity = vim.diagnostic.severity.ERROR,
			},
		})

		local result = diag_resolver.resolve(nil, test_winid)
		assert.is_true(result:find("ERROR") ~= nil)
		assert.is_true(result:find("test error") ~= nil)
	end)

	it("includes file path header", function()
		vim.diagnostic.set(vim.api.nvim_create_namespace("briefing_test2"), test_bufnr, {
			{ lnum = 0, col = 0, message = "err", severity = vim.diagnostic.severity.ERROR },
		})

		local result = diag_resolver.resolve("buffer", test_winid)
		assert.is_true(result:find("Diagnostics:") ~= nil)
	end)

	it("treats nil suboption the same as 'buffer'", function()
		vim.diagnostic.set(vim.api.nvim_create_namespace("briefing_test3"), test_bufnr, {
			{ lnum = 0, col = 0, message = "warn msg", severity = vim.diagnostic.severity.WARN },
		})
		local r_nil = diag_resolver.resolve(nil, test_winid)
		local r_buf = diag_resolver.resolve("buffer", test_winid)
		assert.equals(r_nil, r_buf)
	end)

	it("resolve(:all) returns empty string and warns when no diagnostics anywhere", function()
		-- Make sure there are no diagnostics at all
		vim.diagnostic.reset()

		local notified_level = nil
		local orig = vim.notify
		vim.notify = function(_, level)
			notified_level = level
		end

		local result = diag_resolver.resolve("all", test_winid)

		vim.notify = orig
		assert.equals("", result)
		assert.equals(vim.log.levels.WARN, notified_level)
	end)

	it("resolve(:all) returns 'workspace' header", function()
		vim.diagnostic.set(vim.api.nvim_create_namespace("briefing_test4"), test_bufnr, {
			{ lnum = 0, col = 0, message = "global err", severity = vim.diagnostic.severity.ERROR },
		})

		local result = diag_resolver.resolve("all", test_winid)
		assert.is_true(result:find("Diagnostics: workspace") ~= nil)
		assert.is_true(result:find("global err") ~= nil)
	end)
end)

-- ---------------------------------------------------------------------------
-- context/diff.lua
-- ---------------------------------------------------------------------------

describe("briefing.context.diff.resolve()", function()
	local diff_resolver
	local orig_system

	before_each(function()
		package.loaded["briefing.context.diff"] = nil
		diff_resolver = require("briefing.context.diff")
		orig_system = vim.system
	end)

	after_each(function()
		vim.system = orig_system
		package.loaded["briefing.context.diff"] = nil
	end)

	local function stub_system(stdout, code, stderr)
		vim.system = function()
			return {
				wait = function()
					return { code = code, stdout = stdout, stderr = stderr or "" }
				end,
			}
		end
	end

	it("resolve(nil) returns buffer diff wrapped in a diff block", function()
		local bufnr = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(bufnr, vim.fn.getcwd() .. "/test.lua")
		local winid = vim.api.nvim_open_win(bufnr, false, {
			relative = "editor",
			width = 10,
			height = 10,
			col = 0,
			row = 0,
			style = "minimal",
		})
		stub_system("buffer diff content\n", 0)
		local result = diff_resolver.resolve(nil, winid)
		vim.api.nvim_win_close(winid, true)
		vim.api.nvim_buf_delete(bufnr, { force = true })
		assert.is_true(result:find("```diff") ~= nil)
		assert.is_true(result:find("buffer diff content") ~= nil)
	end)

	it("resolve('buffer') behaves the same as resolve(nil)", function()
		local bufnr = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(bufnr, vim.fn.getcwd() .. "/test.lua")
		local winid = vim.api.nvim_open_win(bufnr, false, {
			relative = "editor",
			width = 10,
			height = 10,
			col = 0,
			row = 0,
			style = "minimal",
		})
		stub_system("buffer diff\n", 0)
		local r_nil = diff_resolver.resolve(nil, winid)
		stub_system("buffer diff\n", 0)
		local r_buf = diff_resolver.resolve("buffer", winid)
		vim.api.nvim_win_close(winid, true)
		vim.api.nvim_buf_delete(bufnr, { force = true })
		assert.equals(r_nil, r_buf)
	end)

	it("resolve('staged') returns staged diff wrapped in a diff block", function()
		stub_system("staged diff\n", 0)
		local result = diff_resolver.resolve("staged")
		assert.is_true(result:find("```diff") ~= nil)
		assert.is_true(result:find("staged diff") ~= nil)
	end)

	it("resolve('abc1234') returns sha diff wrapped in a diff block", function()
		stub_system("commit diff\n", 0)
		local result = diff_resolver.resolve("abc1234")
		assert.is_true(result:find("```diff") ~= nil)
		assert.is_true(result:find("commit diff") ~= nil)
	end)

	it("returns empty string and warns when git exits non-zero", function()
		stub_system(nil, 128, "fatal: not a git repo\n")

		local notified_level = nil
		local orig = vim.notify
		vim.notify = function(_, level)
			notified_level = level
		end

		local result = diff_resolver.resolve(nil)

		vim.notify = orig
		assert.equals("", result)
		assert.equals(vim.log.levels.WARN, notified_level)
	end)

	it("returns empty string and warns when there are no changes", function()
		stub_system("", 0)

		local notified_level = nil
		local orig = vim.notify
		vim.notify = function(_, level)
			notified_level = level
		end

		local result = diff_resolver.resolve(nil)

		vim.notify = orig
		assert.equals("", result)
		assert.equals(vim.log.levels.WARN, notified_level)
	end)
end)

-- ---------------------------------------------------------------------------
-- context/file.lua
-- ---------------------------------------------------------------------------

describe("briefing.context.file.resolve()", function()
	local file_resolver
	local tmp_file

	before_each(function()
		package.loaded["briefing.context.file"] = nil
		file_resolver = require("briefing.context.file")

		-- Write a temp file with known content
		tmp_file = vim.fn.tempname() .. ".lua"
		vim.fn.writefile({ "local x = 1", "return x" }, tmp_file)
	end)

	after_each(function()
		vim.fn.delete(tmp_file)
		package.loaded["briefing.context.file"] = nil
	end)

	it("returns file content wrapped in a fenced code block", function()
		local result = file_resolver.resolve(tmp_file)
		assert.is_true(result:find("local x = 1") ~= nil)
		assert.is_true(result:find("return x") ~= nil)
		assert.is_true(result:find("```") ~= nil)
	end)

	it("includes File: header with line count", function()
		local result = file_resolver.resolve(tmp_file)
		assert.is_true(result:find("lines 1%-2") ~= nil)
	end)

	it("returns empty string and warns for a non-existent file", function()
		local notified_level = nil
		local orig = vim.notify
		vim.notify = function(_, level)
			notified_level = level
		end

		local result = file_resolver.resolve("/nonexistent/path/file.lua")

		vim.notify = orig
		assert.equals("", result)
		assert.equals(vim.log.levels.WARN, notified_level)
	end)

	it("returns empty string and warns when path is nil", function()
		local notified_level = nil
		local orig = vim.notify
		vim.notify = function(_, level)
			notified_level = level
		end

		local result = file_resolver.resolve(nil)

		vim.notify = orig
		assert.equals("", result)
		assert.equals(vim.log.levels.WARN, notified_level)
	end)

	it("returns empty string and warns when path is empty", function()
		local notified_level = nil
		local orig = vim.notify
		vim.notify = function(_, level)
			notified_level = level
		end

		local result = file_resolver.resolve("")

		vim.notify = orig
		assert.equals("", result)
		assert.equals(vim.log.levels.WARN, notified_level)
	end)
end)

-- ---------------------------------------------------------------------------
-- context/quickfix.lua
-- ---------------------------------------------------------------------------

describe("briefing.context.quickfix.resolve()", function()
	local qf_resolver

	before_each(function()
		package.loaded["briefing.context.quickfix"] = nil
		qf_resolver = require("briefing.context.quickfix")
		-- Clear the quickfix list
		vim.fn.setqflist({})
	end)

	after_each(function()
		vim.fn.setqflist({})
		package.loaded["briefing.context.quickfix"] = nil
	end)

	it("returns empty string and warns when quickfix list is empty", function()
		local notified_level = nil
		local orig = vim.notify
		vim.notify = function(_, level)
			notified_level = level
		end

		local result = qf_resolver.resolve()

		vim.notify = orig
		assert.equals("", result)
		assert.equals(vim.log.levels.WARN, notified_level)
	end)

	it("returns formatted quickfix items with item count header", function()
		vim.fn.setqflist({
			{ filename = "/tmp/foo.lua", lnum = 10, col = 5, text = "some error", type = "E" },
			{ filename = "/tmp/bar.lua", lnum = 20, col = 1, text = "another issue", type = "W" },
		})

		local result = qf_resolver.resolve()
		assert.is_true(result:find("Quickfix %(2 items%)") ~= nil)
		assert.is_true(result:find("some error") ~= nil)
		assert.is_true(result:find("another issue") ~= nil)
	end)

	it("includes line and column in each item", function()
		vim.fn.setqflist({
			{ filename = "/tmp/test.lua", lnum = 5, col = 3, text = "err msg", type = "E" },
		})

		local result = qf_resolver.resolve()
		assert.is_true(result:find(":5:3:") ~= nil)
	end)

	it("includes item type in output", function()
		vim.fn.setqflist({
			{ filename = "/tmp/test.lua", lnum = 1, col = 1, text = "warn", type = "W" },
		})

		local result = qf_resolver.resolve()
		assert.is_true(result:find("W:") ~= nil)
	end)
end)

-- ---------------------------------------------------------------------------
-- context/init.lua — preprocess_at_refs()
-- ---------------------------------------------------------------------------

describe("briefing.context.preprocess_at_refs()", function()
	local context

	before_each(function()
		reset()
		context = require("briefing.context")
	end)
	after_each(reset)

	it("converts @path/file.txt to #file:path/file.txt", function()
		local text = "Check @path/file.txt for details"
		local result = context.preprocess_at_refs(text)
		assert.equals("Check #file:path/file.txt for details", result)
	end)

	it("converts @./relative/path to #file:./relative/path", function()
		local text = "See @./local/config.lua"
		local result = context.preprocess_at_refs(text)
		assert.equals("See #file:./local/config.lua", result)
	end)

	it("converts @../parent/file to #file:../parent/file", function()
		local text = "Load @../shared/utils.lua"
		local result = context.preprocess_at_refs(text)
		assert.equals("Load #file:../shared/utils.lua", result)
	end)

	it("converts @file.txt to #file:file.txt", function()
		local text = "Edit @file.txt"
		local result = context.preprocess_at_refs(text)
		assert.equals("Edit #file:file.txt", result)
	end)

	it("does not convert @mention (no / or .)", function()
		local text = "Hey @user check this"
		local result = context.preprocess_at_refs(text)
		assert.equals("Hey @user check this", result)
	end)

	it("does not convert @ within a word", function()
		local text = "email@example.com"
		local result = context.preprocess_at_refs(text)
		assert.equals("email@example.com", result)
	end)

	it("handles multiple @ references", function()
		local text = "Compare @a.lua and @b.lua"
		local result = context.preprocess_at_refs(text)
		assert.equals("Compare #file:a.lua and #file:b.lua", result)
	end)

	it("handles @ at start of line", function()
		local text = "@src/main.ts is the entry"
		local result = context.preprocess_at_refs(text)
		assert.equals("#file:src/main.ts is the entry", result)
	end)

	it("handles @ at end of line", function()
		local text = "See @README.md"
		local result = context.preprocess_at_refs(text)
		assert.equals("See #file:README.md", result)
	end)

	it("does not convert @ followed by non-path characters", function()
		local text = "Error @ (check logs)"
		local result = context.preprocess_at_refs(text)
		assert.equals("Error @ (check logs)", result)
	end)

	it("converts @path-with-dashes/file", function()
		local text = "Open @my-folder/file.txt"
		local result = context.preprocess_at_refs(text)
		assert.equals("Open #file:my-folder/file.txt", result)
	end)

	it("converts @path_with_underscores/file", function()
		local text = "Load @my_folder/file.lua"
		local result = context.preprocess_at_refs(text)
		assert.equals("Load #file:my_folder/file.lua", result)
	end)

	it("handles empty string", function()
		local text = ""
		local result = context.preprocess_at_refs(text)
		assert.equals("", result)
	end)

	it("handles string with no @ references", function()
		local text = "Just plain text"
		local result = context.preprocess_at_refs(text)
		assert.equals("Just plain text", result)
	end)
end)

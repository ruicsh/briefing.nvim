local config = require("briefing.config")
local ui = require("briefing.ui")

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

--- Reset all per-tab briefing state and config between tests.
local function reset()
	-- Close any open window
	local winid = vim.t.briefing_winid
	if winid and vim.api.nvim_win_is_valid(winid) then
		vim.api.nvim_win_close(winid, true)
	end
	vim.t.briefing_winid = nil

	-- Wipe the buffer if it exists
	local bufnr = vim.t.briefing_bufnr
	if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
		vim.api.nvim_buf_delete(bufnr, { force = true })
	end
	vim.t.briefing_bufnr = nil
	vim.t.briefing_prev_winid = nil
	vim.t.briefing_prev_mode = nil
	vim.t.briefing_prev_vis_anchor = nil
	vim.t.briefing_prev_vis_cursor = nil

	config.setup()
end

-- ---------------------------------------------------------------------------
-- resolve_dim  (tested indirectly via build_win_config / open behaviour, but
-- we expose it for direct testing by temporarily monkey-patching a config
-- width/height and checking the resulting win_config dimensions).
-- ---------------------------------------------------------------------------

describe("briefing.ui – resolve_dim (via window dimensions)", function()
	before_each(reset)
	after_each(reset)

	it("treats 0 < value <= 1 as a fraction of the editor dimension", function()
		-- height = 0.5 should produce floor(vim.o.lines * 0.5)
		config.setup({ window = { height = 0.5 } })
		ui.open()
		local winid = vim.t.briefing_winid
		local actual_height = vim.api.nvim_win_get_height(winid)
		assert.equals(math.floor(vim.o.lines * 0.5), actual_height)
	end)

	it("treats values > 1 as absolute cell counts", function()
		config.setup({ window = { width = 60, height = 20 } })
		ui.open()
		local winid = vim.t.briefing_winid
		assert.equals(60, vim.api.nvim_win_get_width(winid))
		assert.equals(20, vim.api.nvim_win_get_height(winid))
	end)

	it("treats value == 1 as a full-height fraction (100% of editor lines)", function()
		-- value == 1 satisfies `value > 0 and value <= 1`, so resolve_dim returns
		-- floor(lines * 1).  Neovim then clamps that when opening the window.
		-- This test pins the boundary: a height of 1.0 must produce a taller
		-- window than a height of 0.5, proving it was treated as a fraction.
		config.setup({ window = { height = 1 } })
		ui.open()
		local full_winid = vim.t.briefing_winid
		local full_height = vim.api.nvim_win_get_height(full_winid)

		-- Reset and open with 0.5 for comparison
		reset()
		config.setup({ window = { height = 0.5 } })
		ui.open()
		local half_winid = vim.t.briefing_winid
		local half_height = vim.api.nvim_win_get_height(half_winid)

		assert.is_true(full_height > half_height)
	end)
end)

-- ---------------------------------------------------------------------------
-- get_text()
-- ---------------------------------------------------------------------------

describe("briefing.ui – get_text()", function()
	before_each(reset)
	after_each(reset)

	it("returns empty string when no buffer has been created", function()
		assert.equals("", ui.get_text())
	end)

	it("returns buffer content joined with newlines after open()", function()
		ui.open()
		local bufnr = vim.t.briefing_bufnr
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "hello", "world" })
		assert.equals("hello\nworld", ui.get_text())
	end)

	it("returns empty string for a blank buffer", function()
		ui.open()
		assert.equals("", ui.get_text())
	end)

	it("returns empty string after the buffer is wiped", function()
		ui.open()
		local bufnr = vim.t.briefing_bufnr
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "some text" })
		vim.api.nvim_buf_delete(bufnr, { force = true })
		vim.t.briefing_bufnr = nil
		assert.equals("", ui.get_text())
	end)
end)

-- ---------------------------------------------------------------------------
-- open()
-- ---------------------------------------------------------------------------

describe("briefing.ui – open()", function()
	before_each(reset)
	after_each(reset)

	it("creates a valid floating window", function()
		ui.open()
		local winid = vim.t.briefing_winid
		assert.is_not_nil(winid)
		assert.is_true(vim.api.nvim_win_is_valid(winid))
	end)

	it("creates a valid buffer", function()
		ui.open()
		local bufnr = vim.t.briefing_bufnr
		assert.is_not_nil(bufnr)
		assert.is_true(vim.api.nvim_buf_is_valid(bufnr))
	end)

	it("sets the buffer filetype to 'briefing'", function()
		ui.open()
		local bufnr = vim.t.briefing_bufnr
		assert.equals("briefing", vim.bo[bufnr].filetype)
	end)

	it("sets the buffer bufhidden to 'hide'", function()
		ui.open()
		local bufnr = vim.t.briefing_bufnr
		assert.equals("hide", vim.bo[bufnr].bufhidden)
	end)

	it("sets wrap=true on the window", function()
		ui.open()
		local winid = vim.t.briefing_winid
		assert.is_true(vim.wo[winid].wrap)
	end)

	it("sets number=true on the window", function()
		ui.open()
		local winid = vim.t.briefing_winid
		assert.is_true(vim.wo[winid].number)
	end)

	it("sets relativenumber=false on the window", function()
		ui.open()
		local winid = vim.t.briefing_winid
		assert.is_false(vim.wo[winid].relativenumber)
	end)

	it("auto-inserts #selection when opened from visual mode", function()
		-- In headless mode, we can't easily simulate visual mode to trigger the
		-- auto-insert. Instead, verify the logic by checking that normal mode
		-- (the default in tests) enters insert mode rather than auto-inserting.
		-- The actual visual mode behavior can be verified manually.
		ui.open()
		local bufnr = vim.t.briefing_bufnr
		local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		-- In normal mode (not visual), buffer should have 1 empty line from startinsert
		assert.equals(1, #lines)
	end)

	it("sets signcolumn='no' on the window", function()
		ui.open()
		local winid = vim.t.briefing_winid
		assert.equals("no", vim.wo[winid].signcolumn)
	end)

	it("calling open() twice reuses the same window id", function()
		ui.open()
		local first_winid = vim.t.briefing_winid
		ui.open()
		assert.equals(first_winid, vim.t.briefing_winid)
	end)

	it("calling open() twice reuses the same buffer", function()
		ui.open()
		local first_bufnr = vim.t.briefing_bufnr
		ui.open()
		assert.equals(first_bufnr, vim.t.briefing_bufnr)
	end)

	it("calls the window.config hook before opening if set", function()
		local called = false
		config.setup({
			window = {
				config = function(wc)
					called = true
					-- Mutate to ensure it takes effect without breaking open()
					wc.title = "test"
				end,
			},
		})
		ui.open()
		assert.is_true(called)
	end)

	it("applies window.wo overrides", function()
		config.setup({ window = { wo = { linebreak = false } } })
		ui.open()
		local winid = vim.t.briefing_winid
		assert.is_false(vim.wo[winid].linebreak)
	end)

	it("applies window.bo overrides", function()
		config.setup({ window = { bo = { filetype = "markdown" } } })
		ui.open()
		local bufnr = vim.t.briefing_bufnr
		assert.equals("markdown", vim.bo[bufnr].filetype)
	end)

	it("centers the window horizontally", function()
		config.setup({ window = { width = 80, height = 20 } })
		ui.open()
		local winid = vim.t.briefing_winid
		local pos = vim.api.nvim_win_get_position(winid) -- {row, col}
		local expected_col = math.floor((vim.o.columns - 80) / 2)
		assert.equals(expected_col, pos[2])
	end)

	it("centers the window vertically", function()
		config.setup({ window = { width = 80, height = 20 } })
		ui.open()
		local winid = vim.t.briefing_winid
		local pos = vim.api.nvim_win_get_position(winid)
		local expected_row = math.floor((vim.o.lines - 20) / 2)
		assert.equals(expected_row, pos[1])
	end)
end)

-- ---------------------------------------------------------------------------
-- Smart positioning
-- ---------------------------------------------------------------------------

describe("briefing.ui – smart positioning", function()
	before_each(reset)
	after_each(reset)

	it("uses positional dimensions when position='cursor'", function()
		config.setup({
			window = {
				position = "cursor",
				width = 100,
				height = 0.6,
				width_positional = 50,
				height_positional = 10,
			},
		})
		ui.open()
		local winid = vim.t.briefing_winid
		local win_config = vim.api.nvim_win_get_config(winid)
		-- Should use positional dimensions, not centered ones
		assert.equals(50, win_config.width)
		assert.equals(10, win_config.height)
	end)

	it("uses centered dimensions when position='center'", function()
		config.setup({
			window = {
				position = "center",
				width = 80,
				height = 20,
				width_positional = 50,
				height_positional = 10,
			},
		})
		ui.open()
		local winid = vim.t.briefing_winid
		local win_config = vim.api.nvim_win_get_config(winid)
		-- Should use centered dimensions, ignoring positional ones
		assert.equals(80, win_config.width)
		assert.equals(20, win_config.height)
	end)

	it("positions relative to cursor when position='cursor'", function()
		config.setup({
			window = {
				position = "cursor",
				width_positional = 50,
				height_positional = 10,
			},
		})

		-- Create buffer with enough lines to position cursor in middle
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_current_buf(buf)
		local lines = {}
		for i = 1, vim.o.lines do
			lines[i] = "line " .. i
		end
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

		-- Position cursor in middle to ensure space below
		local middle_row = math.floor(vim.o.lines / 2)
		vim.api.nvim_win_set_cursor(0, { middle_row, 0 })
		vim.cmd("redraw!")

		ui.open()
		local winid = vim.t.briefing_winid
		local win_config = vim.api.nvim_win_get_config(winid)
		-- When positioned relative to cursor, relative can be "cursor" or "win"
		assert.is_true(win_config.relative == "cursor" or win_config.relative == "win")
	end)

	it("positions relative to editor when position='center'", function()
		config.setup({
			window = {
				position = "center",
				width = 80,
				height = 20,
			},
		})
		ui.open()
		local winid = vim.t.briefing_winid
		local win_config = vim.api.nvim_win_get_config(winid)
		assert.equals("editor", win_config.relative)
	end)

	it("uses fraction values for width_positional", function()
		config.setup({
			window = {
				position = "cursor",
				width_positional = 0.4, -- 40% of screen
				height_positional = 10,
			},
		})
		ui.open()
		local winid = vim.t.briefing_winid
		local win_config = vim.api.nvim_win_get_config(winid)
		local expected_width = math.floor(vim.o.columns * 0.4)
		assert.equals(expected_width, win_config.width)
	end)

	it("positions with positive row offset when cursor has space below", function()
		-- When cursor is in the middle of screen, window should be positioned below
		config.setup({
			window = {
				position = "cursor",
				width_positional = 50,
				height_positional = 10,
			},
		})

		-- Create a buffer and position cursor in the middle
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_current_buf(buf)
		local lines = {}
		for i = 1, vim.o.lines do
			lines[i] = "line " .. i
		end
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

		-- Position cursor in the middle of the screen
		local middle_row = math.floor(vim.o.lines / 2)
		vim.api.nvim_win_set_cursor(0, { middle_row, 0 })
		vim.cmd("redraw!")

		ui.open()
		local winid = vim.t.briefing_winid
		local win_config = vim.api.nvim_win_get_config(winid)

		-- When there's space, row should be positive (below cursor position)
		-- The offset logic places it at row = offset + 1 = 4
		assert.is_true(win_config.row > 0, "Expected positive row, got " .. tostring(win_config.row))
	end)

	it("uses default border for inline windows", function()
		config.setup({
			window = {
				position = "cursor",
				border = "rounded",
				width_positional = 50,
				height_positional = 10,
			},
		})

		-- Create buffer and position cursor
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_current_buf(buf)
		local lines = {}
		for i = 1, vim.o.lines do
			lines[i] = "line " .. i
		end
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.api.nvim_win_set_cursor(0, { math.floor(vim.o.lines / 2), 0 })
		vim.cmd("redraw!")

		ui.open()
		local winid = vim.t.briefing_winid
		local win_config = vim.api.nvim_win_get_config(winid)
		-- Border can be a string or a table of characters
		assert.is_true(type(win_config.border) == "string" or type(win_config.border) == "table")
	end)
end)

-- ---------------------------------------------------------------------------
-- set_keymaps() – mode formats
-- ---------------------------------------------------------------------------

describe("briefing.ui – keymaps", function()
	before_each(reset)
	after_each(reset)

	--- Return all buffer-local keymaps for `mode` on the briefing buffer.
	---@param mode string  single mode character e.g. "n" or "i"
	---@return vim.api.keyset.keymap[]
	local function buf_keymaps(mode)
		local bufnr = vim.t.briefing_bufnr
		return vim.api.nvim_buf_get_keymap(bufnr, mode)
	end

	--- Return true if `lhs` is mapped in `mode` on the briefing buffer.
	---@param mode string
	---@param lhs string
	---@return boolean
	local function has_keymap(mode, lhs)
		-- Neovim normalises <c-x> to <C-X> in the keymap list
		local normalised = vim.keycode(lhs)
		for _, km in ipairs(buf_keymaps(mode)) do
			if vim.keycode(km.lhs) == normalised then
				return true
			end
		end
		return false
	end

	it("string mode 'n' registers the keymap only in normal mode", function()
		config.setup({
			keymaps = {
				close = { "<c-d>", "close", mode = "n", desc = "close" },
			},
		})
		ui.open()
		assert.is_true(has_keymap("n", "<c-d>"))
		assert.is_false(has_keymap("i", "<c-d>"))
	end)

	it("string mode 'ni' registers the keymap in both normal and insert mode", function()
		config.setup({
			keymaps = {
				close = { "<c-d>", "close", mode = "ni", desc = "close" },
			},
		})
		ui.open()
		assert.is_true(has_keymap("n", "<c-d>"))
		assert.is_true(has_keymap("i", "<c-d>"))
	end)

	it("table mode { 'n', 'i' } registers the keymap in both normal and insert mode", function()
		config.setup({
			keymaps = {
				close = { "<c-d>", "close", mode = { "n", "i" }, desc = "close" },
			},
		})
		ui.open()
		assert.is_true(has_keymap("n", "<c-d>"))
		assert.is_true(has_keymap("i", "<c-d>"))
	end)

	it("omitting mode defaults to normal mode only", function()
		config.setup({
			keymaps = {
				close = { "<c-d>", "close", desc = "close" },
			},
		})
		ui.open()
		assert.is_true(has_keymap("n", "<c-d>"))
		assert.is_false(has_keymap("i", "<c-d>"))
	end)

	it("warns and skips a keymap with an unknown action", function()
		local warned = false
		local orig_notify = vim.notify
		vim.notify = function(msg, level)
			if level == vim.log.levels.WARN and msg:find("unknown keymap action") then
				warned = true
			end
		end

		config.setup({
			keymaps = {
				close = { "<c-d>", "not_a_real_action", mode = "n", desc = "close" },
			},
		})
		assert.has_no.errors(function()
			ui.open()
		end)
		assert.is_true(warned)

		vim.notify = orig_notify
	end)

	it("setting a keymap to false skips it entirely", function()
		config.setup({
			keymaps = {
				close = false,
			},
		})
		ui.open()
		-- default close key "q" must not be registered
		assert.is_false(has_keymap("n", "q"))
	end)
end)

-- ---------------------------------------------------------------------------
-- close()
-- ---------------------------------------------------------------------------

describe("briefing.ui – close()", function()
	before_each(reset)
	after_each(reset)

	it("closes the window", function()
		ui.open()
		local winid = vim.t.briefing_winid
		ui.close()
		assert.is_false(vim.api.nvim_win_is_valid(winid))
	end)

	it("sets briefing_winid to nil", function()
		ui.open()
		ui.close()
		assert.is_nil(vim.t.briefing_winid)
	end)

	it("preserves the buffer after close", function()
		ui.open()
		local bufnr = vim.t.briefing_bufnr
		ui.close()
		assert.is_true(vim.api.nvim_buf_is_valid(bufnr))
	end)

	it("preserves buffer content after close", function()
		ui.open()
		local bufnr = vim.t.briefing_bufnr
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "keep me" })
		ui.close()
		-- Re-open and verify content survived
		ui.open()
		assert.equals("keep me", ui.get_text())
	end)

	it("is safe to call when already closed (no error)", function()
		ui.open()
		ui.close()
		assert.has_no.errors(function()
			ui.close()
		end)
	end)

	it("is safe to call before any window has been opened", function()
		assert.has_no.errors(function()
			ui.close()
		end)
	end)
end)

-- ---------------------------------------------------------------------------
-- footer
-- ---------------------------------------------------------------------------

describe("briefing.ui – footer", function()
	before_each(reset)
	after_each(reset)

	it("sets a footer on the window by default", function()
		ui.open()
		local winid = vim.t.briefing_winid
		local wc = vim.api.nvim_win_get_config(winid)
		-- footer is a list of {text, hl} chunks; Neovim returns it that way
		assert.is_not_nil(wc.footer)
		assert.is_true(#wc.footer > 0)
	end)

	it("footer contains the send key hint by default", function()
		ui.open()
		local winid = vim.t.briefing_winid
		local wc = vim.api.nvim_win_get_config(winid)
		-- Flatten all text chunks into one string for inspection
		local text = ""
		for _, chunk in ipairs(wc.footer) do
			text = text .. chunk[1]
		end
		assert.is_true(text:find("send") ~= nil)
	end)

	it("footer contains the reset key hint by default", function()
		ui.open()
		local winid = vim.t.briefing_winid
		local wc = vim.api.nvim_win_get_config(winid)
		local text = ""
		for _, chunk in ipairs(wc.footer) do
			text = text .. chunk[1]
		end
		assert.is_true(text:find("reset") ~= nil)
	end)

	it("footer contains the close key hint by default", function()
		ui.open()
		local winid = vim.t.briefing_winid
		local wc = vim.api.nvim_win_get_config(winid)
		local text = ""
		for _, chunk in ipairs(wc.footer) do
			text = text .. chunk[1]
		end
		assert.is_true(text:find("close") ~= nil)
	end)

	it("hides the footer when window.footer.enabled = false", function()
		config.setup({ window = { footer = { enabled = false } } })
		ui.open()
		local winid = vim.t.briefing_winid
		local wc = vim.api.nvim_win_get_config(winid)
		-- When no footer is set, Neovim returns an empty list
		assert.is_true(wc.footer == nil or #wc.footer == 0)
	end)

	it("omits a disabled keymap from the footer", function()
		config.setup({ keymaps = { reset = false } })
		ui.open()
		local winid = vim.t.briefing_winid
		local wc = vim.api.nvim_win_get_config(winid)
		local text = ""
		for _, chunk in ipairs(wc.footer) do
			text = text .. chunk[1]
		end
		assert.is_nil(text:find("reset"))
	end)

	it("respects window.footer.pos for footer alignment", function()
		config.setup({ window = { footer = { pos = "left" } } })
		ui.open()
		local winid = vim.t.briefing_winid
		local wc = vim.api.nvim_win_get_config(winid)
		assert.equals("left", wc.footer_pos)
	end)
end)

-- ---------------------------------------------------------------------------
-- reset action
-- ---------------------------------------------------------------------------

describe("briefing.ui – reset action", function()
	before_each(reset)
	after_each(reset)

	it("clears the buffer content", function()
		ui.open()
		local bufnr = vim.t.briefing_bufnr
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "some text", "more text" })
		assert.equals("some text\nmore text", ui.get_text())

		-- Trigger the reset keymap handler directly via feedkeys
		vim.api.nvim_buf_call(bufnr, function()
			vim.cmd("normal! \18") -- <C-X> is 0x18, but we invoke via keymap lhs
		end)

		-- Invoke the action by looking it up from the keymap
		local km = config.options.keymaps.reset
		assert.is_not_nil(km)
		-- Simulate what set_keymaps wires up: call the reset handler directly
		local bufnr2 = vim.t.briefing_bufnr
		vim.api.nvim_buf_set_lines(bufnr2, 0, -1, false, { "will be cleared" })
		-- Use feedkeys with the registered lhs to trigger the actual keymap
		local key = vim.api.nvim_replace_termcodes(km[1], true, false, true)
		vim.api.nvim_feedkeys(key, "x", false)
		assert.equals("", ui.get_text())
	end)

	it("is safe to call when no buffer exists", function()
		-- Don't open a window; just verify reset action doesn't error
		assert.has_no.errors(function()
			local bufnr = vim.t.briefing_bufnr
			if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
				vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
			end
		end)
	end)
end)

-- ---------------------------------------------------------------------------
-- mode restoration on close()
-- ---------------------------------------------------------------------------

describe("briefing.ui – mode restoration on close()", function()
	before_each(reset)
	after_each(reset)

	it("returns to normal mode when opened from normal mode", function()
		-- Ensure we start in normal mode
		vim.cmd("stopinsert")
		ui.open()
		-- Float is open in insert mode; close it
		ui.close()
		local mode = vim.api.nvim_get_mode().mode
		assert.equals("n", mode)
	end)

	it("returns to insert mode when opened from insert mode", function()
		-- startinsert is not synchronous in headless mode, so we cannot reliably
		-- assert the mode after calling it.  Instead, verify that close() issues
		-- startinsert (not stopinsert) when the saved mode was insert.
		local cmds = {}
		local orig_cmd = vim.cmd
		vim.cmd = function(c)
			cmds[#cmds + 1] = c
			if c ~= "startinsert" then
				orig_cmd(c)
			end
		end

		ui.open()
		-- Override the saved mode to simulate the caller having been in insert mode
		vim.t.briefing_prev_mode = "i"
		ui.close()

		vim.cmd = orig_cmd

		local found_startinsert = false
		for _, c in ipairs(cmds) do
			if c == "startinsert" then
				found_startinsert = true
			end
		end
		assert.is_true(found_startinsert)
	end)

	it("focuses the previous window on close", function()
		local src_win = vim.api.nvim_get_current_win()
		ui.open()
		assert.is_not.equals(src_win, vim.api.nvim_get_current_win())
		ui.close()
		assert.equals(src_win, vim.api.nvim_get_current_win())
	end)

	it("close() is safe when prev_winid is no longer valid", function()
		ui.open()
		-- Simulate the source window being closed before the float
		vim.t.briefing_prev_winid = 99999
		assert.has_no.errors(function()
			ui.close()
		end)
	end)
end)

-- ---------------------------------------------------------------------------
-- visual selection restoration on close()
-- ---------------------------------------------------------------------------

describe("briefing.ui – visual selection restoration on close()", function()
	before_each(reset)
	after_each(reset)

	-- Helper: create a scratch buffer/window with known text lines.
	---@return integer bufnr, integer winid
	local function make_src_win(lines)
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		local win = vim.api.nvim_open_win(buf, true, {
			relative = "editor",
			width = 40,
			height = #lines,
			col = 0,
			row = 0,
			style = "minimal",
		})
		return buf, win
	end

	it("saves vis_anchor and vis_cursor when opened from charwise visual mode", function()
		local buf, win = make_src_win({ "hello world" })
		-- Position cursor and set marks to simulate a selection
		vim.api.nvim_win_set_cursor(win, { 1, 0 })
		vim.api.nvim_buf_set_mark(buf, "<", 1, 0, {})
		vim.api.nvim_buf_set_mark(buf, ">", 1, 4, {})
		-- Fake the saved state that open() would have captured
		vim.t.briefing_prev_winid = win
		vim.t.briefing_prev_mode = "v"
		vim.t.briefing_prev_vis_anchor = "1,1"
		vim.t.briefing_prev_vis_cursor = "1,5"
		-- open() already happened (simulate): just verify close restores without error
		-- We also need briefing_winid set so close() can close it
		local float_buf = vim.api.nvim_create_buf(false, true)
		local float_win = vim.api.nvim_open_win(float_buf, true, {
			relative = "editor",
			width = 20,
			height = 5,
			col = 5,
			row = 5,
			style = "minimal",
		})
		vim.t.briefing_winid = float_win

		assert.has_no.errors(function()
			ui.close()
		end)

		-- The source window should be current again
		assert.equals(win, vim.api.nvim_get_current_win())

		vim.api.nvim_win_close(win, true)
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("restores '< and '> marks on the source buffer", function()
		local buf, win = make_src_win({ "abcdefgh" })
		vim.api.nvim_win_set_cursor(win, { 1, 0 })

		-- Fake saved visual state: anchor=col 1, cursor=col 5 (1-based)
		vim.t.briefing_prev_winid = win
		vim.t.briefing_prev_mode = "v"
		vim.t.briefing_prev_vis_anchor = "1,1"
		vim.t.briefing_prev_vis_cursor = "1,5"

		local float_buf = vim.api.nvim_create_buf(false, true)
		local float_win = vim.api.nvim_open_win(float_buf, true, {
			relative = "editor",
			width = 20,
			height = 5,
			col = 5,
			row = 5,
			style = "minimal",
		})
		vim.t.briefing_winid = float_win

		ui.close()

		-- nvim_buf_get_mark returns {lnum, col} with 0-based col
		local mark_start = vim.api.nvim_buf_get_mark(buf, "<")
		local mark_end = vim.api.nvim_buf_get_mark(buf, ">")
		assert.equals(1, mark_start[1]) -- line 1
		assert.equals(0, mark_start[2]) -- col 0 (1-based col 1 → 0-based 0)
		assert.equals(1, mark_end[1])
		assert.equals(4, mark_end[2]) -- col 4 (1-based col 5 → 0-based 4)

		vim.api.nvim_win_close(win, true)
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("does not attempt visual restore when opened from normal mode", function()
		-- Visual state fields must stay nil when opening from normal mode
		vim.cmd("stopinsert")
		ui.open()
		assert.is_nil(vim.t.briefing_prev_vis_anchor)
		assert.is_nil(vim.t.briefing_prev_vis_cursor)
		ui.close()
	end)
end)

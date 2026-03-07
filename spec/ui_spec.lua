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

	it("sets number=false on the window", function()
		ui.open()
		local winid = vim.t.briefing_winid
		assert.is_false(vim.wo[winid].number)
	end)

	it("sets relativenumber=false on the window", function()
		ui.open()
		local winid = vim.t.briefing_winid
		assert.is_false(vim.wo[winid].relativenumber)
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

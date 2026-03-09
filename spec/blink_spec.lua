local blink

describe("blink.cmp integration", function()
	local function reset()
		-- Reset any global state if needed
		vim.bo.filetype = "briefing"

		-- Clear module cache to reload with fresh state
		package.loaded["briefing.integrations.blink"] = nil

		-- Mock blink.cmp types module
		package.loaded["blink.cmp.types"] = {
			CompletionItemKind = {
				Variable = 6,
				EnumMember = 20,
				File = 17,
				Folder = 19,
			},
		}

		-- Reload blink module
		blink = require("briefing.integrations.blink")
	end

	before_each(function()
		reset()
	end)

	after_each(function()
		reset()
	end)

	describe("new()", function()
		it("creates a new source instance", function()
			local source = blink.new()
			assert.is_not_nil(source)
			assert.are.equal(blink, getmetatable(source).__index)
		end)
	end)

	describe("get_trigger_characters()", function()
		it("returns # and : as trigger characters", function()
			local source = blink.new()
			local chars = source:get_trigger_characters()
			assert.are.same({ "#", ":" }, chars)
		end)
	end)

	describe("enabled()", function()
		it("returns true for briefing filetype", function()
			local source = blink.new()
			vim.bo.filetype = "briefing"
			assert.is_true(source:enabled())
		end)

		it("returns false for other filetypes", function()
			local source = blink.new()
			vim.bo.filetype = "lua"
			assert.is_false(source:enabled())
		end)
	end)

	describe("get_completions() - variable names", function()
		it("returns all variables when typing just #", function()
			local source = blink.new()
			local ctx = {
				line = "#",
				cursor = { 1, 1 }, -- row 1, col 1 (after #)
			}

			local called = false
			local result = nil

			source:get_completions(ctx, function(res)
				called = true
				result = res
			end)

			assert.is_true(called)
			assert.is_not_nil(result)
			assert.is_not_nil(result.items)
			assert.is_true(#result.items >= 6) -- At least 6 variables

			-- Check that we have expected variables
			local labels = {}
			for _, item in ipairs(result.items) do
				labels[item.label] = true
			end
			assert.is_true(labels["#buffer"])
			assert.is_true(labels["#selection"])
			assert.is_true(labels["#diagnostics"])
			assert.is_true(labels["#diff"])
			assert.is_true(labels["#file"])
			assert.is_true(labels["#quickfix"])
		end)

		it("filters variables when typing partial name", function()
			local source = blink.new()
			local ctx = {
				line = "#buf",
				cursor = { 1, 4 }, -- row 1, col 4 (after #buf)
			}

			local result = nil
			source:get_completions(ctx, function(res)
				result = res
			end)

			assert.is_not_nil(result)
			assert.are.equal(1, #result.items)
			assert.are.equal("#buffer", result.items[1].label)
		end)

		it("is case-insensitive when matching", function()
			local source = blink.new()
			local ctx = {
				line = "#BUF",
				cursor = { 1, 4 },
			}

			local result = nil
			source:get_completions(ctx, function(res)
				result = res
			end)

			assert.is_not_nil(result)
			assert.are.equal(1, #result.items)
			assert.are.equal("#buffer", result.items[1].label)
		end)

		it("includes descriptions in completion items", function()
			local source = blink.new()
			local ctx = {
				line = "#buffer",
				cursor = { 1, 7 },
			}

			local result = nil
			source:get_completions(ctx, function(res)
				result = res
			end)

			assert.is_not_nil(result)
			assert.are.equal(1, #result.items)
			assert.is_not_nil(result.items[1].detail)
			assert.is_true(#result.items[1].detail > 0)
		end)
	end)

	describe("get_completions() - suboptions", function()
		it("returns suboptions for buffer: (all, diff)", function()
			local source = blink.new()
			local ctx = {
				line = "#buffer:",
				cursor = { 1, 8 }, -- after #buffer:
			}

			local result = nil
			source:get_completions(ctx, function(res)
				result = res
			end)

			-- #buffer: now returns all and diff suboptions
			assert.is_not_nil(result)
			assert.are.equal(2, #result.items)

			local labels = {}
			for _, item in ipairs(result.items) do
				table.insert(labels, item.label)
			end
			assert.is_true(vim.tbl_contains(labels, "all"))
			assert.is_true(vim.tbl_contains(labels, "diff"))
		end)

		it("returns suboptions for diagnostics:", function()
			local source = blink.new()
			local ctx = {
				line = "#diagnostics:",
				cursor = { 1, 13 },
			}

			local result = nil
			source:get_completions(ctx, function(res)
				result = res
			end)

			assert.is_not_nil(result)
			assert.are.equal(2, #result.items)

			local labels = {}
			for _, item in ipairs(result.items) do
				labels[item.label] = true
			end
			assert.is_true(labels["buffer"])
			assert.is_true(labels["all"])
		end)

		it("returns suboptions for diff:", function()
			local source = blink.new()
			local ctx = {
				line = "#diff:",
				cursor = { 1, 6 },
			}

			local result = nil
			source:get_completions(ctx, function(res)
				result = res
			end)

			assert.is_not_nil(result)
			assert.are.equal(2, #result.items)

			local labels = {}
			for _, item in ipairs(result.items) do
				labels[item.label] = true
			end
			assert.is_true(labels["unstaged"])
			assert.is_true(labels["staged"])
		end)

		it("filters suboptions when typing partial for non-picker variables", function()
			local source = blink.new()
			local ctx = {
				line = "#diagnostics:bu",
				cursor = { 1, 15 },
			}

			local result = nil
			source:get_completions(ctx, function(res)
				result = res
			end)

			assert.is_not_nil(result)
			assert.are.equal(1, #result.items)
			assert.are.equal("buffer", result.items[1].label)
		end)

		it("returns empty for variables without suboptions", function()
			local source = blink.new()
			local ctx = {
				line = "#selection:",
				cursor = { 1, 11 },
			}

			local result = nil
			source:get_completions(ctx, function(res)
				result = res
			end)

			assert.is_not_nil(result)
			assert.are.equal(0, #result.items)
		end)
	end)

	describe("get_completions() - picker-deferred variables", function()
		it("defers to picker for #file: (returns empty)", function()
			local source = blink.new()
			local ctx = {
				line = "#file:",
				cursor = { 1, 6 },
			}

			local result = nil
			source:get_completions(ctx, function(res)
				result = res
			end)

			-- #file: should return empty so <Tab> falls through to picker
			assert.is_not_nil(result)
			assert.are.equal(0, #result.items)
		end)

		it("shows file completions when typing partial path", function()
			local source = blink.new()
			local ctx = {
				line = "#file:lu",
				cursor = { 1, 8 },
			}

			local result = nil
			source:get_completions(ctx, function(res)
				result = res
			end)

			-- #file: with partial path shows file completions
			assert.is_not_nil(result)
			assert.is_true(#result.items > 0)
		end)
	end)

	describe("setup()", function()
		it("returns a provider config table", function()
			local config = blink.setup()

			assert.are.equal("Briefing", config.name)
			assert.are.equal("briefing.integrations.blink", config.module)
			assert.are.equal(-10, config.score_offset)
			assert.is_function(config.enabled)
		end)

		it("allows customizing score_offset", function()
			local config = blink.setup({ score_offset = 5 })
			assert.are.equal(5, config.score_offset)
		end)

		it("enabled function returns true for briefing filetype", function()
			local config = blink.setup()
			vim.bo.filetype = "briefing"
			assert.is_true(config.enabled())
		end)

		it("enabled function returns false for other filetypes", function()
			local config = blink.setup()
			vim.bo.filetype = "lua"
			assert.is_false(config.enabled())
		end)
	end)
end)

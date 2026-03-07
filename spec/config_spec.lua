local config = require("briefing.config")

describe("briefing.config", function()
	-- Reset to defaults before each test so tests are fully isolated.
	before_each(function()
		config.setup()
	end)

	-- -----------------------------------------------------------------------
	-- Default values
	-- -----------------------------------------------------------------------

	describe("defaults", function()
		it("sets window.width to 100", function()
			assert.equals(100, config.options.window.width)
		end)

		it("sets window.height to 0.6", function()
			assert.equals(0.6, config.options.window.height)
		end)

		it("sets window.border to 'rounded'", function()
			assert.equals("rounded", config.options.window.border)
		end)

		it("sets window.title to ' Briefing '", function()
			assert.equals(" Briefing ", config.options.window.title)
		end)

		it("sets window.title_pos to 'center'", function()
			assert.equals("center", config.options.window.title_pos)
		end)

		it("sets window.config to nil", function()
			assert.is_nil(config.options.window.config)
		end)

		it("sets window.wo to an empty table", function()
			assert.same({}, config.options.window.wo)
		end)

		it("sets window.bo to an empty table", function()
			assert.same({}, config.options.window.bo)
		end)
	end)

	-- -----------------------------------------------------------------------
	-- Default keymaps
	-- -----------------------------------------------------------------------

	describe("default keymaps", function()
		it("defines a 'send' keymap", function()
			assert.is_not_nil(config.options.keymaps.send)
		end)

		it("binds send to <c-s>", function()
			assert.equals("<c-s>", config.options.keymaps.send[1])
		end)

		it("send keymap action is 'send'", function()
			assert.equals("send", config.options.keymaps.send[2])
		end)

		it("send keymap mode is 'ni'", function()
			assert.equals("ni", config.options.keymaps.send.mode)
		end)

		it("defines a 'close' keymap", function()
			assert.is_not_nil(config.options.keymaps.close)
		end)

		it("binds close to q", function()
			assert.equals("q", config.options.keymaps.close[1])
		end)

		it("close keymap action is 'close'", function()
			assert.equals("close", config.options.keymaps.close[2])
		end)

		it("close keymap mode is 'n'", function()
			assert.equals("n", config.options.keymaps.close.mode)
		end)
	end)

	-- -----------------------------------------------------------------------
	-- setup() merging behaviour
	-- -----------------------------------------------------------------------

	describe("setup()", function()
		it("overrides a single window option while preserving the rest", function()
			config.setup({ window = { width = 80 } })
			assert.equals(80, config.options.window.width)
			-- Other defaults must survive
			assert.equals(0.6, config.options.window.height)
			assert.equals("rounded", config.options.window.border)
			assert.equals(" Briefing ", config.options.window.title)
		end)

		it("overrides multiple window options at once", function()
			config.setup({ window = { width = 120, height = 0.8, border = "single" } })
			assert.equals(120, config.options.window.width)
			assert.equals(0.8, config.options.window.height)
			assert.equals("single", config.options.window.border)
		end)

		it("merges wo overrides without wiping other window keys", function()
			config.setup({ window = { wo = { wrap = false } } })
			assert.equals(false, config.options.window.wo.wrap)
			-- Top-level window key still present
			assert.equals(100, config.options.window.width)
		end)

		it("last call wins when called twice with conflicting values", function()
			config.setup({ window = { width = 50 } })
			config.setup({ window = { width = 90 } })
			assert.equals(90, config.options.window.width)
		end)

		it("accepts no arguments and restores defaults", function()
			config.setup({ window = { width = 999 } })
			config.setup()
			assert.equals(100, config.options.window.width)
		end)

		it("stores a window.config callback when provided", function()
			local cb = function() end
			config.setup({ window = { config = cb } })
			assert.equals(cb, config.options.window.config)
		end)

		it("can disable a keymap by setting it to false", function()
			config.setup({ keymaps = { close = false } })
			assert.equals(false, config.options.keymaps.close)
		end)

		it("preserves other keymaps when one is disabled", function()
			config.setup({ keymaps = { close = false } })
			assert.is_not_nil(config.options.keymaps.send)
			assert.equals("<c-s>", config.options.keymaps.send[1])
		end)

		it("can override a keymap lhs", function()
			config.setup({ keymaps = { send = { "<leader>s", "send", mode = "n" } } })
			assert.equals("<leader>s", config.options.keymaps.send[1])
		end)
	end)
end)

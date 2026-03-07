-- Tests for plugin/briefing.lua
-- We source the file directly rather than relying on Neovim's plugin loader so
-- that the double-load guard can be exercised in isolation.

local plugin_path = vim.fn.fnamemodify(
	debug.getinfo(1, "S").source:sub(2),
	":h:h" -- spec/ → repo root
) .. "/plugin/briefing.lua"

describe("plugin/briefing.lua", function()
	before_each(function()
		-- Start each test with a clean slate: remove the load guard and the
		-- command so that sourcing the file is always a fresh attempt.
		vim.g.loaded_briefing = nil
		pcall(vim.api.nvim_del_user_command, "Briefing")
	end)

	after_each(function()
		vim.g.loaded_briefing = nil
		pcall(vim.api.nvim_del_user_command, "Briefing")
	end)

	it("registers the :Briefing user command", function()
		vim.cmd("source " .. plugin_path)
		local cmds = vim.api.nvim_get_commands({})
		assert.is_not_nil(cmds["Briefing"])
	end)

	it(":Briefing command has the expected description", function()
		vim.cmd("source " .. plugin_path)
		local cmd = vim.api.nvim_get_commands({})["Briefing"]
		assert.equals("Open the Briefing prompt window", cmd.definition)
	end)

	it("sets vim.g.loaded_briefing after sourcing", function()
		vim.cmd("source " .. plugin_path)
		assert.is_truthy(vim.g.loaded_briefing)
	end)

	it("double-load guard prevents re-registering the command", function()
		vim.cmd("source " .. plugin_path)
		-- Remove the command manually to simulate a fresh state while keeping
		-- the guard flag, then re-source to verify the guard fires early.
		pcall(vim.api.nvim_del_user_command, "Briefing")
		vim.cmd("source " .. plugin_path)
		-- The command should NOT have been re-created because the guard returned early.
		local cmds = vim.api.nvim_get_commands({})
		assert.is_nil(cmds["Briefing"])
	end)
end)

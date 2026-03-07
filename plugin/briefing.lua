if vim.g.loaded_briefing then
	return
end
vim.g.loaded_briefing = true

vim.api.nvim_create_user_command("Briefing", function()
	require("briefing").open()
end, { desc = "Open the Briefing prompt window" })

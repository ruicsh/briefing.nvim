-- Minimal Neovim init for running busted tests via plenary.nvim.
-- Adds the plugin root and plenary to the runtimepath so that
-- require("briefing") and plenary helpers resolve correctly.

local plenary_path = os.getenv("PLENARY_PATH") or vim.fn.stdpath("data") .. "/site/pack/test/start/plenary.nvim"

vim.opt.runtimepath:prepend(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h"))
vim.opt.runtimepath:prepend(plenary_path)

-- Load plenary's busted helpers
require("plenary.busted")

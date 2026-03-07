local M = {}

---@class briefing.Config
local defaults = {
  window = {
    width = 80,
    height = 20,
    border = "rounded",
    title = " Briefing ",
  },
  keymaps = {
    send = "<c-s>",
    close = "q",
  },
}

---@type briefing.Config
M.options = {}

---@param opts? briefing.Config
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", defaults, opts or {})
end

-- Initialize with defaults
M.setup()

return M

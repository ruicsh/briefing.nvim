local M = {}

---@param opts? briefing.Config
function M.setup(opts)
  require("briefing.config").setup(opts)
end

--- Open (or focus) the briefing floating window.
function M.open()
  require("briefing.ui").open()
end

--- Close the briefing floating window (content persists).
function M.close()
  require("briefing.ui").close()
end

--- Send the current buffer contents to sidekick, then close the window.
function M.send()
  local text = require("briefing.ui").get_text()

  -- Strip leading/trailing whitespace
  text = text:match("^%s*(.-)%s*$")

  if text == "" then
    vim.notify("Briefing: nothing to send", vim.log.levels.WARN)
    return
  end

  local ok, sidekick_cli = pcall(require, "sidekick.cli")
  if not ok then
    vim.notify("Briefing: sidekick.nvim is not installed", vim.log.levels.ERROR)
    return
  end

  sidekick_cli.send({ msg = text })
  M.close()
end

return M

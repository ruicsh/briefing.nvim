local config = require("briefing.config")

local M = {}

-- Track the window and buffer handles
-- Stored per-tab: vim.t.briefing_bufnr, vim.t.briefing_winid

--- Get or create the briefing buffer for the current tab.
---@return integer bufnr
local function get_or_create_buf()
  local bufnr = vim.t.briefing_bufnr

  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    return bufnr
  end

  bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].filetype = "briefing"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false

  vim.t.briefing_bufnr = bufnr
  return bufnr
end

--- Compute centered floating window dimensions.
---@return vim.api.keyset.win_config
local function win_config()
  local opts = config.options.window
  local width = opts.width
  local height = opts.height
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)

  return {
    relative = "editor",
    width = width,
    height = height,
    col = col,
    row = row,
    style = "minimal",
    border = opts.border,
    title = opts.title,
    title_pos = "center",
  }
end

--- Set buffer-local keymaps for the briefing window.
---@param bufnr integer
local function set_keymaps(bufnr)
  local km = config.options.keymaps
  local opts = { buffer = bufnr, silent = true, nowait = true }

  vim.keymap.set({ "n", "i" }, km.send, function()
    require("briefing").send()
  end, opts)

  vim.keymap.set("n", km.close, function()
    require("briefing").close()
  end, opts)
end

--- Open (or focus) the briefing floating window.
function M.open()
  local bufnr = get_or_create_buf()

  -- If the window is already open, just focus it
  local winid = vim.t.briefing_winid
  if winid and vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_set_current_win(winid)
    return
  end

  -- Open the floating window
  winid = vim.api.nvim_open_win(bufnr, true, win_config())
  vim.t.briefing_winid = winid

  -- Window-local options tuned for prose writing
  vim.wo[winid].wrap = true
  vim.wo[winid].linebreak = true
  vim.wo[winid].number = false
  vim.wo[winid].relativenumber = false
  vim.wo[winid].signcolumn = "no"

  set_keymaps(bufnr)

  vim.cmd("startinsert")
end

--- Close the floating window, keeping the buffer alive.
function M.close()
  local winid = vim.t.briefing_winid
  if winid and vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_win_close(winid, false)
  end
  vim.t.briefing_winid = nil
end

--- Return the current buffer contents as a single string.
---@return string
function M.get_text()
  local bufnr = vim.t.briefing_bufnr
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return ""
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return table.concat(lines, "\n")
end

return M

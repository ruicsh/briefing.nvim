local M = {}

local dlog = require("briefing.log").dlog

---@class briefing.blink.Variable
---@field label string The display label (e.g. "#buffer")
---@field description string Human-readable description
---@field insert_text string Text to insert
---@field suboptions briefing.blink.Suboption[]|"path"|nil Suboptions or "path" for dynamic completion

---@class briefing.blink.Suboption
---@field label string The suboption label (e.g. "diff")
---@field description string Description of what it does
---@field insert_text string Full text to insert (e.g. "#buffer:diff")

--- Variable definitions matching existing context modules
---@type table<string, briefing.blink.Variable>
local VARIABLES = {
	buffer = {
		label = "#buffer",
		description = "Inline current buffer content (use :diff or :all after)",
		insert_text = "#buffer",
		suboptions = nil, -- Use <Tab> after #buffer: to open picker
	},
	selection = {
		label = "#selection",
		description = "Visual selection from when briefing opened",
		insert_text = "#selection",
		suboptions = nil,
	},
	diagnostics = {
		label = "#diagnostics",
		description = "LSP diagnostics",
		insert_text = "#diagnostics",
		suboptions = {
			{ label = "buffer", description = "Current buffer only (default)", insert_text = "#diagnostics:buffer" },
			{ label = "all", description = "All workspace diagnostics", insert_text = "#diagnostics:all" },
		},
	},
	diff = {
		label = "#diff",
		description = "Git diff output",
		insert_text = "#diff",
		suboptions = {
			{ label = "unstaged", description = "Unstaged changes (default)", insert_text = "#diff:unstaged" },
			{ label = "staged", description = "Staged changes", insert_text = "#diff:staged" },
		},
	},
	file = {
		label = "#file",
		description = "Content of specified file path",
		insert_text = "#file:",
		suboptions = "path",
	},
	quickfix = {
		label = "#quickfix",
		description = "Current quickfix list items",
		insert_text = "#quickfix",
		suboptions = nil,
	},
}

--- Create a new blink.cmp source instance
---@return table
function M.new()
	dlog("blink: new() called")
	return setmetatable({}, { __index = M })
end

--- Get trigger characters for this source
---@return string[]
function M:get_trigger_characters() -- luacheck: ignore 212
	dlog("blink: get_trigger_characters() called")
	return { "#", ":" }
end

--- Check if this source is enabled for the current buffer
---@return boolean
function M:enabled() -- luacheck: ignore 212
	local ft = vim.bo.filetype
	local is_enabled = ft == "briefing"
	dlog("blink: enabled() called, filetype=" .. ft .. ", enabled=" .. tostring(is_enabled))
	return is_enabled
end

--- Get completion items for variable names (after #)
---@param partial string The partial text after #
---@return table[]
local function get_variable_items(partial)
	dlog("blink: get_variable_items() called with partial='" .. partial .. "'")
	local items = {}
	local CompletionItemKind = require("blink.cmp.types").CompletionItemKind

	for _, var in pairs(VARIABLES) do
		-- Fuzzy match: variable name starts with partial (case-insensitive)
		local var_name = var.label:sub(2) -- Remove # prefix
		if var_name:lower():find(partial:lower(), 1, true) == 1 then
			table.insert(items, {
				label = var.label,
				kind = CompletionItemKind.Variable,
				detail = var.description,
				insertText = var.insert_text,
				insertTextFormat = vim.lsp.protocol.InsertTextFormat.PlainText,
			})
			dlog("blink: added variable item: " .. var.label)
		end
	end

	dlog("blink: get_variable_items() returning " .. #items .. " items")
	return items
end

--- Get file path completions after #file:
---@param partial string The partial path typed
---@return table[]
local function get_file_path_items(partial)
	dlog("blink: get_file_path_items() called with partial='" .. partial .. "'")
	local items = {}
	local CompletionItemKind = require("blink.cmp.types").CompletionItemKind

	if partial == "" then
		-- No partial path yet, don't return anything
		dlog("blink: empty partial, returning no items")
		return items
	end

	-- Try to complete the path
	local glob_pattern = partial .. "*"
	local files = vim.fn.glob(glob_pattern, false, true)
	dlog("blink: glob('" .. glob_pattern .. "') returned " .. #files .. " files")

	-- Also try with **/ prefix for recursive matching
	if not partial:find("/") then
		local recursive_files = vim.fn.glob("**/" .. partial .. "*", false, true)
		dlog("blink: glob('**/" .. partial .. "*') returned " .. #recursive_files .. " files")
		for _, f in ipairs(recursive_files) do
			if not vim.tbl_contains(files, f) then
				table.insert(files, f)
			end
		end
	end

	local cwd = vim.fn.getcwd():gsub("/$", "")

	for _, filepath in ipairs(files) do
		-- Skip directories that don't match the partial exactly
		if partial ~= "" and not filepath:find(partial, 1, true) then
			goto continue
		end

		-- Make path relative if under cwd
		local display_path = filepath
		if filepath:sub(1, #cwd + 1) == cwd .. "/" then
			display_path = filepath:sub(#cwd + 2)
		end

		-- For directories, add trailing slash
		local is_dir = vim.fn.isdirectory(filepath) == 1
		local insert_text = "#file:" .. display_path
		if is_dir then
			insert_text = insert_text .. "/"
		end

		table.insert(items, {
			label = "#file:" .. display_path .. (is_dir and "/" or ""),
			kind = is_dir and CompletionItemKind.Folder or CompletionItemKind.File,
			detail = is_dir and "Directory" or "File",
			insertText = insert_text,
			insertTextFormat = vim.lsp.protocol.InsertTextFormat.PlainText,
		})

		::continue::
	end

	dlog("blink: get_file_path_items() returning " .. #items .. " items")
	return items
end

--- Get suboption completions for a variable
---@param var_name string The variable name (e.g. "buffer")
---@param partial string The partial text after the colon
---@return table[]
local function get_suboption_items(var_name, partial)
	dlog("blink: get_suboption_items() called with var_name='" .. var_name .. "', partial='" .. partial .. "'")
	local items = {}
	local var = VARIABLES[var_name]

	if not var then
		dlog("blink: unknown variable '" .. var_name .. "'")
		return items
	end

	-- Special handling for file paths
	if var.suboptions == "path" then
		dlog("blink: variable has path suboptions")
		return get_file_path_items(partial)
	end

	-- Regular suboptions
	if not var.suboptions then
		dlog("blink: variable has no suboptions")
		return items
	end

	local CompletionItemKind = require("blink.cmp.types").CompletionItemKind

	for _, opt in ipairs(var.suboptions) do
		-- Fuzzy match on suboption label
		if opt.label:lower():find(partial:lower(), 1, true) == 1 then
			table.insert(items, {
				label = opt.label,
				kind = CompletionItemKind.EnumMember,
				detail = opt.description,
				insertText = opt.insert_text,
				insertTextFormat = vim.lsp.protocol.InsertTextFormat.PlainText,
			})
			dlog("blink: added suboption item: " .. opt.label)
		end
	end

	dlog("blink: get_suboption_items() returning " .. #items .. " items")
	return items
end

--- Main completion handler for blink.cmp
---@param ctx table Completion context from blink.cmp
---@param callback function Callback to return results
function M:get_completions(ctx, callback) -- luacheck: ignore 212
	dlog("blink: get_completions() called")
	dlog("blink: ctx.line='" .. ctx.line .. "', cursor.col=" .. ctx.cursor[2])

	local line_before_cursor = ctx.line:sub(1, ctx.cursor[2])
	dlog("blink: line_before_cursor='" .. line_before_cursor .. "'")

	-- Check if we're completing after '#var:' (suboptions)
	-- Pattern: #word:partial$
	local var_name, suboption_partial = line_before_cursor:match("#([a-zA-Z_]+):([%w_./%-]*)$")
	dlog("blink: match result - var_name=" .. tostring(var_name) .. ", suboption_partial=" .. tostring(suboption_partial))

	local items = {}

	if var_name then
		-- Completing suboptions after '#var:'
		dlog("blink: completing suboptions for '" .. var_name .. "'")
		items = get_suboption_items(var_name, suboption_partial)
	else
		-- Check if we're completing a variable name after '#'
		local partial_var = line_before_cursor:match("#([a-zA-Z_]*)$")
		dlog("blink: partial_var=" .. tostring(partial_var))
		if partial_var then
			dlog("blink: completing variable names")
			items = get_variable_items(partial_var)
		else
			dlog("blink: no # pattern found, returning empty")
		end
	end

	dlog("blink: calling callback with " .. #items .. " items")
	callback({
		items = items,
		is_incomplete_forward = false,
		is_incomplete_backward = false,
	})
end

--- Helper to generate blink.cmp provider configuration
---@param opts? { score_offset?: number }
---@return table provider_config
function M.setup(opts)
	opts = opts or {}
	return {
		name = "Briefing",
		module = "briefing.integrations.blink",
		enabled = function()
			return vim.bo.filetype == "briefing"
		end,
		score_offset = opts.score_offset or -10,
	}
end

return M

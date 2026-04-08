local M = {}

--- A parsed context token from the briefing buffer.
---@class briefing.Token
---@field type "context"   token kind (always "context" for # tokens)
---@field name string      token name, e.g. "buffer", "diagnostics"
---@field suboption? string  optional suboption, e.g. "diff", "all"
---@field raw string       the original token text, e.g. "#diff:buffer"

--- Convert @path references to #file:path format.
--- Matches @ followed by a file path (must contain / or . to distinguish from mentions).
---@param text string
---@return string
function M.preprocess_at_refs(text)
	-- Match @path where path contains at least one / or . (file paths, not mentions)
	-- Must be preceded by whitespace or start of line
	-- Must be followed by whitespace or end of line
	local result = text

	-- Pattern explanation:
	-- ([%s\n]) = capture group 1: whitespace or newline before @
	-- @ = literal @
	-- ([a-zA-Z0-9_./-]+) = capture group 2: the path (letters, numbers, underscores, dots, slashes, hyphens)
	-- (?=.) = lookahead to ensure there's at least one . or / in the path
	-- [%s\n]? = optional whitespace or newline after
	local pos = 1
	while pos <= #result do
		-- Find next @
		local at_pos = result:find("@", pos, true)
		if not at_pos then
			break
		end

		-- Check character before @: must be start-of-string, newline, or space
		local before = at_pos > 1 and result:sub(at_pos - 1, at_pos - 1) or nil
		if before ~= nil and before ~= " " and before ~= "\t" and before ~= "\n" then
			pos = at_pos + 1
			goto continue_pre
		end

		-- Match the path after @
		local after = result:sub(at_pos + 1)
		local path = after:match("^([a-zA-Z0-9_./-]+)")
		if not path then
			pos = at_pos + 1
			goto continue_pre
		end

		-- Check if it looks like a file path (has / or .)
		if not path:find("[./]") then
			pos = at_pos + 1
			goto continue_pre
		end

		-- Check character after path: must be end-of-string, newline, or space
		local after_path_pos = at_pos + 1 + #path
		local after_path = result:sub(after_path_pos, after_path_pos)
		if after_path ~= "" and after_path ~= " " and after_path ~= "\t" and after_path ~= "\n" then
			pos = at_pos + 1
			goto continue_pre
		end

		-- Replace @path with #file:path
		result = result:sub(1, at_pos - 1) .. "#file:" .. path .. result:sub(after_path_pos)

		pos = at_pos + 7 + #path -- Skip past #file: + path

		::continue_pre::
	end

	return result
end

--- Parse all `#name` and `#name:suboption` tokens from a text string.
--- Tokens must be preceded by whitespace or start-of-line, and followed by
--- whitespace or end-of-line (so e.g. "foo#bar" is not a token).
---@param text string
---@return briefing.Token[]
function M.parse(text)
	local tokens = {}
	local pos = 1
	while pos <= #text do
		-- Find the next `#`
		local hash_pos = text:find("#", pos, true)
		if not hash_pos then
			break
		end

		-- Check the character before `#`: must be start-of-string, newline, or space
		local before = hash_pos > 1 and text:sub(hash_pos - 1, hash_pos - 1) or nil
		if before ~= nil and before ~= " " and before ~= "\t" and before ~= "\n" then
			pos = hash_pos + 1
			goto continue
		end

		-- Match `#name` or `#name:suboption` starting at hash_pos + 1
		local after = text:sub(hash_pos + 1)
		local name, rest = after:match("^([%a][%w_]*)(.*)")
		if not name then
			pos = hash_pos + 1
			goto continue
		end

		-- Optionally match `:suboption`
		local suboption = nil
		local token_end = hash_pos + #name -- points to last char of name
		local colon_rest = rest:match("^:([%w%./_%-]*)")
		if colon_rest ~= nil then
			suboption = colon_rest ~= "" and colon_rest or nil
			token_end = token_end + 1 + #(colon_rest or "")
		end

		-- Check the character after the token: must be end-of-string, newline, or space
		local after_token = text:sub(token_end + 1, token_end + 1)
		if after_token ~= "" and after_token ~= " " and after_token ~= "\t" and after_token ~= "\n" then
			pos = hash_pos + 1
			goto continue
		end

		local raw_token = "#" .. name .. (suboption and (":" .. suboption) or (colon_rest ~= nil and ":" or ""))
		tokens[#tokens + 1] = {
			type = "context",
			name = name,
			suboption = suboption,
			raw = raw_token,
		}

		pos = token_end + 1
		::continue::
	end

	return tokens
end

--- Resolve a single token to its text content.
--- Returns nil if the token name has no registered resolver.
---@param token briefing.Token
---@param prev_winid? integer  window handle that was active before briefing opened
---@return string|nil
function M.resolve(token, prev_winid)
	if token.name == "buffer" then
		return require("briefing.context.buffer").resolve(prev_winid)
	elseif token.name == "selection" then
		return require("briefing.context.selection").resolve()
	elseif token.name == "diagnostics" then
		return require("briefing.context.diagnostics").resolve(token.suboption, prev_winid)
	elseif token.name == "diff" then
		return require("briefing.context.diff").resolve(token.suboption, prev_winid)
	elseif token.name == "file" then
		return require("briefing.context.file").resolve(token.suboption)
	elseif token.name == "quickfix" then
		return require("briefing.context.quickfix").resolve()
	elseif token.name == "filepath" then
		return require("briefing.context.filepath").resolve(token.suboption, prev_winid)
	end
	return nil
end

return M

local M = {}

--- Run a git command and return (stdout, ok).
--- `ok` is false when the exit code is non-zero.
---@param args string[]
---@return string stdout
---@return boolean ok
local function git(args)
	local completed = vim.system(args, { text = true }):wait()
	if completed.code ~= 0 then
		return (completed.stderr or ""), false
	end
	return (completed.stdout or ""), true
end

--- Wrap raw diff output in a fenced diff block with a header label.
---@param label string  human-readable label, e.g. "#diff:unstaged"
---@param output string
---@return string
local function wrap_diff(label, output)
	if output == "" then
		return ""
	end
	return ("%s\n```diff\n%s```"):format(label, output)
end

--- Resolve `#diff:unstaged` — all unstaged changes.
---@return string
local function resolve_unstaged()
	local out, ok = git({ "git", "diff" })
	if not ok then
		vim.notify("Briefing: #diff:unstaged — git diff failed: " .. out, vim.log.levels.WARN)
		return ""
	end
	if out == "" then
		vim.notify("Briefing: #diff:unstaged — no unstaged changes", vim.log.levels.WARN)
		return ""
	end
	return wrap_diff("#diff:unstaged", out)
end

--- Resolve `#diff:staged` — staged changes.
---@return string
local function resolve_staged()
	local out, ok = git({ "git", "diff", "--cached" })
	if not ok then
		vim.notify("Briefing: #diff:staged — git diff --cached failed: " .. out, vim.log.levels.WARN)
		return ""
	end
	if out == "" then
		vim.notify("Briefing: #diff:staged — no staged changes", vim.log.levels.WARN)
		return ""
	end
	return wrap_diff("#diff:staged", out)
end

--- Resolve `#diff:<sha>` — diff for a specific commit.
---@param sha string
---@return string
local function resolve_sha(sha)
	local out, ok = git({ "git", "show", sha })
	if not ok then
		vim.notify("Briefing: #diff:" .. sha .. " — git show failed: " .. out, vim.log.levels.WARN)
		return ""
	end
	if out == "" then
		return ""
	end
	return wrap_diff("#diff:" .. sha, out)
end

--- Resolve the `#diff` context variable.
--- Suboptions: "unstaged" (default), "staged", or a commit SHA.
---@param suboption? string  "unstaged", "staged", a sha, or nil (defaults to "unstaged")
---@return string
function M.resolve(suboption)
	if suboption == nil or suboption == "unstaged" then
		return resolve_unstaged()
	elseif suboption == "staged" then
		return resolve_staged()
	else
		return resolve_sha(suboption)
	end
end

return M

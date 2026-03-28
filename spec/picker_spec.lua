local picker = require("briefing.picker")

describe("briefing.picker", function()
	describe("get_buffer_pattern()", function()
		it("matches #buffer: at end of line", function()
			local line = "Check this #buffer:"
			local col = #line
			local pattern, start_col = picker.get_buffer_pattern(line, col)
			assert.equals("buffer", pattern)
			assert.equals(12, start_col)
		end)

		it("matches #diff:buffer: at end of line", function()
			local line = "Check #diff:buffer:"
			local col = #line
			local pattern, start_col = picker.get_buffer_pattern(line, col)
			assert.equals("diff:buffer", pattern)
			assert.equals(7, start_col)
		end)

		it("returns nil when cursor is not after pattern", function()
			local line = "Check #buffer: all"
			local col = #line
			local pattern = picker.get_buffer_pattern(line, col)
			assert.is_nil(pattern)
		end)

		it("matches pattern when followed by partial text", function()
			local line = "Check #buffer:fil"
			local col = #line - 3
			local pattern, start_col = picker.get_buffer_pattern(line, col)
			assert.equals("buffer", pattern)
			assert.equals(7, start_col)
		end)

		it("returns nil when pattern is in the middle of text", function()
			local line = "Check #buffer: and more"
			local col = #line
			local pattern = picker.get_buffer_pattern(line, col)
			assert.is_nil(pattern)
		end)

		it("returns nil when cursor is before pattern", function()
			local line = "Check #buffer:"
			local col = 5
			local pattern = picker.get_buffer_pattern(line, col)
			assert.is_nil(pattern)
		end)
	end)

	describe("open_picker() with buffer type", function()
		local captured_lines
		local orig_nvim_buf_get_lines = vim.api.nvim_buf_get_lines
		local orig_nvim_buf_set_lines = vim.api.nvim_buf_set_lines
		local orig_nvim_win_is_valid = vim.api.nvim_win_is_valid
		local orig_nvim_set_current_win = vim.api.nvim_set_current_win
		local orig_schedule = vim.schedule
		local orig_cmd = vim.cmd
		local orig_getcwd = vim.fn.getcwd

		before_each(function()
			captured_lines = nil

			vim.api.nvim_buf_get_lines = function(_, start_row, _, _)
				if captured_lines then
					return { captured_lines[start_row + 1] }
				end
				return { "" }
			end

			vim.api.nvim_buf_set_lines = function(_, _, _, _, lines)
				captured_lines = lines
			end

			vim.api.nvim_win_is_valid = function(_)
				return true
			end

			vim.api.nvim_set_current_win = function(_)
				-- no-op for testing
			end

			vim.schedule = function(fn)
				fn()
			end

			vim.cmd = function(_)
				-- no-op for testing
			end

			vim.fn.getcwd = function()
				return "/home/user/project"
			end
		end)

		after_each(function()
			vim.api.nvim_buf_get_lines = orig_nvim_buf_get_lines
			vim.api.nvim_buf_set_lines = orig_nvim_buf_set_lines
			vim.api.nvim_win_is_valid = orig_nvim_win_is_valid
			vim.api.nvim_set_current_win = orig_nvim_set_current_win
			vim.schedule = orig_schedule
			vim.cmd = orig_cmd
			vim.fn.getcwd = orig_getcwd
		end)

		it("replaces #buffer: with #file:<relative_path>", function()
			local initial_line = "Check #buffer:"
			captured_lines = { initial_line }

			vim.api.nvim_buf_get_lines = function(_, _, _, _)
				return { initial_line }
			end

			local confirm_callback = nil
			package.loaded["snacks"] = {
				picker = {
					buffers = function(opts)
						confirm_callback = opts.confirm
					end,
				},
			}

			picker.open_picker({
				type = "buffer",
				pattern = "buffer",
				start_col = 7,
				line_nr = 1,
			})

			local mock_picker = {
				close = function() end,
				selected = function()
					return {}
				end,
			}
			local mock_item = { file = "/home/user/project/lua/test.lua" }

			confirm_callback(mock_picker, mock_item)

			assert.equals("Check #file:lua/test.lua ", captured_lines[1])
		end)

		it("replaces #diff:buffer: with #file:<relative_path>", function()
			local initial_line = "Check #diff:buffer:"
			captured_lines = { initial_line }

			vim.api.nvim_buf_get_lines = function(_, _, _, _)
				return { initial_line }
			end

			local confirm_callback = nil
			package.loaded["snacks"] = {
				picker = {
					buffers = function(opts)
						confirm_callback = opts.confirm
					end,
				},
			}

			picker.open_picker({
				type = "buffer",
				pattern = "diff:buffer",
				start_col = 7,
				line_nr = 1,
			})

			local mock_picker = {
				close = function() end,
				selected = function()
					return {}
				end,
			}
			local mock_item = { file = "/home/user/project/src/main.ts" }

			confirm_callback(mock_picker, mock_item)

			assert.equals("Check #file:src/main.ts ", captured_lines[1])
		end)

		it("handles multiple selections with spaces", function()
			local initial_line = "Check #buffer:"
			captured_lines = { initial_line }

			vim.api.nvim_buf_get_lines = function(_, _, _, _)
				return { initial_line }
			end

			local confirm_callback = nil
			package.loaded["snacks"] = {
				picker = {
					buffers = function(opts)
						confirm_callback = opts.confirm
					end,
				},
			}

			picker.open_picker({
				type = "buffer",
				pattern = "buffer",
				start_col = 7,
				line_nr = 1,
			})

			local mock_picker = {
				close = function() end,
				selected = function()
					return {
						{ file = "/home/user/project/a.lua" },
						{ file = "/home/user/project/b.lua" },
					}
				end,
			}
			local mock_item = { file = "/home/user/project/a.lua" }

			confirm_callback(mock_picker, mock_item)

			assert.equals("Check #file:a.lua #file:b.lua ", captured_lines[1])
		end)

		it("uses absolute path when file is outside cwd", function()
			local initial_line = "Check #buffer:"
			captured_lines = { initial_line }

			vim.api.nvim_buf_get_lines = function(_, _, _, _)
				return { initial_line }
			end

			local confirm_callback = nil
			package.loaded["snacks"] = {
				picker = {
					buffers = function(opts)
						confirm_callback = opts.confirm
					end,
				},
			}

			picker.open_picker({
				type = "buffer",
				pattern = "buffer",
				start_col = 7,
				line_nr = 1,
			})

			local mock_picker = {
				close = function() end,
				selected = function()
					return {}
				end,
			}
			local mock_item = { file = "/other/path/file.lua" }

			confirm_callback(mock_picker, mock_item)

			assert.equals("Check #file:/other/path/file.lua ", captured_lines[1])
		end)

		it("handles empty file path gracefully", function()
			local initial_line = "Check #buffer:"
			captured_lines = { initial_line }

			vim.api.nvim_buf_get_lines = function(_, _, _, _)
				return { initial_line }
			end

			local confirm_callback = nil
			package.loaded["snacks"] = {
				picker = {
					buffers = function(opts)
						confirm_callback = opts.confirm
					end,
				},
			}

			picker.open_picker({
				type = "buffer",
				pattern = "buffer",
				start_col = 7,
				line_nr = 1,
			})

			local mock_picker = {
				close = function() end,
				selected = function()
					return {}
				end,
			}
			local mock_item = { file = "" }

			confirm_callback(mock_picker, mock_item)

			assert.equals("Check #file: ", captured_lines[1])
		end)

		it("handles nil item gracefully", function()
			local initial_line = "Check #buffer:"
			local set_lines_called = false
			captured_lines = nil

			vim.api.nvim_buf_get_lines = function(_, _, _, _)
				return { initial_line }
			end

			vim.api.nvim_buf_set_lines = function(_, _, _, _, _)
				set_lines_called = true
			end

			local confirm_callback = nil
			package.loaded["snacks"] = {
				picker = {
					buffers = function(opts)
						confirm_callback = opts.confirm
					end,
				},
			}

			picker.open_picker({
				type = "buffer",
				pattern = "buffer",
				start_col = 7,
				line_nr = 1,
			})

			local mock_picker = {
				close = function() end,
				selected = function()
					return {}
				end,
			}

			confirm_callback(mock_picker, nil)

			assert.is_false(set_lines_called)
		end)
	end)

	describe("open_picker() with file type", function()
		local captured_lines
		local orig_get_current_buf = vim.api.nvim_get_current_buf
		local orig_get_current_win = vim.api.nvim_get_current_win
		local orig_nvim_buf_get_lines = vim.api.nvim_buf_get_lines
		local orig_nvim_buf_set_lines = vim.api.nvim_buf_set_lines
		local orig_nvim_win_is_valid = vim.api.nvim_win_is_valid
		local orig_nvim_set_current_win = vim.api.nvim_set_current_win
		local orig_schedule = vim.schedule
		local orig_cmd = vim.cmd
		local orig_getcwd = vim.fn.getcwd

		before_each(function()
			captured_lines = nil

			vim.api.nvim_get_current_buf = function()
				return 1
			end

			vim.api.nvim_get_current_win = function()
				return 1
			end

			vim.api.nvim_buf_get_lines = function(_, start_row, _, _)
				if captured_lines then
					return { captured_lines[start_row + 1] }
				end
				return { "" }
			end

			vim.api.nvim_buf_set_lines = function(_, _, _, _, lines)
				captured_lines = lines
			end

			vim.api.nvim_win_is_valid = function(_)
				return true
			end

			vim.api.nvim_set_current_win = function(_) end

			vim.schedule = function(fn)
				fn()
			end

			vim.cmd = function(_) end

			vim.fn.getcwd = function()
				return "/home/user/project"
			end
		end)

		after_each(function()
			vim.api.nvim_get_current_buf = orig_get_current_buf
			vim.api.nvim_get_current_win = orig_get_current_win
			vim.api.nvim_buf_get_lines = orig_nvim_buf_get_lines
			vim.api.nvim_buf_set_lines = orig_nvim_buf_set_lines
			vim.api.nvim_win_is_valid = orig_nvim_win_is_valid
			vim.api.nvim_set_current_win = orig_nvim_set_current_win
			vim.schedule = orig_schedule
			vim.cmd = orig_cmd
			vim.fn.getcwd = orig_getcwd
		end)

		it("appends #file:<path> after #file: token", function()
			local initial_line = "Check #file:"
			captured_lines = { initial_line }

			vim.api.nvim_buf_get_lines = function(_, _, _, _)
				return { initial_line }
			end

			local confirm_callback = nil
			package.loaded["snacks"] = {
				picker = {
					files = function(opts)
						confirm_callback = opts.confirm
					end,
				},
			}

			picker.open_picker({
				type = "file",
				start_col = 7,
				line_nr = 1,
			})

			local mock_picker = {
				close = function() end,
				selected = function()
					return {}
				end,
			}
			local mock_item = { file = "/home/user/project/lua/test.lua" }

			confirm_callback(mock_picker, mock_item)

			assert.equals("Check #file:lua/test.lua ", captured_lines[1])
		end)

		it("handles multiple file selections", function()
			local initial_line = "Check #file:"
			captured_lines = { initial_line }

			vim.api.nvim_buf_get_lines = function(_, _, _, _)
				return { initial_line }
			end

			local confirm_callback = nil
			package.loaded["snacks"] = {
				picker = {
					files = function(opts)
						confirm_callback = opts.confirm
					end,
				},
			}

			picker.open_picker({
				type = "file",
				start_col = 7,
				line_nr = 1,
			})

			local mock_picker = {
				close = function() end,
				selected = function()
					return {
						{ file = "/home/user/project/a.lua" },
						{ file = "/home/user/project/b.lua" },
					}
				end,
			}
			local mock_item = { file = "/home/user/project/a.lua" }

			confirm_callback(mock_picker, mock_item)

			assert.equals("Check #file:a.lua #file:b.lua ", captured_lines[1])
		end)

		it("uses absolute path when file is outside cwd", function()
			local initial_line = "Check #file:"
			captured_lines = { initial_line }

			vim.api.nvim_buf_get_lines = function(_, _, _, _)
				return { initial_line }
			end

			local confirm_callback = nil
			package.loaded["snacks"] = {
				picker = {
					files = function(opts)
						confirm_callback = opts.confirm
					end,
				},
			}

			picker.open_picker({
				type = "file",
				start_col = 7,
				line_nr = 1,
			})

			local mock_picker = {
				close = function() end,
				selected = function()
					return {}
				end,
			}
			local mock_item = { file = "/other/path/file.lua" }

			confirm_callback(mock_picker, mock_item)

			assert.equals("Check #file:/other/path/file.lua ", captured_lines[1])
		end)
	end)

	describe("on_tab()", function()
		local original_feedkeys
		local original_get_current_buf
		local original_get_current_win
		local original_win_get_cursor
		local original_buf_get_lines

		before_each(function()
			original_feedkeys = vim.api.nvim_feedkeys
			original_get_current_buf = vim.api.nvim_get_current_buf
			original_get_current_win = vim.api.nvim_get_current_win
			original_win_get_cursor = vim.api.nvim_win_get_cursor
			original_buf_get_lines = vim.api.nvim_buf_get_lines
			vim.api.nvim_get_current_buf = function()
				return 999
			end
			vim.api.nvim_get_current_win = function()
				return 1
			end
		end)

		after_each(function()
			vim.api.nvim_feedkeys = original_feedkeys
			vim.api.nvim_get_current_buf = original_get_current_buf
			vim.api.nvim_get_current_win = original_get_current_win
			vim.api.nvim_win_get_cursor = original_win_get_cursor
			vim.api.nvim_buf_get_lines = original_buf_get_lines
		end)

		it("falls back to normal tab in non-briefing buffers", function()
			vim.bo = { [999] = { filetype = "lua" } }
			local feedkeys_called = false
			vim.api.nvim_feedkeys = function(keys, _, _)
				feedkeys_called = true
				assert.equals(vim.keycode("<Tab>"), keys)
			end

			picker.on_tab()
			assert.is_true(feedkeys_called)
		end)

		it("opens buffer picker when cursor is after #buffer:", function()
			vim.bo = { [999] = { filetype = "briefing" } }
			vim.api.nvim_win_get_cursor = function()
				return { 1, 14 }
			end
			vim.api.nvim_buf_get_lines = function(_, _, _, _)
				return { "Check #buffer:" }
			end

			local picker_called = false
			package.loaded["snacks"] = {
				picker = {
					buffers = function(_)
						picker_called = true
					end,
				},
			}

			picker.on_tab()
			assert.is_true(picker_called)
		end)

		it("opens file picker when cursor is after #file:", function()
			vim.bo = { [999] = { filetype = "briefing" } }
			vim.api.nvim_win_get_cursor = function()
				return { 1, 12 }
			end
			vim.api.nvim_buf_get_lines = function(_, _, _, _)
				return { "Check #file:" }
			end

			local picker_called = false
			package.loaded["snacks"] = {
				picker = {
					files = function(_)
						picker_called = true
					end,
				},
			}

			picker.on_tab()
			assert.is_true(picker_called)
		end)

		it("falls back to tab when cursor is not after pattern", function()
			vim.bo = { [999] = { filetype = "briefing" } }
			vim.api.nvim_win_get_cursor = function()
				return { 1, 5 }
			end
			vim.api.nvim_buf_get_lines = function(_, _, _, _)
				return { "Hello world" }
			end

			local feedkeys_called = false
			vim.api.nvim_feedkeys = function(_, _, _)
				feedkeys_called = true
			end

			picker.on_tab()
			assert.is_true(feedkeys_called)
		end)

		it("prioritizes #file: over #buffer:", function()
			vim.bo = { [999] = { filetype = "briefing" } }
			vim.api.nvim_win_get_cursor = function()
				return { 1, 12 }
			end
			vim.api.nvim_buf_get_lines = function(_, _, _, _)
				return { "Check #file:" }
			end

			local file_picker_called = false
			local buffer_picker_called = false
			package.loaded["snacks"] = {
				picker = {
					files = function(_)
						file_picker_called = true
					end,
					buffers = function(_)
						buffer_picker_called = true
					end,
				},
			}

			picker.on_tab()
			assert.is_true(file_picker_called)
			assert.is_false(buffer_picker_called)
		end)
	end)

	describe("get_file_pattern()", function()
		it("matches #file: at end of line", function()
			local line = "Check this #file:"
			local col = #line
			local matched, start_col = picker.get_file_pattern(line, col)
			assert.is_true(matched)
			assert.equals(12, start_col)
		end)

		it("returns false when cursor is not after pattern", function()
			local line = "Check #file: all"
			local col = #line
			local matched = picker.get_file_pattern(line, col)
			assert.is_false(matched)
		end)

		it("matches pattern when followed by partial text", function()
			local line = "Check #file:fil"
			local col = #line - 3
			local matched, start_col = picker.get_file_pattern(line, col)
			assert.is_true(matched)
			assert.equals(7, start_col)
		end)

		it("returns false when pattern is in the middle of text", function()
			local line = "Check #file: and more"
			local col = #line
			local matched = picker.get_file_pattern(line, col)
			assert.is_false(matched)
		end)

		it("returns false when cursor is before pattern", function()
			local line = "Check #file:"
			local col = 5
			local matched = picker.get_file_pattern(line, col)
			assert.is_false(matched)
		end)
	end)
end)

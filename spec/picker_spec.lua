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

		it("matches #buffer:diff: at end of line", function()
			local line = "Check #buffer:diff:"
			local col = #line
			local pattern, start_col = picker.get_buffer_pattern(line, col)
			assert.equals("buffer:diff", pattern)
			assert.equals(7, start_col)
		end)

		it("returns nil when cursor is not after pattern", function()
			local line = "Check #buffer: all"
			local col = #line
			local pattern = picker.get_buffer_pattern(line, col)
			assert.is_nil(pattern)
		end)

		it("returns nil for #buffer:all", function()
			local line = "Check #buffer:all"
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

	describe("replace_token behavior", function()
		local captured_lines

		before_each(function()
			captured_lines = nil

			-- Mock vim.api functions
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

			-- Mock vim.fn.getcwd for relative path tests
			vim.fn.getcwd = function()
				return "/home/user/project"
			end
		end)

		after_each(function()
			-- Restore original functions
			vim.api.nvim_buf_get_lines = nil
			vim.api.nvim_buf_set_lines = nil
			vim.api.nvim_win_is_valid = nil
			vim.api.nvim_set_current_win = nil
			vim.schedule = nil
			vim.cmd = nil
			vim.fn.getcwd = nil
		end)

		it("replaces #buffer: with #file:<relative_path>", function()
			-- Set up initial line
			local initial_line = "Check #buffer:"
			captured_lines = { initial_line }

			-- Mock the get_lines to return our test line
			vim.api.nvim_buf_get_lines = function(_, _, _, _)
				return { initial_line }
			end

			-- Call open_buffer_picker with mocked snacks
			local confirm_callback = nil
			package.loaded["snacks"] = {
				picker = {
					buffers = function(opts)
						confirm_callback = opts.confirm
					end,
				},
			}

			picker.open_buffer_picker({
				pattern = "buffer",
				start_col = 7,
				line_nr = 1,
			})

			-- Simulate selecting a file
			local mock_picker = {
				close = function() end,
				selected = function()
					return {}
				end,
			}
			local mock_item = { file = "/home/user/project/lua/test.lua" }

			confirm_callback(mock_picker, mock_item)

			-- Verify replacement
			assert.equals("Check #file:lua/test.lua ", captured_lines[1])
		end)

		it("replaces #buffer:diff: with #file:<relative_path>", function()
			local initial_line = "Check #buffer:diff:"
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

			picker.open_buffer_picker({
				pattern = "buffer:diff",
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

			picker.open_buffer_picker({
				pattern = "buffer",
				start_col = 7,
				line_nr = 1,
			})

			-- Simulate multi-select
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

			picker.open_buffer_picker({
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
			-- File outside cwd
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

			picker.open_buffer_picker({
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
			-- Empty file path
			local mock_item = { file = "" }

			confirm_callback(mock_picker, mock_item)

			-- Should still replace with #file: and trailing space
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

			picker.open_buffer_picker({
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

			-- Nil item - should not modify buffer
			confirm_callback(mock_picker, nil)

			-- Buffer should not be modified
			assert.is_false(set_lines_called)
		end)
	end)

	describe("on_tab()", function()
		local original_feedkeys

		before_each(function()
			original_feedkeys = vim.api.nvim_feedkeys
			vim.api.nvim_get_current_buf = function()
				return 999
			end
		end)

		after_each(function()
			vim.api.nvim_feedkeys = original_feedkeys
			vim.api.nvim_get_current_buf = nil
			vim.api.nvim_win_get_cursor = nil
			vim.api.nvim_buf_get_lines = nil
			vim.bo = vim.bo or {}
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

		it("opens picker when cursor is after #buffer:", function()
			vim.bo = { [999] = { filetype = "briefing" } }
			vim.api.nvim_win_get_cursor = function()
				return { 1, 14 } -- line 1, after "Check #buffer:"
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

		it("falls back to tab when cursor is not after pattern", function()
			vim.bo = { [999] = { filetype = "briefing" } }
			vim.api.nvim_win_get_cursor = function()
				return { 1, 5 } -- cursor in middle of text
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

	describe("replace_file_token behavior", function()
		local captured_lines

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
			vim.api.nvim_get_current_buf = nil
			vim.api.nvim_get_current_win = nil
			vim.api.nvim_buf_get_lines = nil
			vim.api.nvim_buf_set_lines = nil
			vim.api.nvim_win_is_valid = nil
			vim.api.nvim_set_current_win = nil
			vim.schedule = nil
			vim.cmd = nil
			vim.fn.getcwd = nil
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

			picker.open_file_picker({
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

			picker.open_file_picker({
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

			picker.open_file_picker({
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

	describe("on_tab() with #file:", function()
		local original_feedkeys

		before_each(function()
			original_feedkeys = vim.api.nvim_feedkeys
			vim.api.nvim_get_current_buf = function()
				return 999
			end
			vim.api.nvim_get_current_win = function()
				return 1
			end
		end)

		after_each(function()
			vim.api.nvim_feedkeys = original_feedkeys
			vim.api.nvim_get_current_buf = nil
			vim.api.nvim_get_current_win = nil
			vim.api.nvim_win_get_cursor = nil
			vim.api.nvim_buf_get_lines = nil
			vim.bo = vim.bo or {}
		end)

		it("opens file picker when cursor is after #file:", function()
			vim.bo = { [999] = { filetype = "briefing" } }
			vim.api.nvim_win_get_cursor = function()
				return { 1, 12 } -- line 1, after "Check #file:"
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
end)

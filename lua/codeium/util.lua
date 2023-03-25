local enums = require("codeium.enums")
local M = {}

function M.fallback_call(calls, with_filter)
	local num = #calls
	local fns = num - 1
	for i = 1, fns do
		local ok, result = pcall(unpack(calls[i]))
		if ok and (with_filter ~= nil and with_filter(result)) then
			return result
		end
	end
	return calls[num]
end

function M.get_editor_options(bufnr)
	local function greater_than_zero(v)
		return v > 0
	end

	return {
		tab_size = M.fallback_call({
			{ vim.api.nvim_buf_get_option, bufnr, "shiftwidth" },
			{ vim.api.nvim_buf_get_option, bufnr, "tabstop" },
			{ vim.api.nvim_get_option, "shiftwidth" },
			{ vim.api.nvim_get_option, "tabstop" },
			4,
		}, greater_than_zero),
		insert_spaces = M.fallback_call({
			{ vim.api.nvim_buf_get_option, bufnr, "expandtab" },
			{ vim.api.nvim_get_option, "expandtab" },
			true,
		}),
	}
end

function M.get_newline(bufnr)
	return enums.line_endings[vim.api.nvim_buf_get_option(bufnr, "fileformat")] or "\n"
end

function M.has_win32()
	return vim.fn.has("win32")
	-- return vim.call("exists", "*win32") == 1
end

return M

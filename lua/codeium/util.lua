local enums = require("codeium.enums")
local M = {}

function M.fallback_call(calls)
	local num = #calls
	local fns = num - 1
	for i = 1, fns do
		local ok, result = pcall(unpack(calls[i]))
		if ok then
			return result
		end
	end
	return calls[num]
end

function M.get_editor_options(bufnr)
	return {
		tab_size = M.fallback_call({
			{ vim.api.nvim_buf_get_option, bufnr, "shiftwidth" },
			{ vim.api.nvim_buf_get_option, bufnr, "tabstop" },
			{ vim.api.nvim_get_option, "shiftwidth" },
			{ vim.api.nvim_get_option, "tabstop" },
			4,
		}),
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

return M

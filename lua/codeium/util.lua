local enums = require("codeium.enums")
local M = {}

function M.fallback_call(calls, with_filter, fallback_value)
	for _, i in ipairs(calls) do
		local ok, result = pcall(unpack(i))
		if ok and (with_filter ~= nil and with_filter(result)) then
			return result
		end
	end
	return fallback_value
end

function M.get_editor_options(bufnr)
	local function greater_than_zero(v)
		return v > 0
	end

	return {
		tab_size = M.fallback_call({
			{ vim.api.nvim_buf_get_option, bufnr,       "shiftwidth" },
			{ vim.api.nvim_buf_get_option, bufnr,       "tabstop" },
			{ vim.api.nvim_get_option,     "shiftwidth" },
			{ vim.api.nvim_get_option,     "tabstop" },
		}, greater_than_zero, 4),
		insert_spaces = M.fallback_call({
			{ vim.api.nvim_buf_get_option, bufnr,      "expandtab" },
			{ vim.api.nvim_get_option,     "expandtab" },
		}, nil, true),
	}
end

function M.get_newline(bufnr)
	return enums.line_endings[vim.bo[bufnr].fileformat] or "\n"
end

return M

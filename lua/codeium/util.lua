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
			{ vim.api.nvim_get_option_value, "shiftwidth", { buf = bufnr, } },
			{ vim.api.nvim_get_option_value, "tabstop",    { buf = bufnr, } },
			{ vim.api.nvim_get_option_value, "shiftwidth" },
			{ vim.api.nvim_get_option_value, "tabstop" },
		}, greater_than_zero, 4),
		insert_spaces = M.fallback_call({
			{ vim.api.nvim_get_option_value, "expandtab", { buf = bufnr, } },
			{ vim.api.nvim_get_option_value, "expandtab" },
		}, nil, true),
	}
end

function M.get_newline(bufnr)
	return enums.line_endings[vim.bo[bufnr].fileformat] or "\n"
end

function M.get_relative_path(bufnr)
	return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":")
end

return M

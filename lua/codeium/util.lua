local enums = require("codeium.enums")
local config = require("codeium.config")
local io = require("codeium.io")
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
			{ vim.api.nvim_get_option_value, "shiftwidth", { buf = bufnr } },
			{ vim.api.nvim_get_option_value, "tabstop", { buf = bufnr } },
			{ vim.api.nvim_get_option_value, "shiftwidth" },
			{ vim.api.nvim_get_option_value, "tabstop" },
		}, greater_than_zero, 4),
		insert_spaces = M.fallback_call({
			{ vim.api.nvim_get_option_value, "expandtab", { buf = bufnr } },
			{ vim.api.nvim_get_option_value, "expandtab" },
		}, nil, true),
	}
end

function M.get_newline(bufnr)
	return enums.line_endings[vim.bo[bufnr].fileformat] or "\n"
end

local cached_roots = {}
--- @param cwd string The current working directory
--- @return string The workspace root
local function _get_project_root(cwd)
	if config.options.workspace_root.find_root then
		root = config.options.workspace_root.find_root()
		if root then
			return root
		end
	end

	if config.options.workspace_root.use_lsp then
		root = vim.lsp.buf.list_workspace_folders()[0]
		if root then
			return root
		end
	end

	-- From the CWD, walk up the tree looking for a directory that contains one of the project root files
	local candidates = config.options.workspace_root.paths
	local result = vim.fs.find(candidates, {
		path = cwd,
		upward = true,
		limit = 1,
	})

	local found = result[1]
	local dir
	if found then
		dir = vim.fs.dirname(found)
	else
		dir = cwd
	end

	return dir
end

function M.get_project_root()
	local wd = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":p:h") or vim.fn.getcwd()
	if cached_roots[wd] then
		return cached_roots[wd]
	end

	local root = _get_project_root(wd)
	cached_roots[wd] = root
	return root
end

function M.get_uri(path)
	local info = io.get_system_info()
	if info.is_windows then
		path = path:gsub("\\", "/")
		return "file:///" .. path
	end
	return "file://" .. path
end

return M

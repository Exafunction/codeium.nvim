local notify = require("codeium.notify")

local M = {}

function M.defaults()
	return {
		manager_path = nil,
		bin_path = vim.fn.stdpath("cache") .. "/codeium/bin",
		config_path = vim.fn.stdpath("cache") .. "/codeium/config.json",
		language_server_download_url = "https://github.com",
		api = {
			host = "server.codeium.com",
			port = "443",
			path = "/",
			portal_url = "codeium.com",
		},
		quiet = false,
		enterprise_mode = nil,
		detect_proxy = nil,
		tools = {},
		wrapper = nil,
		enable_chat = true,
		enable_local_search = true,
		enable_index_service = true,
		search_max_workspace_file_count = 5000,
		file_watch_max_dir_count = 50000,
		enable_cmp_source = true,
		virtual_text = {
			enabled = false,
			filetypes = {},
			default_filetype_enabled = true,
			manual = false,
			idle_delay = 75,
			virtual_text_priority = 65535,
			map_keys = true,
			accept_fallback = nil,
			key_bindings = {
				accept = "<Tab>",
				accept_word = false,
				accept_line = false,
				clear = false,
				next = "<M-]>",
				prev = "<M-[>",
			},
		},
		workspace_root = {
			use_lsp = true,
			find_root = nil,
			paths = {
				".bzr",
				".git",
				".hg",
				".svn",
				"_FOSSIL_",
				"package.json",
			},
		},
	}
end

function M.installation_defaults()
	local has_installed, installed_config = pcall(require, "codeium.installation_defaults")
	if has_installed then
		return installed_config
	else
		return {}
	end
end

function M.apply_conditional_defaults(options)
	if options.enterprise_mode then
		if options.api == nil then
			options.api = {}
		end

		if options.api.path == nil then
			options.api.path = "/_route/api_server"
		end

		if options.api.host == nil then
			notify.warn("You need to specify api.host in enterprise mode")
		else
			if options.api.portal_url == nil then
				options.api.portal_url = options.api.host .. ":" .. (options.api.port or "443")
			end
		end
	end

	return options
end

M.options = {}

function M.setup(options)
	options = options or {}

	options = M.apply_conditional_defaults(options)

	M.options = vim.tbl_deep_extend("force", {}, M.defaults(), M.installation_defaults(), options)
end

return M

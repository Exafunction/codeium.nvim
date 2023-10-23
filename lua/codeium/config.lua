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
		},
		tools = {},
		wrapper = nil,
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

M.options = {}

function M.setup(options)
	options = options or {}
	M.options = vim.tbl_deep_extend("force", {}, M.defaults(), M.installation_defaults(), options)
end

return M

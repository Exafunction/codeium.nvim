local M = {}

function M.defaults()
	return { 
		manager_path = vim.fn.stdpath("cache") .. "/codeium/manager",
		bin_path = vim.fn.stdpath("cache") .. "/codeium/bin",
		config_path = vim.fn.stdpath("cache") .. "/codeium/config.json",
		api = {
			host = "server.codeium.com",
			port = "443",
		},
		tools = {
			uname = "uname",
			genuuid = "genuuid",
		},
		wrapper = nil,
	}
end

M.options = {
	api = {},
}

function M.setup(options)
	options = options or {}

	M.options = vim.tbl_deep_extend("force", {}, M.defaults(), options)
end

return M

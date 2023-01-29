local M = {}

function M.defaults()
	return {
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

function M.job_args(cmd, options)
	local o = M.options
	local bin = o.tools[cmd[1]]

	if bin then
		cmd[1] = bin
	elseif o.wrapper then
		cmd = vim.tbl_flatten({ o.wrapper, cmd })
	end

	options.command = cmd[1]
	options.args = { unpack(cmd, 2) }
	return options
end

return M

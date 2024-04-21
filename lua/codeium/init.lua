local M = {
	Server = nil,
	Config = nil
}

function M.setup(options)
	local source = require("codeium.source")
	local server = require("codeium.api")
	local update = require("codeium.update")
	local config = require("codeium.config")
	config.setup(options)
	Config = config.options

	Server = server:new()
	update.download(function(err)
		if not err then
			server.load_api_key()
			Server.start()
			if config.options.enable_chat then
				Server.init_chat()
			end
		end
	end)

	vim.api.nvim_create_user_command("Codeium", function(opts)
		local args = opts.fargs
		if args[1] == "Auth" then
			server.authenticate()
		end
		if args[1] == "Chat" then
			Server.open_chat()
			Server.add_workspace()
		end
	end, {
		nargs = 1,
		complete = function()
			local commands = {"Auth"}
			if config.options.enable_chat then
				commands = vim.list_extend(commands, {"Chat"})
			end
			return commands
		end,
	})

	local source = source:new(Server)
	require("cmp").register_source("codeium", source)
end

function M.open_chat()
	if not Config.enable_chat then
		return
	end
	Server.open_chat()
end

function M.add_workspace()
	Server.add_workspace()
end

return M

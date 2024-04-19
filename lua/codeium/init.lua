local M = {}

function M.setup(options)
	local Source = require("codeium.source")
	local Server = require("codeium.api")
	local update = require("codeium.update")
	local config = require("codeium.config")
	config.setup(options)

	local s = Server:new()
	update.download(function(err)
		if not err then
			Server.load_api_key()
			s.start()
		end
	end)

	vim.api.nvim_create_user_command("Codeium", function(opts)
		local args = opts.fargs
		if args[1] == "Auth" then
			Server.authenticate()
		end
		if args[1] == "Chat" then
			s.get_chat_ports()
			s.add_workspace()
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

	local source = Source:new(s)
	require("cmp").register_source("codeium", source)
end

return M

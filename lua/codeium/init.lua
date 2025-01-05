local M = {}

function M.setup(options)
	local Source = require("codeium.source")
	local Server = require("codeium.api")
	local update = require("codeium.update")
	local health = require("codeium.health")
	require("codeium.config").setup(options)

	M.s = Server.new()
	update.download(function(err)
		if not err then
			Server.load_api_key()
			M.s:start()
		end
	end)
	health.register(M.s)

	vim.api.nvim_create_user_command("Codeium", function(opts)
		local args = opts.fargs
		if args[1] == "Auth" then
			Server.authenticate()
		end
		if args[1] == "Chat" then
			M.chat()
		end
		if args[1] == "Toggle" then
			M.toggle()
		end
	end, {
		nargs = 1,
		complete = function()
			local commands = { "Auth", "Toggle" }
			if require("codeium.config").options.enable_chat then
				commands = vim.list_extend(commands, { "Chat" })
			end
			return commands
		end,
	})

	local source = Source:new(M.s)
	if require("codeium.config").options.enable_cmp_source then
		require("cmp").register_source("codeium", source)
	end

	require("codeium.virtual_text").setup(M.s)
end

--- Open Codeium Chat
function M.chat()
	M.s:refresh_context()
	M.s:get_chat_ports()
	M.s:add_workspace()
end

--- Toggle the Codeium plugin
function M.toggle()
	M.s:toggle()
end

function M.enable()
	M.s:enable()
end

function M.disable()
	M.s:disable()
end

return M

local notify = require("codeium.notify")

---@class codeium
---@field Server codeium.Server|nil
---@field Config codeium.options|nil
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
	M.Config = config.options

	M.Server = server:new()
	update.download(function(err)
		if not err then
			M.Server.load_api_key()
			M.Server:start()
			if config.options.enable_chat then
				M.Server:init_chat()
			end
			M.Server:add_workspace()
		end
	end)

	vim.api.nvim_create_user_command("Codeium", function(opts)
		local args = opts.fargs
		if args[1] == "Auth" then
			M.Server.authenticate()
		end
		if args[1] == "Chat" then
			M.Server:open_chat()
			M.Server:add_workspace()
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

	require("cmp").register_source("codeium", source:new(M.Server))
end

function M.open_chat()
	if not M.Config.enable_chat then
		notify.info("Codeium Chat disabled")
		return
	end
	M.Server:open_chat()
end

function M.add_workspace()
	M.Server:add_workspace()
end

function M.generate_code()
	M.Server:request_generate_code()
end

function M.explain()
	M.Server:request_explain_code()
end

function M.refactor()
	M.Server:request_refactor()
end

function M.add_docstring()
	M.Server:request_docstring()
end

function M.connect_ide()
	M.Server:connect_ide()
end

function M.stop()
	M.Server:close()
end

return M

local Menu = require("nui.menu")
local Popup = require("nui.popup")
local Input = require("nui.input")
local event = require("nui.utils.autocmd").event
local io = require("codeium.io")
local notify = require("codeium.notify")

local function get_key(callback)
	Input({
		position = "50%",
		size = {
			width = "80%",
		},
		border = {
			style = "rounded",
			text = {
				top = "API Key",
				top_align = "center",
			},
		},
	}, {
		prompt = "> ",
		on_submit = callback,
	}):mount()
end

local function open_buffer(url, callback)
	local popup = Popup({
		enter = true,
		focusable = true,
		border = {
			style = "rounded",
			text = {
				top = "Authentication URL",
				top_align = "center",
			},
		},
		position = "50%",
		size = {
			width = "80%",
			height = "20%",
		},
	})

	popup:mount()
	popup:on(event.BufLeave, function()
		popup:unmount()
		get_key(callback)
	end)

	vim.api.nvim_buf_set_lines(popup.bufnr, 0, 1, false, {
		url,
	})
end

local function M(url, callback)
	local menu = Menu({
		position = "50%",
		size = {
			width = 25,
			height = 4,
		},
		border = {
			style = "rounded",
			text = {
				top = "Browser",
				top_align = "center",
			},
		},
	}, {
		lines = {
			Menu.item("Open Default Browser", {
				callback = function()
					local _, err = io.shell_open(url)
					if err then
						notify.error("failed to open default browser")
						return M(url, callback)
					end
					get_key(callback)
				end,
			}),
			Menu.item("Copy URL to Clipboard", {
				callback = function()
					if vim.fn.setreg("+", url) ~= 0 then
						notify.error("failed to set clipboard contents")
						return M(url, callback)
					end
					get_key(callback)
				end,
			}),
			Menu.item("Display URL", {
				callback = function()
					open_buffer(url, callback)
				end,
			}),
			Menu.item("I already have a key", {
				callback = function()
					get_key(callback)
				end,
			}),
		},
		max_width = 20,
		on_submit = function(item)
			item.callback()
		end,
	})

	menu:mount()
end

return M

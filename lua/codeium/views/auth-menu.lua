local io = require("codeium.io")
local notify = require("codeium.notify")

local function get_key(callback)
	local result = vim.fn.inputsecret("Token ")
	callback(result)
end

local function open_buffer(url, callback)
	local bufnr = vim.api.nvim_create_buf(false, true)
	assert(bufnr ~= 0, "failed to create buffer")

	vim.bo[bufnr].bufhidden = 'wipe'
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, {
		url,
		"",
		"Press enter when done, or escape to cancel",
	})

	local win_id, aucmd

	local function close()
		vim.api.nvim_del_autocmd(aucmd)
		vim.api.nvim_win_close(win_id, true)
	end

	vim.keymap.set("n", "<CR>", function()
		close()
		get_key(callback)
	end, {
		silent = true,
		buffer = bufnr,
	})

	vim.keymap.set("n", "<ESC>", function()
		close()
		get_key(callback)
	end, {
		silent = true,
		buffer = bufnr,
	})

	aucmd = vim.api.nvim_create_autocmd({ "BufLeave" }, {
		callback = close,
		buffer = bufnr,
		once = true,
	})

	local win_opts = {
		relative = "editor",
		row = 3,
		col = 3,
		style = "minimal",
		border = "rounded",
		title = "Authentication URL",
		width = 70,
		height = 6,
		zindex = 50,
		focusable = true,
		noautocmd = true,
	}

	win_id = vim.api.nvim_open_win(bufnr, true, win_opts)
end

local function M(url, callback)
	vim.ui.select({
		{
			"Open Default Browser",
			callback = function()
				local _, err = io.shell_open(url)
				if err then
					vim.pretty_print(err)
					notify.error("failed to open default browser")
					return M(url, callback)
				end
				get_key(callback)
			end,
		},
		{
			"Copy URL to Clipboard",
			callback = function()
				if vim.fn.setreg("+", url) ~= 0 then
					notify.error("failed to set clipboard contents")
					return M(url, callback)
				end
				get_key(callback)
			end,
		},
		{
			"Display URL",
			callback = function()
				open_buffer(url, callback)
			end,
		},
		{
			"I already have a key",
			callback = function()
				get_key(callback)
			end,
		},
	}, {
		prompt = "Authenticate Type",
		format_item = function(item)
			return item[1]
		end,
	}, function(item)
		if item then
			item.callback()
		end
	end)
end

return M

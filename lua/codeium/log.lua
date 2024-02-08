local p_debug = vim.env.DEBUG_CODEIUM

return require("plenary.log").new({
	plugin = "codeium/codeium.log",
	level = p_debug or "info",
})

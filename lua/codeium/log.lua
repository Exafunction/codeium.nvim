local p_debug = vim.env.DEBUG_CODEIUM

return require("plenary.log").new({
	plugin = "windsurf/windsurf",
	level = p_debug or "info",
})

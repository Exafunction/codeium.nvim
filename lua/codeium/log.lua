local p_debug = vim.fn.getenv("DEBUG_CODEIUM")
if p_debug == vim.NIL or type(p_debug) ~= "string" then
	p_debug = "info"
end

return require("plenary.log").new({
	plugin = "codeium",
	level = p_debug or "info",
})

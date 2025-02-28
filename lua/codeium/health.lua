local Server = require("codeium.api")

local M = {}

---@diagnostic disable-next-line: deprecated
local start = vim.health.start or vim.health.report_start
---@diagnostic disable-next-line: deprecated
local ok = vim.health.ok or vim.health.report_ok
local warn = vim.health.warn or vim.health.report_warn
---@diagnostic disable-next-line: deprecated
local error = vim.health.error or vim.health.report_error
---@diagnostic disable-next-line: deprecated
local info = vim.health.info or vim.health.report_info
local health_logger = { ok = ok, info = info, warn = warn, error = error }

local instance = nil

function M.check()
	start("Codeium: checking Codeium server status")
	local server_status = Server.check_status()
	if server_status.api_key_error ~= nil then
		error("API key not loaded: " .. server_status.api_key_error)
	else
		ok("API key properly loaded")
	end

	if instance == nil then
		warn("Codeium: checkhealth is not set")
		return
	end
	instance:checkhealth(health_logger)
end

---@param server codeium.Server
function M.register(server)
	instance = server
end

return M

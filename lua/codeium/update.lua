local log = require("codeium.log")
local config = require("codeium.config")
local versions = require("codeium.versions")
local io = require("codeium.io")
local Job = require("plenary.job")
local M = {}

local cached = nil
function M.get_bin_info()
	if cached then
		return cached
	end

	local os_info = io.get_system_info()
	local dir = config.options.bin_path .. "/" .. versions.extension
	local bin_sufix
	if os_info.os == "windows" then
		bin_sufix = "windows_x64.exe"
	elseif os_info.is_aarch or os_info.is_arm then
		bin_sufix = os_info.os .. "_arm"
	else
		bin_sufix = os_info.os .. "_x64"
	end

	cached = {
		dir = dir,
		bin_sufix = bin_sufix,
		bin = dir .. "/" .. "language_server_" .. bin_sufix,
		download_url = "https://github.com/Exafunction/codeium/releases/download/language-server-v"
			.. versions.extension
			.. "/language_server_"
			.. bin_sufix
			.. ".gz",
	}
	return cached
end

function M.download(callback)
	local info = M.get_bin_info()

	if io.exists(info.bin) then
		callback(nil)
		return
	end

	local gz = info.bin .. ".gz"
	vim.fn.mkdir(info.dir, "p")

	local function chmod()
		Job:new(config.job_args({
			"chmod",
			"+x",
			info.bin,
		}, {
			on_exit = vim.schedule_wrap(function(j, s)
				if s ~= 0 then
					log.error("failed to chmod Codeium server ", s, ": ", {
						stdout = j:result(),
						stderr = j:stderr_result(),
					})
					vim.notify("Failed to chmod Codeium server")
					callback("chmod_failed")
					return
				end
				vim.notify("Codeium server updated")
				callback(nil)
			end),
		})):start()
	end

	local function unpack()
		vim.notify("Unpacking Codeium server", vim.log.levels.INFO)
		Job:new(config.job_args({
			"gzip",
			"-d",
			gz,
		}, {
			on_exit = vim.schedule_wrap(function(j, s)
				if s ~= 0 then
					log.error("failed to unpack Codeium server ", s, ": ", {
						stdout = j:result(),
						stderr = j:stderr_result(),
					})
					vim.notify("Failed to unpack Codeium server")
					callback("unpack_failed")
					return
				end
				chmod()
			end),
		})):start()
	end

	local function download()
		vim.notify("Downloading Codeium Server", vim.log.levels.INFO)
		Job:new(config.job_args({
			"curl",
			"-Lo",
			gz,
			info.download_url,
		}, {
			on_exit = vim.schedule_wrap(function(j, s)
				if s ~= 0 then
					log.error("failed to download Codeium server ", s, ": ", {
						stdout = j:result(),
						stderr = j:stderr_result(),
					})
					vim.notify("Failed to download Codeium server")
					callback("download_failed")
					return
				end
				unpack()
			end),
		})):start()
	end

	download()
end

return M

local config = require("codeium.config")
local versions = require("codeium.versions")
local io = require("codeium.io")
local notify = require("codeium.notify")
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

	local function hint(err)
		notify.info(
			"you can manually install the server",
			"download and extract '",
			info.download_url,
			"' to '",
			info.bin,
			"'"
		)
		callback(err)
	end

	local function chmod()
		io.set_executable(info.bin, function(_, err)
			if err then
				notify.error("failed to chmod server", err)
				hint("chmod_failed")
			else
				notify.info("server updated")
				callback(nil)
			end
		end)
	end

	local function unpack()
		notify.info("unpacking server")
		io.gunzip(gz, function(_, err)
			if err then
				notify.error("failed to unpack server")
				hint("unpack_failed")
			else
				notify.info("server unpacked")
				chmod()
			end
		end)
	end

	local function download()
		notify.info("downloading server")
		io.download(info.download_url, gz, function(_, err)
			if err then
				notify.error("failed to download server", err)
				hint("download_failed")
			else
				notify.info("server downloaded")
				unpack()
			end
		end)
	end

	download()
end

return M

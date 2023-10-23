local config = require("codeium.config")
local versions = require("codeium.versions")
local io = require("codeium.io")
local notify = require("codeium.notify")
local M = {}

local cached = nil
local language_server_download_url = "https://github.com"
function M.get_bin_info()
	if cached then
		return cached
	end

	if config.options.tools.language_server then
		cached = {
			bin = config.options.tools.language_server,
		}
		return cached
	end

	if config.options.language_server_download_url then
		language_server_download_url = config.options.language_server_download_url
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
		download_url = language_server_download_url
			.. "/Exafunction/codeium/releases/download/language-server-v"
			.. versions.extension
			.. "/language_server_"
			.. bin_sufix
			.. ".gz",
	}
	return cached
end

function M.validate(callback)
	local info = M.get_bin_info()
	local prefix = "STABLE_BUILD_SCM_REVISION: "

	if not io.file_exists(info.bin) then
		callback(info.bin .. " not found")
		return
	end

	io.job({
		info.bin,
		"--stamp",
		on_exit = function(self, _)
			local result = self:result()

			for _, v in ipairs(result) do
				if v:sub(1, #prefix) == prefix then
					local stamp = v:sub(#prefix + 1)
					if stamp == versions.extension_stamp then
						callback(nil)
						return
					end
					notify.error(
						stamp
						.. " does not match the expected Codeium server stamp of "
						.. versions.extension_stamp
						.. ". Please update to: https://github.com/Exafunction/codeium/releases/tag/language-server-v"
						.. versions.extension
					)
					callback(nil)
					return
				end
			end

			notify.warn(
				"Codeium.nvim: the version of the Codeium server could not be determined, make sure it matches "
				.. versions.extension
			)
			callback(nil)
		end,
	}):start()
end

function M.download(callback)
	local info = M.get_bin_info()

	if io.file_exists(info.bin) then
		M.validate(callback)
		return
	end

	local gz = info.bin .. ".gz"
	vim.fn.mkdir(info.dir, "p")

	local function hint(err)
		notify.info(
			"Codeium.nvim: you can manually install the server",
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
				notify.error("Codeium.nvim: failed to chmod server", err)
				hint("chmod_failed")
			else
				notify.info("Codeium.nvim: server updated")
				M.validate(callback)
			end
		end)
	end

	local function unpack()
		notify.info("unpacking server")
		io.gunzip(gz, function(_, err)
			if err then
				notify.error("Codeium.nvim: failed to unpack server")
				hint("unpack_failed")
			else
				notify.info("Codeium.nvim: server unpacked")
				chmod()
			end
		end)
	end

	local function download()
		notify.info("downloading server")
		io.download(info.download_url, gz, function(_, err)
			if err then
				notify.error("Codeium.nvim: failed to download server", err)
				hint("download_failed")
			else
				notify.info("Codeium.nvim: server downloaded")
				unpack()
			end
		end)
	end

	download()
end

return M

local nvim_version_info = vim.api.nvim_command_output("version")
local _, _, full_match = string.find(nvim_version_info, [[NVIM v(%d+.%d+.%d+[.-a-zA-Z0-9]*)]])

if not full_match then
	local version = vim.version()
	if version then
		full_match = version.major .. "." .. version.minor .. "." .. version.patch
		if version.prerelease then
			full_match = full_match .. "-unknown-prerelease"
		end
	end
end

local extension_version = "1.1.53"
local extension_stamp = "7eed58b5255c4c5d05bb7e9c1d5e93f2d1c8bb6d"

return {
	nvim = full_match,
	extension = extension_version,
	extension_stamp = extension_stamp,
}

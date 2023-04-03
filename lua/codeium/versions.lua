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

local function readfile(path)
	if vim.fn.readfile then
		return vim.fn.readfile(path)
	else
		return vim.api.nvim_eval('readfile("' .. path .. '")')
	end
end

local path = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\\\])")
local version_info = readfile(path .. "/versions.json")
local version_parsed = vim.fn.json_decode(version_info)

if not version_parsed then
	error("unable to read version file from " .. path)
end

return {
	nvim = full_match,
	extension = version_parsed.version,
	extension_stamp = version_parsed.stamp,
}

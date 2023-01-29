local uv = vim.loop
local log = require("codeium.log")
local Path = require("plenary.path")
local Job = require("plenary.job")
local config = require("codeium.config")

local M = {}

function M.touch(path)
	local fd, err = uv.fs_open(path, "w+", 1)
	if err then
		log.error("failed to create file ", path, ": ", err)
		return nil
	end

	local stat, err = uv.fs_fstat(fd)
	uv.fs_close(fd)

	if err then
		log.error("could not stat ", path, ": ", err)
		return nil
	end

	return stat.mtime.sec
end

function M.stat_mtime(path)
	local stat, err = uv.fs_stat(path)
	if err then
		log.error("could not stat ", path, ": ", err)
		return nil
	end

	return stat.mtime.sec
end

function M.exists(path)
	local stat, err = uv.fs_stat(path)
	if err then
		return false
	end
	return stat.type == "file"
end

function M.readdir(path)
	local fd, err = uv.fs_opendir(path, nil, 1000)
	if err then
		log.error("could not open dir ", path, ": ", err)
		return {}
	end

	local entries, err = uv.fs_readdir(fd)
	uv.fs_closedir(fd)
	if err then
		log.error("could not read dir ", path, ":", err)
		return {}
	end

	return entries
end

function M.tempdir(suffix)
	local dir = vim.fn.tempname() .. (suffix or "")
	vim.fn.mkdir(dir, "p")
	return dir
end

function M.timer(delay, rep, fn)
	local timer = uv.new_timer()
	fn = vim.schedule_wrap(fn)
	local function cancel()
		if timer then
			pcall(timer.stop, timer)
			pcall(timer.close, timer)
		end
		timer = nil
	end
	local function callback()
		if timer then
			fn(cancel)
		end
	end

	timer:start(delay, rep, callback)
	return cancel
end

function M.read_json(path)
	local fd, err, errcode = uv.fs_open(path, "r", 0)
	if err then
		if errcode ~= "ENOENT" then
			return nil, errcode
		end
		log.error("could not open ", path, ": ", err)
		return nil, errcode
	end

	local stat, err, errcode = uv.fs_fstat(fd)
	if err then
		uv.fs_close(fd)
		log.error("could not stat ", path, ": ", err)
		return nil, errcode
	end

	local contents, err, errcode = uv.fs_read(fd, stat.size, 0)
	uv.fs_close(fd)
	if err then
		log.error("could not read ", path, ": ", err)
		return nil, errcode
	end

	local ok, json = pcall(vim.fn.json_decode, contents)
	if not ok then
		log.error("could not parse json in ", path, ": ", err)
		return nil, json
	end

	return json, nil
end

function M.write_json(path, json)
	local ok, text = pcall(vim.fn.json_encode, json)
	if not ok then
		log.error("could not encode JSON ", path, ": ", text)
		return nil, text
	end

	local parent = Path:new(path):parent().filename
	local ok, err = pcall(vim.fn.mkdir, parent, "p")
	if not ok then
		log.error("could not create directory ", parent, ": ", err)
		return nil, err
	end

	local fd, err, errcode = uv.fs_open(path, "w+", 3)
	if err then
		log.error("could not open ", path, ": ", err)
		return nil, errcode
	end

	local size, err, errcode = uv.fs_write(fd, text, 0)
	uv.fs_close(fd)
	if err then
		log.error("could not write ", path, ": ", err)
		return nil, errcode
	end

	return size, nil
end

function M.get_command_output(...)
	local job = Job:new(config.job_args({ ... }, {}))
	local result, code = job:sync(1000)
	if code == 0 then
		return result[1]
	else
		return nil
	end
end

local system_info_cache = nil
function M.get_system_info()
	if system_info_cache then
		return system_info_cache
	end

	local uname = M.get_command_output("uname") or "windows"
	local arch = M.get_command_output("uname", "-m") or "x86_64"
	local os

	if uname == "Linux" then
		os = "linux"
	elseif uname == "Darwin" then
		os = "mac"
	else
		os = "windows"
	end

	local is_arm = string.find(arch, "arm") ~= nil
	local is_aarch = string.find(arch, "aarch64") ~= nil
	local is_x86 = arch == "x86_64"

	system_info_cache = {
		os = os,
		arch = arch,
		is_arm = is_arm,
		is_aarch = is_aarch,
		is_x86 = is_x86,
	}
	return system_info_cache
end

function M.generate_uuid()
	return M.get_command_output("uuidgen")
end

return M

local Job = require("plenary.job")
local versions = require("codeium.versions")
local config = require("codeium.config")
local io = require("codeium.io")
local log = require("codeium.log")
local update = require("codeium.update")
local api_key = nil

local function find_port(manager_dir, start_time)
	for _, file in ipairs(io.readdir(manager_dir)) do
		local number = tonumber(file.name, 10)
		if file.type == "file" and number and io.stat_mtime(manager_dir .. "/" .. file.name) >= start_time then
			return number
		end
	end
	return nil
end

local function get_request_metadata()
	return {
		api_key = api_key,
		ide_name = "neovim",
		ide_version = versions.nvim,
		extension_name = "vim",
		extension_version = versions.extension,
	}
end

local cookie_generator = 1
local function next_cookie()
	cookie_generator = cookie_generator + 1
	return cookie_generator
end

local Server = {}
Server.__index = Server

function Server.load_api_key()
	local json, err = io.read_json(config.options.config_path)
	if err then
		if err == "ENOENT" then
			vim.notify("Please log into Codeium with :Codeium Auth", vim.log.levels.INFO)
		else
			vim.notify("Failed to load Codeium API key", vim.log.levels.ERROR)
		end
		api_key = nil
	end
	api_key = (json or {}).api_key
end

function Server.save_api_key()
	local _, result = io.write_json(config.options.config_path, {
		api_key = api_key,
	})
	if result then
		vim.notify("Failed to save the Codeium API key", vim.log.levels.ERROR)
	end
end

function Server.authenticate()
	local Input = require("nui.input")
	local attempts = 0
	local uuid = io.generate_uuid()
	local url = "https://www.codeium.com/profile?response_type=token&redirect_uri=vim-show-auth-token&state="
		.. uuid
		.. "&scope=openid%20profile%20email&redirect_parameters_type=query"
	io.get_command_output("xdg-open", url)

	local prompt
	local function on_submit(value)
		Job:new(config.job_args({
			"curl",
			"-s",
			"https://api.codeium.com/register_user/",
			"--header",
			"Content-Type: application/json",
			"--data",
			vim.fn.json_encode({
				firebase_id_token = value,
			}),
		}, {
			on_exit = vim.schedule_wrap(function(j, r)
				if r ~= 0 then
					log.error("failed to validate token ", r, ": ", {
						stdout = j:result(),
						stderr = j:stderr_result(),
					})
					vim.notify("Failed to validate token", vim.log.levels.ERROR)
					return
				end

				local ok, json = pcall(vim.fn.json_decode, j:result())
				if not ok then
					log.error("failed to decode JSON: ", json)
					vim.notify("Failed to validate token", vim.log.levels.ERROR)
					return
				end

				if json and json.api_key and json.api_key ~= "" then
					api_key = json.api_key
					Server.save_api_key()
					vim.notify("API key saved", vim.log.levels.INFO)
					return
				end

				attempts = attempts + 1
				if attempts == 3 then
					vim.notify("Too many failed attempts", vim.log.levels.ERROR)
					return
				end
				vim.notify("API key is incorrect", vim.log.levels.ERROR)
				prompt()
			end),
		})):start()
	end

	prompt = function()
		Input({
			position = "50%",
			size = {
				width = 20,
			},
			border = {
				style = "rounded",
				text = {
					top = "API Key",
					top_align = "center",
				},
			},
			win_options = {
				winhighlight = "Normal:Normal,FloatBorder:Normal",
			},
		}, {
			prompt = "> ",
			on_close = function() end,
			on_submit = on_submit,
		}):mount()
	end

	prompt()
end

function Server:new()
	local m = {}
	setmetatable(m, self)

	local o = {}
	setmetatable(o, m)

	local port = nil
	local job = nil
	local current_cookie = nil
	local healthy = false

	local function request(fn, payload, callback)
		callback = vim.schedule_wrap(callback)
		Job:new(config.job_args({
			"curl",
			"http://localhost:" .. port .. "/exa.language_server_pb.LanguageServerService/" .. fn,
			"--header",
			"Content-Type: application/json",
			"--data",
			vim.fn.json_encode(payload),
		}, {
			on_exit = function(j, return_val)
				callback(return_val, j:result(), j:stderr_result())
			end,
		})):start()
	end

	local function do_heartbeat()
		request("Heartbeat", {
			metadata = get_request_metadata(),
		}, function(code, stdout, stderr)
			if code ~= 0 then
				log.warn("Codeium heartbeat failed ", code, ": ", {
					stdout = stdout,
					stderr = stderr,
				})
				vim.notify("Codeium heartbeat failed", vim.log.levels.WARN)
			else
				healthy = true
			end
		end)
	end

	function m.is_healthy()
		return healthy
	end

	function m.start()
		m.shutdown()

		local cookie = next_cookie()
		current_cookie = cookie

		if not api_key then
			io.timer(1000, 0, m.start)
			return
		end

		local manager_dir = io.tempdir("codeium/manager")
		local start_time = io.touch(manager_dir .. "/start")

		job = Job:new(config.job_args({
			update.get_bin_info().bin,
			"--api_server_host",
			config.options.api.host,
			"--api_server_port",
			config.options.api.port,
			"--manager_dir",
			manager_dir,
		}, {
			on_exit = function(j, code)
				if current_cookie ~= cookie then
					return
				end

				healthy = false
				if code ~= 0 then
					job = nil
					current_cookie = nil

					local stdout = j:result()
					local stderr = j:stderr_result()

					log.error("Codeium server crashed ", code, ": ", {
						stdout = stdout,
						stderr = stderr,
					})
					vim.notify("Codeium server crashed", vim.log.levels.ERROR)

					io.timer(1000, 0, function()
						log.debug("Restarting server after crash")
						m.start()
					end)
				end
			end,
		}))
		job:start()

		io.timer(100, 500, function(cancel)
			if current_cookie ~= cookie then
				cancel()
				return
			end

			port = find_port(manager_dir, start_time)
			if port then
				cancel()

				io.timer(100, 5000, function(cancel_heartbeat)
					if current_cookie ~= cookie then
						cancel_heartbeat()
					else
						do_heartbeat()
					end
				end)
			end
		end)
	end

	function m.request_completion(document, editor_options, callback)
		local metadata = get_request_metadata()
		local request_id = next_cookie()
		metadata.request_id = request_id

		request("GetCompletions", {
			metadata = metadata,
			editor_options = editor_options,
			document = document,
		}, function(code, stdout, stderror)
			request_id = 0

			if code ~= 0 then
				log.error("Codeium completion request failed ", code, ": ", {
					stdout = stdout,
					stderr = stderror,
				})
				vim.notify("Codeium request failed", vim.log.levels.ERROR)
				callback(false, nil)
				return
			end

			local ok, json = pcall(vim.fn.json_decode, stdout)
			if not ok then
				log.error("Invalid JSON received: ", {
					value = stdout,
					error = json,
				})
				vim.notify("Codeium request failed", vim.log.levels.ERROR)
				return
			end

			callback(true, json)
		end)

		return function()
			if request_id ~= metadata.request_id then
				return
			end

			request("CancelRequest", {
				request_id = request_id,
			}, function(code, stdout, stderr)
				if code ~= 0 then
					log.warn("Codeium failed to cancel in-flight request ", code, ": ", {
						stdout = stdout,
						stderr = stderr,
					})
				end
			end)
		end
	end

	function m.shutdown()
		current_cookie = nil
		if job then
			job.on_exit = nil
			job:shutdown()
		end
	end

	function m.__gc()
		current_cookie = nil
	end

	m.__index = m
	return o
end

return Server

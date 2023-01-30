local versions = require("codeium.versions")
local config = require("codeium.config")
local io = require("codeium.io")
local log = require("codeium.log")
local update = require("codeium.update")
local notify = require("codeium.notify")
local api_key = nil

local function find_port(manager_dir, start_time)
	local files, err = io.readdir(manager_dir)
	for _, file in ipairs(files) do
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
			-- Allow any UI plugins to load
			vim.defer_fn(function()
				notify.info("please log in with :Codeium Auth")
			end, 100)
		else
			notify.info("failed to load the api key")
		end
		api_key = nil
		return
	end
	api_key = (json or {}).api_key
end

function Server.save_api_key()
	local _, result = io.write_json(config.options.config_path, {
		api_key = api_key,
	})
	if result then
		notify.error("failed to save the api key", result)
	end
end

function Server.authenticate()
	local attempts = 0
	local uuid = io.generate_uuid()
	local url = "https://www.codeium.com/profile?response_type=token&redirect_uri=vim-show-auth-token&state="
		.. uuid
		.. "&scope=openid%20profile%20email&redirect_parameters_type=query"

	local prompt
	local function on_submit(value)
		if not value then
			return
		end

		io.post("https://api.codeium.com/register_user/", {
			headers = {
				accept = "application/json",
			},
			body = {
				firebase_id_token = value,
			},
			callback = function(body, err)
				if err and not err.response then
					notify.error("failed to validate token", err)
					return
				end

				local ok, json = pcall(vim.fn.json_decode, body)
				if not ok then
					notify.error("failed to decode json", json)
					return
				end
				if json and json.api_key and json.api_key ~= "" then
					api_key = json.api_key
					Server.save_api_key()
					notify.info("api key saved")
					return
				end

				attempts = attempts + 1
				if attempts == 3 then
					notify.error("too many failed attempts")
					return
				end
				notify.error("api key is incorrect")
				prompt(true)
			end,
		})
	end

	prompt = function(proceed)
		if proceed then
			require("codeium.views.auth-menu")(url, on_submit)
		end
	end

	prompt(true)
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
		io.post("http://localhost:" .. port .. "/exa.language_server_pb.LanguageServerService/" .. fn, {
			body = payload,
			callback = callback,
		})
	end

	local function do_heartbeat()
		request("Heartbeat", {
			metadata = get_request_metadata(),
		}, function(_, err)
			if err then
				notify.warn("heartbeat failed", err)
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

		local function on_exit(_, err)
			if current_cookie ~= cookie then
				return
			end

			healthy = false
			if err then
				job = nil
				current_cookie = nil

				notify.error("codeium server crashed", err)
				io.timer(1000, 0, function()
					log.debug("restarting server after crash")
					m.start()
				end)
			end
		end

		local function on_output(_, v, j)
			log.debug(j.pid .. ": " .. v)
		end

		job = io.job({
			update.get_bin_info().bin,
			"--api_server_host",
			config.options.api.host,
			"--api_server_port",
			config.options.api.port,
			"--manager_dir",
			manager_dir,
			enable_handlers = true,
			enable_recording = false,
			on_exit = on_exit,
			on_stdout = on_output,
			on_stderr = on_output,
		})
		job:start()

		local function start_heartbeat()
			io.timer(100, 5000, function(cancel_heartbeat)
				if current_cookie ~= cookie then
					cancel_heartbeat()
				else
					do_heartbeat()
				end
			end)
		end

		io.timer(100, 500, function(cancel)
			if current_cookie ~= cookie then
				cancel()
				return
			end

			port = find_port(manager_dir, start_time)
			if port then
				cancel()
				start_heartbeat()
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
		}, function(body, err)
			request_id = 0

			if err then
				if err.status == 408 then
					-- Timeout error
					return callback(false, nil)
				end
				notify.error("completion request failed", err)
				callback(false, nil)
				return
			end

			local ok, json = pcall(vim.fn.json_decode, body)
			if not ok then
				notify.error("completion request failed", "invalid JSON:", json)
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
			}, function(_, err)
				if err then
					log.warn("failed to cancel in-flight request", err)
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

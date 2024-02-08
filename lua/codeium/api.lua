local versions = require("codeium.versions")
local config = require("codeium.config")
local io = require("codeium.io")
local log = require("codeium.log")
local update = require("codeium.update")
local notify = require("codeium.notify")
local api_key = nil

local function find_port(manager_dir, start_time)
	local files = io.readdir(manager_dir)

	for _, file in ipairs(files) do
		local number = tonumber(file.name, 10)
		if file.type == "file" and number and io.stat_mtime(manager_dir .. "/" .. file.name) >= start_time then
			return number
		end
	end
	return nil
end

local cookie_generator = 1
local function next_cookie()
	cookie_generator = cookie_generator + 1
	return cookie_generator
end

local function get_request_metadata(request_id)
	return {
		api_key = api_key,
		ide_name = "neovim",
		ide_version = versions.nvim,
		extension_name = "neovim",
		extension_version = versions.extension,
		request_id = request_id or next_cookie(),
	}
end

local Server = {}
Server.__index = Server

function Server.load_api_key()
	local json, err = io.read_json(config.options.config_path)
	if err or type(json) ~= "table" then
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
	api_key = json.api_key
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
				prompt()
			end,
		})
	end

	prompt = function()
		require("codeium.views.auth-menu")(url, on_submit)
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
		local url = "http://127.0.0.1:" .. port .. "/exa.language_server_pb.LanguageServerService/" .. fn
		io.post(url, {
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

		current_cookie = next_cookie()

		if not api_key then
			io.timer(1000, 0, m.start)
			return
		end

		local manager_dir = config.manager_path
		if not manager_dir then
			manager_dir = io.tempdir("codeium/manager")
			vim.fn.mkdir(manager_dir, "p")
		end

		local start_time = io.touch(manager_dir .. "/start")

		local function on_exit(_, err)
			if not current_cookie then
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

		local api_server_url = "https://" .. config.options.api.host .. ":" .. config.options.api.port
		job = io.job({
			update.get_bin_info().bin,
			"--api_server_url",
			api_server_url,
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
				if not current_cookie then
					cancel_heartbeat()
				else
					do_heartbeat()
				end
			end)
		end

		io.timer(100, 500, function(cancel)
			if not current_cookie then
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

	local function noop(...) end

	local pending_request = { 0, noop }
	function m.request_completion(document, editor_options, callback)
		pending_request[2](true)

		local metadata = get_request_metadata()
		local this_pending_request

		local complete
		complete = function(...)
			complete = noop
			this_pending_request(false)
			callback(...)
		end

		this_pending_request = function(is_complete)
			if pending_request[1] == metadata.request_id then
				pending_request = { 0, noop }
			end
			this_pending_request = noop

			request("CancelRequest", {
				metadata = get_request_metadata(),
				request_id = metadata.request_id,
			}, function(_, err)
				if err then
					log.warn("failed to cancel in-flight request", err)
				end
			end)

			if is_complete then
				complete(false, nil)
			end
		end
		pending_request = { metadata.request_id, this_pending_request }

		request("GetCompletions", {
			metadata = metadata,
			editor_options = editor_options,
			document = document,
		}, function(body, err)
			if err then
				if err.status == 503 or err.status == 408 then
					-- Service Unavailable or Timeout error
					return complete(false, nil)
				end

				local ok, json = pcall(vim.fn.json_decode, err.response.body)
				if ok and json then
					if json.state and json.state.state == "CODEIUM_STATE_INACTIVE" then
						if json.state.message then
							log.debug("completion request failed", json.state.message)
						end
						return complete(false, nil)
					end
					if json.code == "canceled" then
						log.debug("completion request cancelled at the server", json.message)
						return complete(false, nil)
					end
				end

				notify.error("completion request failed", err)
				complete(false, nil)
				return
			end

			local ok, json = pcall(vim.fn.json_decode, body)
			if not ok then
				notify.error("completion request failed", "invalid JSON:", json)
				return
			end

			log.trace("completion: ", json)
			complete(true, json)
		end)

		return function()
			this_pending_request(true)
		end
	end

	function m.accept_completion(completion_id)
		request("AcceptCompletion", {
			metadata = get_request_metadata(),
			completion_id = completion_id,
		}, noop)
	end

	function m.shutdown()
		current_cookie = nil
		if job then
			job.on_exit = nil
			job:shutdown()
		end
	end

	m.__index = m
	return o
end

return Server

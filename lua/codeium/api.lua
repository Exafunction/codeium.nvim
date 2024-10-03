local versions = require("codeium.versions")
local config = require("codeium.config")
local io = require("codeium.io")
local log = require("codeium.log")
local update = require("codeium.update")
local notify = require("codeium.notify")
local util = require("codeium.util")
local enums = require("codeium.enums")

local api_key = nil
local status = {
	api_key_error = nil,
}

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

function Server.check_status()
	return status
end

function Server.load_api_key()
	local json, err = io.read_json(config.options.config_path)
	if err or type(json) ~= "table" then
		if err == "ENOENT" then
			-- Allow any UI plugins to load
			local message = "please log in with :Codeium Auth"
			status.api_key_error = message
			vim.defer_fn(function()
				notify.info(message)
			end, 100)
		else
			local message = "failed to load the api key"
			status.api_key_error = message
			notify.info(message)
		end
		api_key = nil
		return
	end

	status.api_key_error = nil
	api_key = json.api_key
end

function Server.save_api_key()
	local _, result = io.write_json(config.options.config_path, {
		api_key = api_key,
	})
	status.api_key_error = nil

	if result then
		local message = "failed to save the api key"
		status.api_key_error = message
		notify.error(message, result)
	end
end

function Server.authenticate()
	local attempts = 0
	local uuid = io.generate_uuid()
	local url = "https://"
		.. config.options.api.portal_url
		.. "/profile?response_type=token&redirect_uri=vim-show-auth-token&state="
		.. uuid
		.. "&scope=openid%20profile%20email&redirect_parameters_type=query"

	local prompt
	local function on_submit(value)
		if not value then
			return
		end

		local endpoint = "https://api.codeium.com/register_user/"

		if config.options.enterprise_mode then
			endpoint = "https://" .. config.options.api.host .. ":" .. config.options.api.port
			if config.options.api.path then
				endpoint = endpoint .. "/" .. config.options.api.path:gsub("^/", "")
			end
			endpoint = endpoint .. "/exa.seat_management_pb.SeatManagementService/RegisterUser"
		end

		io.post(endpoint, {
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
	local workspaces = {}
	local healthy = false
	local last_heartbeat = nil
	local last_heartbeat_error = nil

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
			last_heartbeat = os.time()
			last_heartbeat_error = nil
			if err then
				notify.warn("heartbeat failed", err)
				last_heartbeat_error = err
			else
				healthy = true
			end
		end)
	end

	function m.is_healthy()
		return healthy
	end

	function m.checkhealth(logger)
		logger.info("Checking server status")
		if m.is_healthy() then
			logger.ok("Server is healthy on port: " .. port)
		else
			logger.warn("Server is unhealthy")
		end

		logger.info("Language Server binary: " .. update.get_bin_info().bin)

		if last_heartbeat == nil then
			logger.warn("No heartbeat executed")
		else
			logger.info("Last heartbeat: " .. os.date("%D %H:%M:%S", last_heartbeat))
			if last_heartbeat_error ~= nil then
				logger.error(last_heartbeat_error)
			else
				logger.ok("Heartbeat ok")
			end
		end
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

		local api_server_url = "https://"
			.. config.options.api.host
			.. ":"
			.. config.options.api.port
			.. (config.options.api.path and "/" .. config.options.api.path:gsub("^/", "") or "")

		local job_args = {
			update.get_bin_info().bin,
			"--api_server_url",
			api_server_url,
			"--manager_dir",
			manager_dir,
			"--file_watch_max_dir_count",
			config.options.file_watch_max_dir_count,
			enable_handlers = true,
			enable_recording = false,
			on_exit = on_exit,
			on_stdout = on_output,
			on_stderr = on_output,
		}

		if config.options.enable_chat then
			table.insert(job_args, "--enable_chat_web_server")
			table.insert(job_args, "--enable_chat_client")
		end

		if config.options.enable_local_search then
			table.insert(job_args, "--enable_local_search")
		end

		if config.options.enable_index_service then
			table.insert(job_args, "--enable_index_service")
			table.insert(job_args, "--search_max_workspace_file_count")
			table.insert(job_args, config.options.search_max_workspace_file_count)
		end

		if config.options.api.portal_url then
			table.insert(job_args, "--portal_url")
			table.insert(job_args, "https://" .. config.options.api.portal_url)
		end

		if config.options.enterprise_mode then
			table.insert(job_args, "--enterprise_mode")
		end

		if config.options.detect_proxy ~= nil then
			table.insert(job_args, "--detect_proxy=" .. tostring(config.options.detect_proxy))
		end

		local job = io.job(job_args)
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
	function m.request_completion(document, editor_options, other_documents, callback)
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
			other_documents = other_documents,
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

	function m.refresh_context()
		-- bufnr for current buffer is 0
		local bufnr = 0

		local line_ending = util.get_newline(bufnr)
		local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)

		-- Ensure that there is always a newline at the end of the file
		table.insert(lines, "")
		local text = table.concat(lines, line_ending)

		local filetype = vim.bo.filetype
		local language = enums.languages[filetype] or enums.languages.unspecified

		local doc = {
			editor_language = filetype,
			language = language,
			cursor_offset = 0,
			text = text,
			line_ending = line_ending,
			absolute_path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":p"),
			relative_path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":"),
		}

		request("RefreshContextForIdeAction", {
			active_document = doc,
		}, function(_, err)
			if err then
				notify.error("failed refresh context: " .. err.out)
				return
			end
		end
		)
	end

	function m.add_workspace()
		local project_root = vim.fn.getcwd()
		-- workspace already tracked by server
		if workspaces[project_root] then
			return
		end
		-- unable to track hidden path
		for entry in project_root:gmatch("[^/]+") do
			if entry:sub(1, 1) == "." then
				return
			end
		end

		request("AddTrackedWorkspace", { workspace = project_root }, function(_, err)
			if err then
				notify.error("failed to add workspace: " .. err.out)
				return
			end
			workspaces[project_root] = true
		end)
	end

	function m.get_chat_ports()
		request("GetProcesses", {
			metadata = get_request_metadata(),
		}, function(body, err)
			if err then
				notify.error("failed to get chat ports", err)
				return
			end
			local ports = vim.fn.json_decode(body)
			local url = "http://127.0.0.1:"
				.. ports.chatClientPort
				.. "?api_key="
				.. api_key
				.. "&has_enterprise_extension="
				.. (config.options.enterprise_mode and "true" or "false")
				.. "&web_server_url=ws://127.0.0.1:"
				.. ports.chatWebServerPort
				.. "&ide_name=neovim"
				.. "&ide_version="
				.. versions.nvim
				.. "&app_name=codeium.nvim"
				.. "&extension_name=codeium.nvim"
				.. "&extension_version="
				.. versions.extension
				.. "&ide_telemetry_enabled=true"
				.. "&has_index_service="
				.. (config.options.enable_index_service and "true" or "false")
				.. "&locale=en_US"

			-- cross-platform solution to open the web app
			local os_info = io.get_system_info()
			if os_info.os == "linux" then
				os.execute("xdg-open '" .. url .. "'")
			elseif os_info.os == "macos" then
				os.execute("open '" .. url .. "'")
			elseif os_info.os == "windows" then
				os.execute("start " .. url)
			else
				notify.error("Unsupported operating system")
			end
		end)
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

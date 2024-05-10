local versions = require("codeium.versions")
local chat = require("codeium.chat")
local config = require("codeium.config")
local io = require("codeium.io")
local log = require("codeium.log")
local update = require("codeium.update")
local notify = require("codeium.notify")
local utils = require("codeium.util")
local wsclient = require('ws.websocket_client')
local api_key = nil

local function noop(...) end

---@return string
local function get_nonce()
	local possible = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
	local nonce = ""

	for _ = 1, 32 do
		local randomIndex = math.random(1, #possible)
		nonce = nonce .. string.sub(possible, randomIndex, randomIndex)
	end

	return nonce
end

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

local codeium_workspace_root_hints = { '.bzr', '.git', '.hg', '.svn', '_FOSSIL_', 'package.json' }
local function get_project_root()
	local last_dir = ''
	local dir = vim.fn.getcwd()
	while dir ~= last_dir do
		for root_hint in ipairs(codeium_workspace_root_hints) do
			local hint = dir .. '/' .. root_hint
			if vim.fn.isdirectory(hint) or vim.fn.filereadable(hint) then
				return dir
			end
		end
		last_dir = dir
		dir = vim.fn.fnamemodify(dir, ':h')
	end
	return vim.fn.getcwd()
end

---@class codeium.Server
---@field port? number
---@field job? plenary.Job
---@field chat_ports? table
---@field current_cookie? number
---@field workspaces table
---@field healthy boolean
---@field pending_request table
---@field ws? WebSocketClient
local Server = {
	_port = nil,
	job = nil,
	chat_ports = { chatClientPort = nil, chatWebServerPort = nil },
	current_cookie = nil,
	workspaces = {},
	healthy = false,
	pending_request = { 0, noop },
	ws = nil,
}
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

local function save_api_key()
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
					save_api_key()
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

---@return codeium.Server
function Server:new()
	local m = {}
	setmetatable(m, self)

	m.__index = m
	return m
end

function Server:start()
	self:shutdown()

	self.current_cookie = next_cookie()

	if not api_key then
		io.timer(1000, 0, self.start)
		return
	end

	local manager_dir = config.options.manager_path
	if not manager_dir then
		manager_dir = io.tempdir("codeium/manager")
		vim.fn.mkdir(manager_dir, "p")
	end

	local start_time = io.touch(manager_dir .. "/start")

	local function on_exit(_, err)
		if not self.current_cookie then
			return
		end

		self.healthy = false
		if err then
			self.job = nil
			self.current_cookie = nil

			notify.error("codeium server crashed", err)
			io.timer(1000, 0, function()
				log.debug("restarting server after crash")
				self:start()
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
			if not self.current_cookie then
				cancel_heartbeat()
			else
				self:do_heartbeat()
			end
		end)
	end

	io.timer(100, 500, function(cancel)
		if not self.current_cookie then
			cancel()
			return
		end

		self.port = find_port(manager_dir, start_time)
		if self.port then
			notify.info("Codeium server started on port " .. self.port)
			cancel()
			start_heartbeat()
		end
	end)
end

---@param fn string
---@param payload table
---@param callback function
function Server:request(fn, payload, callback)
	if not self.port then
		notify.info("Server not started yet")
		return
	end
	local url = "http://127.0.0.1:" .. self.port .. "/exa.language_server_pb.LanguageServerService/" .. fn
	io.post(url, {
		body = payload,
		callback = callback,
	})
end

function Server:init_chat()
	io.timer(200, 500, function(cancel)
		if not self.port then
			return
		end
		self:request("GetProcesses", {
			metadata = get_request_metadata(),
		}, function(body, err)
			if err then
				notify.error("failed to get chat ports", err)
				cancel()
				return
			end
			self.chat_ports = vim.fn.json_decode(body)
			notify.info("Codeium chat ready to use on server ports: client port " ..
				self.chat_ports.chatClientPort .. " and server port " .. self.chat_ports.chatWebServerPort)
			cancel()
		end)
	end)
end

function Server:request_completion(document, editor_options, other_documents, callback)
	self.pending_request[2](true)

	local metadata = get_request_metadata()
	local this_pending_request

	local complete
	complete = function(...)
		complete = noop
		this_pending_request(false)
		callback(...)
	end

	this_pending_request = function(is_complete)
		if self.pending_request[1] == metadata.request_id then
			self.pending_request = { 0, noop }
		end
		this_pending_request = noop

		self:request("CancelRequest", {
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
	self.pending_request = { metadata.request_id, this_pending_request }

	self:request("GetCompletions", {
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

function Server:accept_completion(completion_id)
	self:request("AcceptCompletion", {
		metadata = get_request_metadata(),
		completion_id = completion_id,
	}, noop)
end

function Server:do_heartbeat()
	self:request("Heartbeat", {
		metadata = get_request_metadata(),
	}, function(_, err)
		if err then
			notify.warn("heartbeat failed", err)
		else
			self.healthy = true
		end
	end)
end

function Server:is_healthy()
	return self.healthy
end

function Server:open_chat()
	if self.chat_ports == nil then
		notify.error("chat ports not found")
		return
	end
	local url = "http://127.0.0.1:"
		.. self.chat_ports.chatClientPort
		.. "?api_key="
		.. api_key
		.. "&has_enterprise_extension="
		.. (config.options.enterprise_mode and "true" or "false")
		.. "&web_server_url=ws://127.0.0.1:"
		.. self.chat_ports.chatWebServerPort
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
end

function Server:add_workspace()
	local project_root = get_project_root()
	-- workspace already tracked by server
	if self.workspaces[project_root] then
		return
	end

	io.timer(300, 500, function(cancel)
		if not self.port then
			return
		end
		self:request("AddTrackedWorkspace", { workspace = project_root, metadata = get_request_metadata() },
			function(_, err)
				if err then
					notify.error("failed to add workspace: " .. err.out)
					return
				end
				self.workspaces[project_root] = true
				notify.info("Workspace " .. project_root .. " added")
			end)
		cancel()
	end)
end

function Server:shutdown()
	self.current_cookie = nil
	if self.ws then
		self.ws.close()
	end
	if self.job then
		self.job.on_exit = nil
		self.job:shutdown()
	end
end

---@param payload table
function Server:chat_server_request(payload)
	local body = { get_chat_message_request = { metadata = get_request_metadata(), chat_messages = {payload} } }
	local input_string = vim.fn.json_encode(body)
	print("request: " .. input_string)

	self.ws.send(input_string)
	print("request sent")
end

---@param intent table
function Server:request_chat_action(intent)
	local current_timestamp = {
		seconds = os.time(),
		nanos = os.clock() * 1000000000   -- Assuming you want nanoseconds precision
	}
	local message_id = "user-" .. tostring(current_timestamp.nanos)
	local chat_message = {
		message_id = message_id,
		source = 'CHAT_MESSAGE_SOURCE_USER',
		timestamp = current_timestamp,
		conversation_id = get_nonce(),
		intent = intent,
		in_progress = false
	}
	self:chat_server_request(chat_message)
end

function Server:request_generate_code()
	self:request_chat_action(chat.intent_generate_code())
end

function Server:request_explain_code()
	self:request_function_action(chat.intent_function_explain)
end

function Server:request_docstring()
	self:request_function_action(chat.intent_function_docstring)
end

function Server:request_refactor()
	self:request_function_action(chat.intent_function_refactor)
end

function Server:connect_ide()
	local url = "ws://127.0.0.1:" .. self.chat_ports.chatWebServerPort .. "/connect/ide"
	print("Connecting to " .. url)
	local ws = wsclient(url)

	ws.on_close(function()
		print("Websocket closed ")
	end)

	ws.on_open(function()
		print("Websocket open")
	end)

	ws.on_error(function(err)
		print("Websocket error " .. err)
	end)

	ws.on_message(function(msg, is_binary)
		if is_binary then
			print("Binary message received")
		else
			local _msg = msg:to_string()
			print("Message received " .. _msg)
		end
	end)

	-- Connect to server.
	ws.connect()

	self.ws = ws
end

function Server:close()
	self.ws.close()
end

---Request action for a function under cursor.
---@param intent function
function Server:request_function_action(intent)
	local row, _ = unpack(vim.api.nvim_win_get_cursor(0))
	self:request("GetFunctions", { document = utils.buf_to_codeium(0) },
		function(body, err)
			if err then
				notify.error("failed to get functions: " .. err.out)
				return
			end

			local ok, json = pcall(vim.fn.json_decode, body)
			if ok and json then
				for _, item in ipairs(json.functionCaptures) do
					-- print("item: " .. item.nodeName)
					if item.startLine <= row and item.endLine >= row then
						self:request_chat_action(intent(item))
						return
					end
				end
			end
		end)
end

return Server

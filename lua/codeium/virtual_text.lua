local config = require("codeium.config")
local enums = require("codeium.enums")
local notify = require("codeium.notify")
local util = require("codeium.util")

local M = {}

local hlgroup = "CodeiumSuggestion"
local request_nonce = 0
local using_status_line = false

--- @type "idle" | "waiting" | "completions"
local codeium_status = "idle"

--- @class Completions
--- @field items table[] | nil
--- @field index number | nil
--- @field cancel function
--- @field request_id number
--- @field request_data table

--- @type Completions | nil
local completions
local idle_timer

local server = {
	--- This will be replaced by the actual server when setup is called.
	is_healthy = function()
		return false
	end,
}

function M.setup(_server)
	server = _server

	local augroup = vim.api.nvim_create_augroup("codeium_virtual_text", { clear = true })

	if not config.options.virtual_text.enabled then
		return
	end

	vim.api.nvim_create_autocmd({ "InsertEnter", "CursorMovedI", "CompleteChanged" }, {
		group = augroup,
		callback = function()
			M.debounced_complete()
		end,
	})

	vim.api.nvim_create_autocmd("BufEnter", {
		group = augroup,
		callback = function()
			if vim.fn.mode():match("^[iR]") then
				M.debounced_complete()
			end
		end,
	})

	vim.api.nvim_create_autocmd("InsertLeave", {
		group = augroup,
		callback = function()
			M.clear()
		end,
	})

	vim.api.nvim_create_autocmd("BufLeave", {
		group = augroup,
		callback = function()
			if vim.fn.mode():match("^[iR]") then
				M.clear()
			end
		end,
	})

	if config.options.virtual_text.map_keys then
		local bindings = config.options.virtual_text.key_bindings
		if bindings.clear and bindings.clear ~= "" then
			vim.keymap.set("i", bindings.clear, function()
				M.clear()
			end, { silent = true })
		end

		if bindings.next and bindings.next ~= "" then
			vim.keymap.set("i", bindings.next, function()
				M.cycle_completions(1)
			end, { silent = true })
		end

		if bindings.prev and bindings.prev ~= "" then
			vim.keymap.set("i", bindings.prev, function()
				M.cycle_completions(-1)
			end, { silent = true })
		end

		if bindings.accept and bindings.accept ~= "" then
			vim.keymap.set("i", bindings.accept, function()
					if not M.has_suggestions() then return bindings.accept end
					M.accept_suggestion()
				end,
				{ silent = true, expr = true, script = true, nowait = true })
		end

		if bindings.accept_word and bindings.accept_word ~= "" then
			vim.keymap.set(
				"i",
				bindings.accept_word,
				function()
					if not M.has_suggestions() then return bindings.accept_word end
					M.accept_word()
				end,
				{ silent = true, expr = true, script = true, nowait = true }
			)
		end

		if bindings.accept_line and bindings.accept_line ~= "" then
			vim.keymap.set(
				"i",
				bindings.accept_line,
				function()
					if not M.has_suggestions() then return bindings.accept_line end
					M.accept_line()
				end,
				{ silent = true, expr = true, script = true, nowait = true }
			)
		end
	end

	vim.api.nvim_create_autocmd({ "ColorScheme", "VimEnter" }, {
		group = augroup,
		callback = function()
			M.set_style()
		end,
	})
end

M.accept_suggestion = vim.schedule_wrap(function()
	M.accept()
end)

M.accept_line = vim.schedule_wrap(function()
	M.accept_next_line()
end)

M.accept_word = vim.schedule_wrap(function()
	M.accept_next_word()
end)

function M.set_style()
	if vim.fn.has("termguicolors") == 1 and vim.o.termguicolors then
		vim.api.nvim_set_hl(0, hlgroup, { fg = "#808080", default = true })
	else
		vim.api.nvim_set_hl(0, hlgroup, { ctermfg = 244, default = true })
	end
end

function M.get_completion_text()
	local completion_text = M.completion_text
	M.completion_text = nil
	return completion_text or ""
end

local function str_to_lines(str)
	return vim.fn.split(str, "\n")
end

local function move_cursor(offset)
	local row, col = unpack(vim.api.nvim_win_get_cursor(0))
	local target_row, target_col = row, col + offset
	while target_col < 0 and target_row > 1 do
		target_row = target_row - 1
		local prev_line = vim.api.nvim_buf_get_lines(0, target_row - 1, target_row, false)[1]
		target_col = #prev_line + target_col + 1
	end

	if target_col < 0 then
		target_col = 0
	end

	vim.api.nvim_win_set_cursor(0, { target_row, target_col })
end


local function delete_file_range(start_offset, end_offset)
	if end_offset <= start_offset then
		return
	end

	local start_line = vim.fn.byte2line(start_offset + 1)
	local end_line = vim.fn.byte2line(end_offset)

	local start_col = start_offset - vim.fn.line2byte(start_line) + 1
	local end_col = end_offset - vim.fn.line2byte(end_line) + 1

	local start_line_content = vim.fn.getline(start_line)
	local updated_start_line = start_line_content:sub(1, start_col)

	local end_line_content = vim.fn.getline(end_line)
	local updated_end_line = end_line_content:sub(end_col + 1)

	if start_line == end_line then
		local updated_line = updated_start_line .. updated_end_line
		vim.fn.setline(start_line, updated_line)
	else
		vim.fn.setline(start_line, updated_start_line)
		vim.fn.setline(end_line, updated_end_line)
		vim.api.nvim_buf_set_lines(0, start_line, end_line - 1, false, {})
	end

	vim.api.nvim_win_set_cursor(0, { start_line, start_col })
end


local function completion_inserter(current_completion, insert_text)
	if not (vim.fn.mode():match("^[iR]")) then
		return
	end

	if current_completion == nil then
		return
	end

	local range = current_completion.range
	local suffix = current_completion.suffix or {}
	local suffix_text = suffix.text or ""
	local delta = suffix.deltaCursorOffset or 0
	local start_offset = range.startOffset or 0
	local end_offset = range.endOffset or 0

	local text = insert_text .. suffix_text
	if text == "" then
		return
	end

	delete_file_range(start_offset, end_offset)

	M.completion_text = text

	server.accept_completion(current_completion.completion.completionId)
	local lines = str_to_lines(text)

	vim.api.nvim_put(lines, "c", false, true)

	move_cursor(delta)
end

function M.accept()
	local current_completion = M.get_current_completion_item()
	completion_inserter(current_completion, current_completion and current_completion.completion.text or "")
end

function M.accept_next_word()
	local current_completion = M.get_current_completion_item()
	local completion_parts = current_completion and (current_completion.completionParts or {}) or {}
	if #completion_parts == 0 then
		return ""
	end
	local prefix_text = completion_parts[1].prefix or ""
	local completion_text = completion_parts[1].text or ""
	local next_word = completion_text:match("^%W*%w*")
	completion_inserter(current_completion, prefix_text .. next_word)
end

function M.accept_next_line()
	local current_completion = M.get_current_completion_item()
	local text = current_completion and current_completion.completion.text:gsub("\n.*$", "") or ""
	completion_inserter(current_completion, text)
end

function M.has_suggestions()
	local current_completion = M.get_current_completion_item()
	local suffix = current_completion and current_completion.suffix or {}
	local suffix_text = suffix and suffix.text or ""
	return current_completion and current_completion.completion.text .. suffix_text
end

function M.get_current_completion_item()
	if completions and completions.items and completions.index and completions.index < #completions.items then
		return completions.items[completions.index + 1]
	end
	return nil
end

local nvim_extmark_ids = {}

local function clear_completion()
	local namespace = vim.api.nvim_create_namespace("codeium")
	for _, id in ipairs(nvim_extmark_ids) do
		vim.api.nvim_buf_del_extmark(0, namespace, id)
	end
	nvim_extmark_ids = {}
end

local function render_current_completion()
	clear_completion()
	M.redraw_status_line()

	if not vim.fn.mode():match("^[iR]") then
		return ""
	end

	local current_completion = M.get_current_completion_item()
	if current_completion == nil then
		return ""
	end

	local parts = current_completion.completionParts or {}

	local inline_cumulative_cols = 0
	local diff = 0
	for idx, part in ipairs(parts) do
		local row = (part.line or 0) + 1
		if row ~= vim.fn.line(".") then
			notify.debug("Ignoring completion, line number is not the current line.")
			goto continue
		end
		local _col
		if part.type == "COMPLETION_PART_TYPE_INLINE" then
			_col = inline_cumulative_cols + #(part.prefix or "") + 1
			inline_cumulative_cols = _col - 1
		else
			_col = #(part.prefix or "") + 1
		end
		local text = part.text

		if
			(part.type == "COMPLETION_PART_TYPE_INLINE" and idx == 1)
			or part.type == "COMPLETION_PART_TYPE_INLINE_MASK"
		then
			local completion_prefix = part.prefix or ""
			local completion_line = completion_prefix .. text
			local full_line = vim.fn.getline(row)
			local cursor_prefix = full_line:sub(1, vim.fn.col(".") - 1)
			local matching_prefix = 0
			for i = 1, #completion_line do
				if i <= #full_line and completion_line:sub(i, i) == full_line:sub(i, i) then
					matching_prefix = matching_prefix + 1
				else
					break
				end
			end
			if #cursor_prefix > #completion_prefix then
				diff = #cursor_prefix - #completion_prefix
			elseif #cursor_prefix < #completion_prefix then
				if matching_prefix >= #completion_prefix then
					diff = matching_prefix - #completion_prefix
				else
					diff = #cursor_prefix - #completion_prefix
				end
			end
			if diff > 0 then
				diff = 0
			end
			if diff < 0 then
				text = completion_prefix:sub(diff + 1) .. text
			elseif diff > 0 then
				text = text:sub(diff + 1)
			end
		end

		local priority = config.options.virtual_text.virtual_text_priority
		local _virtcol = vim.fn.virtcol({ row, _col + diff })
		local data = { id = idx + 1, hl_mode = "combine", virt_text_win_col = _virtcol - 1, priority = priority }
		if part.type == "COMPLETION_PART_TYPE_INLINE_MASK" then
			data.virt_text = { { text, hlgroup } }
		elseif part.type == "COMPLETION_PART_TYPE_BLOCK" then
			local lines = vim.split(text, "\n")
			if lines[#lines] == "" then
				table.remove(lines)
			end
			data.virt_lines = vim.tbl_map(function(l)
				return { { l, hlgroup } }
			end, lines)
		else
			goto continue
		end

		table.insert(nvim_extmark_ids, data.id)
		vim.api.nvim_buf_set_extmark(0, vim.api.nvim_create_namespace("codeium"), row - 1, 0, data)

		::continue::
	end
end

function M.clear()
	codeium_status = "idle"
	M.redraw_status_line()
	if idle_timer then
		vim.fn.timer_stop(idle_timer)
		idle_timer = nil
	end

	if completions then
		if completions.cancel then
			completions.cancel()
		end
		render_current_completion()
		completions = nil
	end

	render_current_completion()
	return ""
end

--- @param n number
function M.cycle_completions(n)
	if not completions or M.get_current_completion_item() == nil then
		return
	end

	completions.index = completions.index + n
	local n_items = #completions.items

	if completions.index < 0 then
		completions.index = completions.index + n_items
	end

	completions.index = completions.index % n_items

	render_current_completion()
end

local warn_filetype_missing = true
--- @param buf_id number
--- @param cur_line number
--- @param cur_col number
--- @return table | nil
local function get_document(buf_id, cur_line, cur_col)
	local lines = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)
	if vim.bo[buf_id].eol then
		table.insert(lines, "")
	end

	local filetype = vim.bo[buf_id].filetype:gsub("%..*", "")
	local language = enums.filetype_aliases[filetype == "" and "text" or filetype] or filetype
	if filetype == "" and warn_filetype_missing ~= false then
		notify.debug("No filetype detected. This will affect completion quality.")
		warn_filetype_missing = false
	end
	local editor_language = vim.bo[buf_id].filetype == "" and "unspecified" or vim.bo[buf_id].filetype

	local buf_name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf_id), ":p")
	-- If it's already any sort of URI, this might be a special buffer for some plugins, so we ignore it to
	-- avoid an LS error.
	if buf_name:match("^%w+://") ~= nil then
		return nil
	end

	local line_ending = util.get_newline(buf_id)
	local doc = {
		text = table.concat(lines, line_ending),
		editor_language = editor_language,
		language = enums.languages[language] or enums.languages.unspecified,
		cursor_position = { row = cur_line - 1, col = cur_col - 1 },
		absolute_uri = util.get_uri(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf_id), ":p")),
		workspace_uri = util.get_uri(util.get_project_root()),
		line_ending = line_ending,
	}

	return doc
end

--- @param opts { bufnr: number, timer: any }?
function M.complete(opts)
	if opts then
		if opts.timer ~= idle_timer then
			return
		end

		idle_timer = nil

		if vim.fn.mode() ~= "i" or opts.bufnr ~= vim.fn.bufnr("") then
			return
		end
	end

	if idle_timer then
		vim.fn.timer_stop(idle_timer)
		idle_timer = nil
	end

	if vim.o.encoding ~= "latin1" and vim.o.encoding ~= "utf-8" then
		error("Only latin1 and utf-8 are supported")
		return
	end

	local bufnr = vim.fn.bufnr("")

	if not M.filetype_enabled(bufnr) then
		return
	end

	local document = get_document(bufnr, vim.fn.line("."), vim.fn.col("."))
	if document == nil then
		return
	end

	local other_documents = util.get_other_documents(bufnr)
	local data = {
		document = document,
		editor_options = util.get_editor_options(bufnr),
		other_documents = other_documents,
	}

	if completions and completions.request_data == data then
		return
	end

	local request_data = vim.deepcopy(data)

	request_nonce = request_nonce + 1
	local request_id = request_nonce

	codeium_status = "waiting"

	local cancel = server.request_completion(
		data.document,
		data.editor_options,
		data.other_documents,
		function(success, json)
			if completions and completions.request_id == request_id then
				completions.cancel = nil
				codeium_status = "idle"
			end
			if not success then
				return
			end

			if json and json.state and json.state.state == "CODEIUM_STATE_SUCCESS" and json.completionItems then
				M.handle_completions(json.completionItems)
			end
		end
	)
	completions = {
		cancel = cancel,
		request_data = request_data,
		request_id = request_id,
	}
end

function M.handle_completions(completion_items)
	if not completions then
		return
	end
	completions.items = completion_items
	completions.index = 0
	codeium_status = "completions"
	render_current_completion()
end

function M.filetype_enabled(bufnr)
	local filetype = vim.bo[bufnr].filetype
	local enabled = config.options.virtual_text.filetypes[filetype]
	if enabled == nil then
		return config.options.virtual_text.default_filetype_enabled
	end
	return enabled
end

function M.debounced_complete()
	M.clear()
	if config.options.virtual_text.manual or not server.is_healthy() or not M.filetype_enabled(vim.fn.bufnr("")) then
		return
	end
	local current_buf = vim.fn.bufnr("")
	idle_timer = vim.fn.timer_start(config.options.virtual_text.idle_delay, function(timer)
		M.complete({ bufnr = current_buf, timer = timer })
	end)
end

function M.cycle_or_complete()
	if M.get_current_completion_item() == nil then
		M.complete()
	else
		M.cycle_completions(1)
	end
end

function M.status()
	if codeium_status == "completions" then
		if completions and completions.items and completions.index then
			return {
				state = "completions",
				current = completions.index + 1,
				total = #completions.items,
			}
		else
			return { state = "idle" }
		end
	else
		return { state = codeium_status }
	end
end

function M.status_string()
	using_status_line = true
	local status = M.status()

	if status.state == "completions" then
		if status.total > 0 then
			return string.format("%d/%d", status.current, status.total)
		else
			return " 0 "
		end
	elseif status.state == "waiting" then
		return " * "
	elseif status.state == "idle" then
		return " 0 "
	else
		return "   "
	end
end

local refresh_fn = function()
	vim.cmd("redrawstatus")
end

function M.set_statusbar_refresh(refresh)
	using_status_line = true
	refresh_fn = refresh
end

function M.redraw_status_line()
	if using_status_line then
		refresh_fn()
	end
end

return M

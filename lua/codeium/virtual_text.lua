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
			vim.keymap.set("i", bindings.accept, M.accept, { silent = true, expr = true, script = true, nowait = true })
		end

		if bindings.accept_word and bindings.accept_word ~= "" then
			vim.keymap.set(
				"i",
				bindings.accept_word,
				M.accept_next_word,
				{ silent = true, expr = true, script = true, nowait = true }
			)
		end

		if bindings.accept_line and bindings.accept_line ~= "" then
			vim.keymap.set(
				"i",
				bindings.accept_line,
				M.accept_next_line,
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

local function completion_inserter(current_completion, insert_text)
	local default = config.options.virtual_text.accept_fallback or (vim.fn.pumvisible() == 1 and "<C-N>" or "\t")

	if not (vim.fn.mode():match("^[iR]")) then
		return default
	end

	if current_completion == nil then
		return default
	end

	local range = current_completion.range
	local suffix = current_completion.suffix or {}
	local suffix_text = suffix.text or ""
	local delta = suffix.deltaCursorOffset or 0
	local start_offset = range.startOffset or 0
	local end_offset = range.endOffset or 0

	local text = insert_text .. suffix_text
	if text == "" then
		return default
	end

	local delete_range = ""
	if end_offset - start_offset > 0 then
		local delete_bytes = end_offset - start_offset
		local delete_chars = vim.fn.strchars(vim.fn.strpart(vim.fn.getline("."), 0, delete_bytes))
		delete_range = ' <Esc>"_x0"_d' .. delete_chars .. "li"
	end

	local insert_text = '<C-R><C-O>=v:lua.require("codeium.virtual_text").get_completion_text()<CR>'
	M.completion_text = text

	local cursor_text = delta == 0 and "" or '<C-O>:exe "go" line2byte(line("."))+col(".")+(' .. delta .. ")<CR>"

	server.accept_completion(current_completion.completion.completionId)

	return '<C-g>u' .. delete_range .. insert_text .. cursor_text
end

function M.accept()
	local current_completion = M.get_current_completion_item()
	return completion_inserter(current_completion, current_completion and current_completion.completion.text or "")
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
	return completion_inserter(current_completion, prefix_text .. next_word)
end

function M.accept_next_line()
	local current_completion = M.get_current_completion_item()
	local text = current_completion and current_completion.completion.text:gsub("\n.*$", "") or ""
	return completion_inserter(current_completion, text)
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

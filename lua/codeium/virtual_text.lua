local config = require("codeium.config")
local enums = require("codeium.enums")
local notify = require("codeium.notify")
local util = require("codeium.util")

local M = {}

local hlgroup = "CodeiumSuggestion"
local request_nonce = 0
local using_codeium_status = 0

local completions
local idle_timer

local server = nil
local options
function M.setup(_server, _options)
	server = _server
	options = _options

	local augroup = vim.api.nvim_create_augroup("codeium_virtual_text", { clear = true })

	if not options.enabled then
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
		bindings = config.options.virtual_text.key_bindings
		if bindings.clear then
			vim.keymap.set("i", bindings.accept, function()
				M.clear()
			end, { silent = true })
		end

		if bindings.next then
			vim.keymap.set("i", bindings.next, function()
				M.cycle_completions(1)
			end, { silent = true })
		end

		if bindings.prev then
			vim.keymap.set("i", bindings.prev, function()
				M.cycle_completions(-1)
			end, { silent = true })
		end

		if bindings.accept then
			vim.keymap.set("i", bindings.accept, M.accept, { silent = true, expr = true, script = true, nowait = true })
		end

		if bindings.accept_word then
			vim.keymap.set(
				"i",
				bindings.accept_word,
				M.accept_next_word,
				{ silent = true, expr = true, script = true, nowait = true }
			)
		end

		if bindings.accept_line then
			vim.keymap.set(
				"i",
				bindings.accept_line,
				M.accept_next_line,
				{ silent = true, expr = true, script = true, nowait = true }
			)
		end
	end

	-- vim.api.nvim_create_autocmd({ "ColorScheme", "VimEnter" }, {
	-- 	group = augroup,
	-- 	callback = function()
	-- 		vim.fn["s:SetStyle"]()
	-- 	end,
	-- })
end

function M.get_completion_text()
	local completion_text = M.completion_text
	M.completion_text = nil
	return completion_text or ""
end

local function completion_inserter(current_completion, insert_text)
	local default = vim.g.codeium_tab_fallback or (vim.fn.pumvisible() == 1 and "<C-N>" or "\t")

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

	return delete_range .. insert_text .. cursor_text
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

local function ClearCompletion()
	local namespace = vim.api.nvim_create_namespace("codeium")
	for _, id in ipairs(nvim_extmark_ids) do
		vim.api.nvim_buf_del_extmark(0, namespace, id)
	end
	nvim_extmark_ids = {}
end

local function RenderCurrentCompletion()
	ClearCompletion()
	-- TODO enable
	-- M.RedrawStatusLine()

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
			-- TODO: Implement codeium#log#Warn
			-- codeium#log#Warn('Ignoring completion, line number is not the current line.')
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

		local priority = config.options.virtual_text.priority
		local _virtcol = vim.fn.virtcol({ row, _col + diff })
		local data = { id = idx + 1, hl_mode = "combine", virt_text_win_col = _virtcol - 1, priority = priority }
		if part.type == "COMPLETION_PART_TYPE_INLINE_MASK" then
			data.virt_text = { { text, hlgroup } }
		elseif part.type == "COMPLETION_PART_TYPE_BLOCK" then
			local lines = vim.split(text, "\n", true)
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

function M.clear(...)
	vim.b._codeium_status = 0
	-- TODO enable
	-- M.RedrawStatusLine()
	if idle_timer then
		vim.fn.timer_stop(idle_timer)
		idle_timer = nil
	end

	if completions then
		if completions.cancel then
			completions.cancel()
		end
		RenderCurrentCompletion()
		completions = nil
	end

	if select("#", ...) == 0 then
		RenderCurrentCompletion()
	end
	return ""
end

function M.cycle_completions(n)
	if M.get_current_completion_item() == nil then
		return
	end

	completions.index = completions.index + n
	local n_items = #completions.items

	if completions.index < 0 then
		completions.index = completions.index + n_items
	end

	completions.index = completions.index % n_items

	RenderCurrentCompletion()
end

local warn_filetype_missing = true
function M.get_document(buf_id, cur_line, cur_col)
	local lines = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)
	if vim.bo[buf_id].eol then
		table.insert(lines, "")
	end

	local filetype = vim.bo[buf_id].filetype:gsub("%..*", "")
	local language = enums.filetype_aliases[filetype == "" and "text" or filetype] or filetype
	if filetype == "" and warn_filetype_missing ~= false then
		notify.warn("No filetype detected. This will affect completion quality.")
		warn_filetype_missing = false
	end
	local editor_language = vim.bo[buf_id].filetype == "" and "unspecified" or vim.bo[buf_id].filetype

	local doc = {
		text = table.concat(lines, vim.api.nvim_get_option_value("ff", { buf = buf_id }) == "dos" and "\r\n" or "\n"),
		editor_language = editor_language,
		language = enums.languages[language] or enums.languages.unspecified,
		cursor_position = { row = cur_line - 1, col = cur_col - 1 },
		absolute_path_migrate_me_to_uri = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf_id), ":p"),
	}

	local line_ending = vim.api.nvim_get_option_value("ff", { buf = buf_id }) == "dos" and "\r\n" or "\n"
	if line_ending then
		doc.line_ending = line_ending
	end

	return doc
end

function M.complete(...)
	if select("#", ...) == 2 then
		local bufnr, timer = ...

		if timer ~= idle_timer then
			return
		end

		idle_timer = nil

		if vim.fn.mode() ~= "i" or bufnr ~= vim.fn.bufnr("") then
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

	local other_documents = {}
	local current_bufnr = vim.fn.bufnr("%")
	local loaded_buffers = vim.fn.getbufinfo({ bufloaded = 1 })
	for _, buf in ipairs(loaded_buffers) do
		if buf.bufnr ~= current_bufnr and vim.fn.getbufvar(buf.bufnr, "&filetype") ~= "" then
			table.insert(other_documents, M.get_document(buf.bufnr, 1, 1))
		end
	end

	local bufnr = vim.fn.bufnr("")
	local data = {
		document = M.get_document(bufnr, vim.fn.line("."), vim.fn.col(".")),
		editor_options = util.get_editor_options(bufnr),
		other_documents = other_documents,
	}

	if completions and completions.request_data == data then
		return
	end

	local request_data = vim.deepcopy(data)

	request_nonce = request_nonce + 1
	local request_id = request_nonce

	vim.b._codeium_status = 1

	local cancel = server.request_completion(
		data.document,
		data.editor_options,
		data.other_documents,
		function(success, json)
			if completions.request_id == request_id then
				completions.cancel = nil
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
	RenderCurrentCompletion()
end

function M.debounced_complete()
	M.clear()
	if config.options.virtual_text.manual or not server.is_healthy() then
		return
	end
	local current_buf = vim.fn.bufnr("")
	idle_timer = vim.fn.timer_start(options.idle_delay, function()
		M.complete(current_buf, idle_timer)
	end)
end

function M.cycle_or_complete()
	if M.get_current_completion_item() == nil then
		M.complete()
	else
		M.cycle_completions(1)
	end
end

return M

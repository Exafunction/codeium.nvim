local enums = require("codeium.enums")
local util = require("codeium.util")

local function utf8len(str)
	if str == "" or not str then
		return 0
	end
	-- TODO: Figure out how to convert the document encoding to UTF8 length
	-- Bonus points for doing it with raw codepoints instead of converting the
	-- string wholesale
	return string.len(str)
end

local function codeium_to_cmp(comp, offset, right_offset)
	local documentation = comp.completion.text
	local label = string.sub(documentation, offset, -(right_offset + 1))
	return {
		type = 1,
		documentation = label,
		label = label,
		insertText = label,
		cmp = {
			kind_text = "Codeium",
		},
	}
end

local Source = {
	server = nil,
}
Source.__index = Source

function Source:new(server)
	local o = {}
	setmetatable(o, self)

	o.server = server
	return o
end

function Source:is_available()
	return self.server.is_healthy()
end

function Source:get_position_encoding_kind()
	return "utf-8"
end

function Source:complete(params, callback)
	if self._cancel_previous_request then
		self._cancel_previous_request()
	end

	local context = params.context
	local offset = params.offset
	local cursor = context.cursor
	local bufnr = context.bufnr
	local filetype = enums.filetype_aliases[context.filetype] or context.filetype or "text"
	local language = enums.languages[filetype] or enums.languages.unspecified
	local after_line_length = string.len(context.cursor_before_line)
	local before_line = context.cursor_before_line
	local line_ending = util.get_newline(bufnr)
	local line_ending_len = utf8len(line_ending)
	local editor_options = util.get_editor_options(bufnr)

	-- We need to calculate the number of bytes prior to the current character,
	-- that starts with all the prior lines
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)

	-- For the current line, we want to exclude any extra characters that were
	-- entered after the popup displayed
	lines[cursor.row] = context.cursor_line

	-- We exclude the current line from the loop below, so add it's length here
	local cursor_offset = utf8len(before_line)
	for i = 1, (cursor.row - 1) do
		local line = lines[i]
		cursor_offset = cursor_offset + utf8len(line) + line_ending_len
	end

	-- Ensure that there is always a newline at the end of the file
	table.insert(lines, "")
	local text = table.concat(lines, line_ending)

	local pending_cancellation = nil
	local remove_event = nil
	local function cancel()
		if pending_cancellation then
			pending_cancellation()
			pending_cancellation = nil
		end
		if remove_event then
			remove_event()
			remove_event = nil
		end
	end

	remove_event = require("cmp").event:on("menu_closed", cancel)
	self._cancel_previous_request = cancel

	local function handle_completions(completion_items)
		local duplicates = {}
		local completions = {}
		for _, comp in ipairs(completion_items) do
			if not duplicates[comp.completion.text] then
				duplicates[comp.completion.text] = true
				table.insert(completions, codeium_to_cmp(comp, offset, after_line_length))
			end
		end
		callback(completions)
	end

	self.server.request_completion(
		{
			editor_language = filetype,
			language = language,
			cursor_offset = cursor_offset,
			text = text,
			line_ending = line_ending,
		},
		editor_options,
		function(success, json)
			cancel()

			if not success then
				callback(nil)
			end

			if json and json.state and json.state.state == "CODEIUM_STATE_SUCCESS" and json.completionItems then
				handle_completions(json.completionItems)
			else
				callback(nil)
			end
		end
	)
end

return Source

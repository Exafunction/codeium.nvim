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

local function codeium_to_cmp(comp, offset, before_line_length)
	local label = comp.completion.text
	return {
		type = 1,
		detail = label,
		documentation = label,
		label = string.sub(label, offset),
		insertText = string.sub(label, before_line_length),
		cmp = {
			kind_text = "Suggestion",
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
	local context = params.context
	local offset = params.offset
	local cursor = context.cursor
	local bufnr = context.bufnr
	local filetype = enums.filetype_aliases[context.filetype] or context.filetype or "text"
	local language = enums.languages[filetype] or enums.languages.unspecified
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
			if not success then
				callback(nil)
			end

			if json and json.state and json.state.state == "CODEIUM_STATE_SUCCESS" and json.completionItems then
				local completions = {}
				local before_line_length = string.len(before_line)
				for _, comp in ipairs(json.completionItems) do
					table.insert(completions, codeium_to_cmp(comp, offset, before_line_length))
				end
				callback(completions)
			else
				callback(nil)
			end
		end
	)
end

return Source

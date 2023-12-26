local enums = require("codeium.enums")
local util = require("codeium.util")

local function utf8len(str)
	if not str then
		return 0
	end
	-- TODO: Figure out how to convert the document encoding to UTF8 length
	-- Bonus points for doing it with raw codepoints instead of converting the
	-- string wholesale
	return str:len()
end

local function codeium_to_cmp(comp, offset, right)
	local documentation = comp.completion.text

	local label = documentation:sub(offset)
	if label:sub(- #right) == right then
		label = label:sub(1, - #right - 1)

	end

	-- We get the completion part that has the largest offset
	local max_offset = offset
	if comp.completionParts then
		for _, v in pairs(comp.completionParts) do
			local part_offset = tonumber(v.offset)
			if part_offset > max_offset then
				max_offset = part_offset
			end
		end
	end

	-- We get where the suffix difference between the completion and the range of code
	local suffix_diff = comp.range.endOffset - max_offset

	local range = {
		start = {
			-- Codeium returns an empty row for the first line
			line = (tonumber(comp.range.startPosition.row) or 0),
			character = offset - 1,
		},
		["end"] = {
			-- Codeium returns an empty row for the first line
			line = (tonumber(comp.range.endPosition.row) or 0),
			-- We only want to replace up to where the completion ends
			character = (comp.range.endPosition.col or suffix_diff) - suffix_diff,
		},
	}

	return {
		type = 1,
		documentation = {
			kind = "markdown",
			value = table.concat({
				"```" .. vim.api.nvim_buf_get_option(0, "filetype"),
				label,
				"```",
			}, "\n"),
		},
		label = label,
		insertText = label,
		textEdit = {
			newText = label,
			insert = range,
			replace = range,
		},
		cmp = {
			kind_text = "Codeium",
			kind_hl_group = "CmpItemKindCodeium",
		},
		codeium_completion_id = comp.completion.completionId,
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

require("cmp").event:on("confirm_done", function(event)
	if
		event.entry
		and event.entry.source
		and event.entry.source.name == "codeium"
		and event.entry.completion_item
		and event.entry.completion_item.codeium_completion_id
		and event.entry.source.source
		and event.entry.source.source.server
	then
		event.entry.source.source.server.accept_completion(event.entry.completion_item.codeium_completion_id)
	end
end)

function Source:complete(params, callback)
	local context = params.context
	local offset = params.offset
	local cursor = context.cursor
	local bufnr = context.bufnr
	local filetype = enums.filetype_aliases[context.filetype] or context.filetype or "text"
	local language = enums.languages[filetype] or enums.languages.unspecified
	local after_line = context.cursor_after_line
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

	local function handle_completions(completion_items)
		local duplicates = {}
		local completions = {}
		for _, comp in ipairs(completion_items) do
			if not duplicates[comp.completion.text] then
				duplicates[comp.completion.text] = true
				table.insert(completions, codeium_to_cmp(comp, offset, after_line))
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

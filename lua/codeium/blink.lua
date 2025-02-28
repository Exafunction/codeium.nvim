--- Module for the codeium completion source
local enums = require("codeium.enums")
local util = require("codeium.util")

--- @class blink.cmp.Source
--- @field server codeium.Server
local M = {}

local function utf8len(str)
	if not str then
		return 0
	end
	return str:len()
end

local function codeium_to_item(comp, offset, right)
	local documentation = comp.completion.text

	local insert_text = documentation:sub(offset)
	if insert_text:sub(-#right) == right then
		insert_text = insert_text:sub(1, -#right - 1)
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

	local display_label = string.match(insert_text, "([^\n]*)")
	if display_label ~= insert_text then
		display_label = display_label .. " "
	end

	return {
		label = display_label,
		insertText = insert_text,
		kind = require('blink.cmp.types').CompletionItemKind.Text,
		insertTextFormat = vim.lsp.protocol.InsertTextFormat.PlainText,
		kind_name = 'Codeium',
		kind_hl_group = 'BlinkCmpKindCopilot',
		kind_icon = '󰘦',
		textEdit = {
			newText = insert_text,
			insert = range,
			replace = range,
		},
	}
end

--- Resolve the completion item
function M:resolve(item, callback)
	item = vim.deepcopy(item)

	item.documentation = {
		kind = 'markdown',
		value = table.concat({
			"```" .. vim.api.nvim_get_option_value("filetype", {}),
			item.insertText,
			"```",
		}, "\n"),
	}

	callback(item)
end

function M.new()
	local o = {}
	o.server = require("codeium").s
	return setmetatable(o, { __index = M })
end

function M:get_trigger_characters()
	return { '"', "`", "[", "]", ".", " ", "\n" }
end
--
function M:enabled()
	return self.server.enabled
end

function M:get_completions(ctx, callback)
	local offset = ctx.bounds.start_col
	local cursor = ctx.cursor
	local bufnr = ctx.bufnr
	local filetype = vim.api.nvim_get_option_value("filetype", { buf = ctx.bufnr })
	filetype = enums.filetype_aliases[filetype] or filetype or "text"
	local language = enums.languages[filetype] or enums.languages.unspecified
	local after_line = string.sub(ctx.line, cursor[2])
	local before_line = string.sub(ctx.line, 1, cursor[2] - 1)
	local line_ending = util.get_newline(bufnr)
	local line_ending_len = utf8len(line_ending)
	local editor_options = util.get_editor_options(bufnr)

	-- We need to calculate the number of bytes prior to the current character,
	-- that starts with all the prior lines
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)

	-- For the current line, we want to exclude any extra characters that were
	-- entered after the popup displayed
	lines[cursor[1]] = ctx.line

	-- We exclude the current line from the loop below, so add it's length here
	local cursor_offset = utf8len(before_line)
	for i = 1, (cursor[1] - 1) do
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
				table.insert(completions, codeium_to_item(comp, offset, after_line))
			end
		end
		callback({
			is_incomplete_forward = false,
			is_incomplete_backward = false,
			items = completions,
			context = ctx,
		})
	end

	local other_documents = util.get_other_documents(bufnr)

	self.server:request_completion(
		{
			text = text,
			editor_language = filetype,
			language = language,
			cursor_position = { row = cursor[1] - 1, col = cursor[2] },
			absolute_uri = util.get_uri(vim.api.nvim_buf_get_name(bufnr)),
			workspace_uri = util.get_uri(util.get_project_root()),
			line_ending = line_ending,
			cursor_offset = cursor_offset,
		},
		editor_options,
		other_documents,
		function(success, json)
			if not success then
				return nil
			end

			if json and json.state and json.state.state == "CODEIUM_STATE_SUCCESS" and json.completionItems then
				handle_completions(json.completionItems)
			else
				return nil
			end
		end
	)
	return function() end
end

return M

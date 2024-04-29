local enums = require("codeium.enums")
local util = require("codeium.util")
---@class codeium.Chat
local chat = {}

function chat.intent_generic(text)
	return { text = text }
end

-- string raw_source = 1;
-- string clean_function = 2;
-- string docstring = 3;
-- string node_name = 4;
-- string params = 5;
-- int32 definition_line = 6;
-- int32 start_line = 7;
-- int32 end_line = 8;
-- int32 start_col = 9;
-- int32 end_col = 10;
-- string leading_whitespace = 11;
-- Language language = 12;
local function function_info()
	local bufnr = vim.api.nvim_get_current_buf()
	local filetype = enums.filetype_aliases[vim.bo[bufnr].filetype] or vim.bo[bufnr].filetype or "text"
	local language = enums.languages[filetype] or enums.languages.unspecified
	return {
		raw_source = "",
		clean_function = "",
		docstring = "",
		node_name = "",
		params = "",
		definition_line = 6,
		start_line = 7,
		end_line = 8,
		start_col = 9,
		end_col = 10,
		leading_whitespace = "",
		language = language
	}
end

---@return number
local function language()
	local bufnr = vim.api.nvim_get_current_buf()
	local filetype = enums.filetype_aliases[vim.bo[bufnr].filetype] or vim.bo[bufnr].filetype or "text"
	return enums.languages[filetype] or enums.languages.unspecified
end

-- string raw_source = 1;
--
-- // Start position of the code block.
-- int32 start_line = 2;
-- int32 start_col = 3;
--
-- // End position of the code block.
-- int32 end_line = 4;
-- int32 end_col = 5;
local function code_block_info()
	-- Get the current buffer
	local current_buffer = vim.api.nvim_get_current_buf()

	-- Get the start and end positions of the visual selection
	local start_line, start_col = unpack(vim.api.nvim_buf_get_mark(current_buffer, "<"))
	local end_line, end_col = unpack(vim.api.nvim_buf_get_mark(current_buffer, ">"))

	local lines = vim.api.nvim_buf_get_lines(current_buffer, start_line, end_line, true)
	local line_ending = util.get_newline(current_buffer)
	table.insert(lines, "")
	local text = table.concat(lines, line_ending)

	return { raw_source = text, start_line = start_line, start_col = start_col, end_line = end_line, end_col = end_col }
end


-- codeium_common_pb.FunctionInfo function_info = 1;
-- codeium_common_pb.Language language = 2;
-- string file_path = 3;
function chat.intent_function_explain()
	return { explain_function = { function_info = function_info(), language = language(), file_path = vim.api.nvim_buf_get_name(0) } }
end

-- codeium_common_pb.FunctionInfo function_info = 1;
-- codeium_common_pb.Language language = 2;
-- string file_path = 3;
-- string refactor_description = 4;
function chat.intent_function_refactor()
	local file_path = vim.api.nvim_buf_get_name(0)
	return { function_refactor = { function_info = function_info(), language = language(), file_path = file_path, refactor_description = "" } }
end

-- codeium_common_pb.FunctionInfo function_info = 1;
-- codeium_common_pb.Language language = 2;
-- string file_path = 3;
--
--  --Optional additional instructions to inform what tests to generate.
-- string instructions = 4;
function chat.intent_function_unit_tests()
	local prompt = vim.fn.input("Unit test instructions: ")
	local file_path = vim.api.nvim_buf_get_name(0)
	return { function_unit_tests = { function_info = function_info(), language = language(), file_path = file_path, instructions = prompt } }
end

--Ask for a docstring for a function.
-- codeium_common_pb.FunctionInfo function_info = 1;
-- codeium_common_pb.Language language = 2;
-- string file_path = 3;
function chat.intent_function_docstring()
	local file_path = vim.api.nvim_buf_get_name(0)
	return { function_docstring = { function_info = function_info(), language = language(), file_path = file_path } }
end

--Ask to explain a generic piece of code.
-- CodeBlockInfo code_block_info = 1;
-- codeium_common_pb.Language language = 2;
-- string file_path = 3;
function chat.intent_code_block_explain()
	local file_path = vim.api.nvim_buf_get_name(0)
	return { code_block_explain = { code_block_info = code_block_info(), language = language(), file_path = file_path } }
end

--Ask to refactor a generic piece of code.
-- CodeBlockInfo code_block_info = 1;
-- codeium_common_pb.Language language = 2;
-- string file_path = 3;
-- string refactor_description = 4;
function chat.intent_code_block_refactor()
	local file_path = vim.api.nvim_buf_get_name(0)
	return { code_block_refactor = { code_block_info = code_block_info(), language = language(), file_path = file_path, refactor_description = "" } }
end

--Ask to explain a problem.
-- string diagnostic_function chat.= 1;
-- CodeBlockInfo problematic_code = 2; //entire code block with error
-- string surrounding_code_snippet = 3;
-- codeium_common_pb.Language language = 4;
-- string file_path = 5;
-- int32 line_number = 6;
function chat.intent_problem_explain()
	local file_path = vim.api.nvim_buf_get_name(0)
	return {
		problem_explain = {
			diagnostic_function = "",
			problematic_code = code_block_info(),
			surrounding_code_snippet = "",
			language = language(),
			file_path = file_path,
			line_number = 0
		}
	}
end

--Ask to generate a piece of code.
-- string instruction = 1;
-- codeium_common_pb.Language language = 2;
-- string file_path = 3;
--  --Line to insert the generated code into.
-- int32 line_number = 4;
function chat.intent_generate_code()
	local prompt = vim.fn.input("Please add prompt:")
	local file_path = vim.api.nvim_buf_get_name(0)
	local line_number = vim.api.nvim_win_get_cursor(0)[1]
	return { generate_code = { instruction = prompt, language = language(), file_path = file_path, line_number = line_number } }
end

return chat

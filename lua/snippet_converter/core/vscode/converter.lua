local M = {}

local NodeType = require("snippet_converter.core.node_type")
local base_converter = require("snippet_converter.core.converter")
local err = require("snippet_converter.utils.error")
local io = require("snippet_converter.utils.io")
local export_utils = require("snippet_converter.utils.export_utils")
local json_utils = require("snippet_converter.utils.json_utils")

M.node_visitor = {
  [NodeType.TABSTOP] = function(node)
    if not node.transform then
      return "$" .. node.int
    end
    return ("${%s/%s}"):format(node.int, M.node_visitor[NodeType.TRANSFORM](node.transform))
  end,
  [NodeType.TRANSFORM] = function(node)
    -- Can currently only convert VSCode to VSCode regex
    if node.regex_kind ~= NodeType.RegexKind.JAVASCRIPT then
      err.raise_converter_error(
        NodeType.RegexKind.to_string(node.regex_kind) .. " regex in transform node"
      )
    end
    -- ASCII conversion option
    if node.options:match("a") then
      err.raise_converter_error("option 'a' (ascii conversion) in transform node")
    end
    -- Only g, i and m options are valid - ignore the rest
    local converted_options = node.options:gsub("[^gim]", "")

    local replacements = {}
    for i, replacement in pairs(replacements) do
      -- Text or format nodes
      replacements[i] = M.node_visitor[replacement.type](replacement)
    end
    return ("%s/%s/%s"):format(node.regex, table.concat(replacements), converted_options)
  end,
  [NodeType.FORMAT] = function(node)
    if not node.format_modifier then
      return "$" .. node.int
    end
    -- TODO: handle if / else
    return ("${%s:/}"):format(node.format_modifier)
  end,
  [NodeType.VISUAL_PLACEHOLDER] = function(_)
    err.raise_converter_error(NodeType.to_string(NodeType.VISUAL_PLACEHOLDER))
  end,
}

M.visit_node = setmetatable(M.node_visitor, {
  __index = base_converter.visit_node(M.node_visitor),
})

---Creates package.json file contents as expected by VSCode and Luasnip.
---@name string the name that will be added at the top of the output
---@filetypes array an array of filetypes that determine the path attribute
---@param langs_for_filetype table<string, table> maps a relative path to a snippet to an array of supported languages for that file.
---@return string the generated string to be written
local get_package_json_string = function(name, filetypes, langs_for_filetype)
  local snippets = {}
  for i, filetype in ipairs(filetypes) do
    snippets[i] = {
      language = langs_for_filetype[filetype],
      path = ("./%s.json"):format(filetype),
    }
  end
  return json_utils:pretty_print(snippets, function(key_a, _)
    return key_a == "name" or key_a == "description" or key_a == "contributes"
  end)
end

-- TODO: remove source_format parameter
M.convert = function(snippet, _, visit_node)
  if snippet.options and snippet.options:match("r") then
    err.raise_converter_error("regex trigger")
  end
  -- Prepare snippet for export
  snippet.body = vim.split(
    base_converter.convert_ast(snippet.body, visit_node or M.visit_node),
    "\n"
  )
  if #snippet.body == 1 then
    snippet.body = snippet.body[1]
  end
  snippet.scope = snippet.scope and table.concat(snippet.scope, ",")
  return snippet
end

-- Takes a list of converted snippets for a particular filetype and exports them to a JSON file.
-- @param converted_snippets table[] @A list of strings where each item is a snippet string to be exported
-- @param filetype string @The filetype of the snippets
-- @param output_dir string @The absolute path to the directory to write the snippets to
M.export = function(converted_snippets, filetype, output_path)
  local table_to_export = {}
  for _, snippet in ipairs(converted_snippets) do
    -- Ignore any other fields
    table_to_export[snippet.name or snippet.trigger] = {
      prefix = snippet.trigger,
      description = snippet.description,
      scope = snippet.scope,
      body = snippet.body,
    }
  end
  local output_string = json_utils:pretty_print(table_to_export, function(key, _)
    return key == "prefix" or key == "description" or key == "scope"
  end, true)
  output_path = export_utils.get_output_file_path(output_path, filetype, "json")
  io.write_file(vim.split(output_string, "\n"), output_path)
end

M.post_export = function(template, filetypes, output_path)
  local json_string = get_package_json_string(template.name, filetypes, { lua = { "lua" } })
  local lines = export_utils.snippet_strings_to_lines { json_string }
  -- TODO: check that output_path is a folder
  io.write_file(lines, output_path .. "/package.json")
end

return M

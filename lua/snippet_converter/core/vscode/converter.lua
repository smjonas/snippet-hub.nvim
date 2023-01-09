local M = {}

local NodeType = require("snippet_converter.core.node_type")
local base_converter = require("snippet_converter.core.converter")
local err = require("snippet_converter.utils.error")
local io = require("snippet_converter.utils.io")
local tbl = require("snippet_converter.utils.table")
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
    -- YASnippet snippets only specify a replacement attribute
    if not node.regex then
      err.raise_converter_error("YASnippet transform node")
    end
    -- Can currently only convert VSCode to VSCode regex
    if node.regex_kind ~= NodeType.RegexKind.JAVASCRIPT then
      err.raise_converter_error(NodeType.RegexKind.to_string(node.regex_kind) .. " regex in transform node")
    end
    -- ASCII conversion option
    if node.options:match("a") then
      err.raise_converter_error("option 'a' (ascii conversion) in transform node")
    end
    -- Only g, i and m options are valid - ignore the rest
    local converted_options = node.options:gsub("[^gim]", "")

    local replacements = {}
    for i, replacement in ipairs(node.replacement) do
      -- Text or format nodes
      replacements[i] = M.node_visitor[replacement.type](replacement)
    end
    return ("%s/%s/%s"):format(node.regex, table.concat(replacements), converted_options)
  end,
  [NodeType.FORMAT] = function(node)
    if not node.format_modifier then
      if not (node.if_text or node.else_text) then
        return "$" .. node.int
      end
      if node.if_text and node.else_text then
        return ("${%s:?%s:%s}"):format(node.int, node.if_text, node.else_text)
      elseif node.if_text then
        return ("${%s:+%s}"):format(node.int, node.if_text)
      else
        return ("${%s:-%s}"):format(node.int, node.else_text)
      end
    end
    return ("${%s:/%s}"):format(node.int, node.format_modifier)
  end,
  [NodeType.CHOICE] = function(node)
    return ("${%s|%s|}"):format(node.int, table.concat(node.text, ","))
  end,
  [NodeType.VARIABLE] = function(node, opts)
    -- Don't convert variable to Vimscript when the target flavor is luasnip
    if opts.flavor == "luasnip" then
      if node.transform then
        err.raise_converter_error("transform")
      end
      if node.any then
        local any = base_converter.convert_ast(node.any, M.node_visitor, opts)
        return string.format("${%s:%s}", node.var, any)
      end
      return ("${%s}"):format(node.var)
    end
    return base_converter.visit_node(M.node_visitor)
  end,
  [NodeType.VISUAL_PLACEHOLDER] = function(node)
    if not node.text then
      return "$TM_SELECTED_TEXT"
    end
    return "${VISUAL_PLACEHOLDER}"
  end,
  [NodeType.TEXT] = function(node)
    -- Escape '$' and '}' characters (see https://code.visualstudio.com/docs/editor/userdefinedsnippets#_grammar)
    return node.text:gsub("[%$}]", "\\%1")
  end,
}

M.visit_node = setmetatable(M.node_visitor, {
  __index = base_converter.visit_node(M.node_visitor),
})

---Creates package.json file contents as expected by VSCode and Luasnip.
---@name string the name that will be added at the top of the output
---@filetypes array an array of filetypes that determine the language and path attribute
---@langs_per_filetype table<string, table<string>> maps a filetype to a list of language that this filetype should be active for
---@return string the generated string to be written
local get_package_json_string = function(name, filetypes, langs_per_filetype)
  local snippets = {}
  for i, ft in ipairs(filetypes) do
    snippets[i] = {
      language = langs_per_filetype[ft] or { ft },
      path = ("./%s.json"):format(ft),
    }
  end
  local package_json = {
    name = name,
    description = "Generated by snippet-converter.nvim (https://github.com/smjonas/snippet-converter.nvim)",
    contributes = {
      snippets = snippets,
    },
  }
  return json_utils:pretty_print(
    package_json,
    { { "name", "description", "contributes" }, { "language", "path" } },
    true
  )
end

-- Expose to tests
M._get_package_json_string = get_package_json_string

--TODO: from UltiSnips: $VISUAL with transform
M.convert = function(snippet, visit_node, opts)
  opts = opts or {}
  if snippet.options and snippet.options:match("r") then
    err.raise_converter_error("regex trigger")
  end
  -- Prepare snippet for export
  snippet.body = vim.split(base_converter.convert_ast(snippet.body, visit_node or M.visit_node, opts), "\n")
  if #snippet.body == 1 then
    snippet.body = snippet.body[1]
  end
  snippet.scope = snippet.scope and table.concat(snippet.scope, ",")

  if opts.flavor == "luasnip" then
    snippet.luasnip = tbl.make_default_table({}, "luasnip")
    if snippet.autotrigger or snippet.options and snippet.options:match("A") then
      snippet.luasnip.autotrigger = true
    end
    if snippet.priority then
      snippet.luasnip.priority = snippet.priority
    end
    if vim.tbl_isempty(snippet.luasnip) then
      -- Delete if empty
      snippet.luasnip = nil
    end
  end
  return snippet
end

-- Takes a list of converted snippets for a particular filetype and exports them to a JSON file.
-- @param converted_snippets table[] #A list of strings where each item is a snippet string to be exported
-- @param filetypes string #The filetypes of the snippets
-- @param output_dir string #The absolute path to the directory to write the snippets to
---@return string output path
M.export = function(converted_snippets, filetypes, output_dir, _)
  local table_to_export = {}
  local order = { [1] = {}, [2] = { "prefix", "description", "scope", "body", "luasnip" } }
  for i, snippet in ipairs(converted_snippets) do
    local key = snippet.name or snippet.trigger
    order[1][i] = key
    -- Ignore any other fields
    table_to_export[key] = {
      prefix = snippet.trigger,
      description = snippet.description,
      scope = snippet.scope,
      body = snippet.body,
      luasnip = snippet.luasnip,
    }
  end
  local output_string = json_utils:pretty_print(table_to_export, order, true)
  local output_path = ("%s/%s.%s"):format(output_dir, filetypes, "json")
  io.write_file(vim.split(output_string, "\n"), output_path)
  return output_path
end

-- @param context []? @A table of additional snippet contexts optionally provided the source parser (e.g. extends directives from UltiSnips)
M.post_export = function(template_name, filetypes, output_path, context, template_opts)
  if template_opts and not template_opts.generate_package_json then
    return
  end

  filetypes = vim.tbl_filter(function(ft)
    return ft ~= "package"
  end, filetypes)

  local json_string = get_package_json_string(template_name, filetypes, context.langs_per_filetype or {})
  local lines = export_utils.snippet_strings_to_lines { json_string }
  io.write_file(lines, io.get_containing_folder(output_path) .. "/package.json")
end

return M

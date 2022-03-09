local parser = require("snippet_converter.core.ultisnips.body_parser")
local NodeType = require("snippet_converter.core.node_type")

describe("UltiSnips body parser", function()
  it("should parse tabstop and placeholder", function()
    local input = "local ${1:name} = function($2)"
    local expected = {
      { text = "local ", type = NodeType.TEXT },
      {
        int = "1",
        any = { { text = "name", type = NodeType.TEXT } },
        type = NodeType.PLACEHOLDER,
      },
      { text = " = function(", type = NodeType.TEXT },
      { int = "2", type = NodeType.TABSTOP },
      { text = ")", type = NodeType.TEXT },
    }
    assert.are_same(expected, parser.parse(input))
  end)

  it("should parse choice element", function()
    local input = "${0|🠂,⇨|}"
    local expected = {
      { int = "0", text = { "🠂", "⇨" }, type = NodeType.CHOICE },
    }
    assert.are_same(expected, parser.parse(input))
  end)

  it("should parse escaped chars in text element", function()
    local input = [[\`\{\$\\]]
    local expected = { { text = [[`{$\]], type = NodeType.TEXT } }
    assert.are_same(expected, parser.parse(input))
  end)

  it("should parse multiple lines starting with backslash", function()
    local input = [[
\pdfminorversion=7
\usepackage{pdfpages}
\usepackage{transparent}]]
    local expected = {
      {
        text = "\\pdfminorversion=7\n\\usepackage{pdfpages}\n\\usepackage{transparent}",
        type = NodeType.TEXT,
      },
    }
    assert.are_same(expected, parser.parse(input))
  end)

  it("should parse unambiguous unescaped chars", function()
    local input = [[${\cup}$]]
    local expected = {
      {
        -- $ does not need to be escaped because it does not mark the beginning of a tabstop
        text = [[${\cup}$]],
        type = NodeType.TEXT,
      },
    }
    assert.are_same(expected, parser.parse(input))
  end)

  it("should parse python code", function()
    local input = [[`!p print("hello world")`]]
    local expected = { { code = [[print("hello world")]], type = NodeType.PYTHON_CODE } }
    assert.are_same(expected, parser.parse(input))
  end)

  it("should parse placeholder with curly braces", function()
    local input = [[${2:{}}abc]]
    local expected = {
      {
        type = NodeType.PLACEHOLDER,
        int = "2",
        any = { { type = NodeType.TEXT, text = "{}" } },
      },
      { type = NodeType.TEXT, text = "abc" },
    }
    assert.are_same(expected, parser.parse(input))
  end)

  it("should parse incomplete placeholder as placeholder with empty text node", function()
    local input = [[${2:]]
    local expected = {
      {
        type = NodeType.PLACEHOLDER,
        int = "2",
        any = { type = NodeType.TEXT, text = "" },
      },
    }
    assert.are_same(expected, parser.parse(input))
  end)

  it("should parse visual placeholder with default text", function()
    local input = [[${VISUAL:default}]]
    local expected = { { text = "default", type = NodeType.VISUAL_PLACEHOLDER } }
    assert.are_same(expected, parser.parse(input))
  end)

  it("should parse tabstop inside literal {$...$} text block", function()
    local input = [[{$${1}$}]]
    local expected = {
      {
        text = "{$",
        type = NodeType.TEXT,
      },
      {
        int = "1",
        type = NodeType.TABSTOP,
      },
      {
        text = "$}",
        type = NodeType.TEXT,
      },
    }
    assert.are_same(expected, parser.parse(input))
  end)

  it("should parse transformation", function()
    local input = [[${1/\w+\s*/\u$0/}]]
    local expected = {
      {
        int = "1",
        transform = {
          regex = [[\w+\s*]],
          replacement = [[\u$0]],
          options = "",
          type = NodeType.TRANSFORM,
        },
        type = NodeType.TABSTOP,
      },
    }
    assert.are_same(expected, parser.parse(input))
  end)

  it("should parse placeholder with multiple nested nodes", function()
    local input = [[${3:else success(${4:ok, err})} end)]]
    local expected = {
      {
        int = "3",
        any = {
          { text = "else success(", type = NodeType.TEXT },
          {
            int = "4",
            any = { { text = "ok, err", type = NodeType.TEXT } },
            type = NodeType.PLACEHOLDER,
          },
          { text = ")", type = NodeType.TEXT },
        },
        type = NodeType.PLACEHOLDER,
      },
      {
        text = " end)",
        type = NodeType.TEXT,
      },
    }
    assert.are_same(expected, parser.parse(input))
  end)

  it("should not throw invalid index error when merging", function()
    local input = [[
\begin{$1}
  x
\end{$1}]]
    local ok, _ = pcall(parser.parse, input)
    assert.is_true(ok)
  end)
end)

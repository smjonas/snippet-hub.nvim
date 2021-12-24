local converter = {}

function converter.create()
  local self = setmetatable({}, { __index = converter })
  return self
end

function converter.convert(snippet)
  local description = ""
  if snippet.description then
    description = " " .. snippet.description
  end
  return string.format(
    "snippet %s%s\n%s\nendsnippet\n\n",
    snippet.trigger,
    description,
    snippet.body
  )
end

return converter

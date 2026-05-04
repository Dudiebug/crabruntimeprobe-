local log = {}

local function normalize(message)
  local text = tostring(message or '')
  text = text:gsub('[\r\n]+$', '')
  return text
end

function log.line(message)
  print(normalize(message) .. '\n')
end

return log

local json = require('json')
local writer = { file = nil }

local function openResult(path)
  local f = io.open(path, 'a')
  if f then return f end
  return io.open('probe_results.jsonl', 'a')
end

function writer.init(sessionId)
  writer.file = openResult('results/probe_results_' .. sessionId .. '.jsonl')
end

function writer.write(row)
  if not writer.file then return end
  writer.file:write(json.encode(row) .. '\n')
  writer.file:flush()
end

return writer

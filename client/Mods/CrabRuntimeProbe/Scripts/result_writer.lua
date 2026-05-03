local json = require('json')
local writer = {}

local function utcNow()
  return os.date('!%Y-%m-%dT%H:%M:%SZ')
end

local function appendLine(path, line)
  local f = io.open(path, 'a')
  if not f then return false end
  f:write(line .. '\n')
  f:close()
  return true
end

function writer.new(sessionId, config)
  local o = {
    sessionId = sessionId,
    config = config,
    resultPath = 'results/probe_results_' .. sessionId .. '.jsonl',
    fallbackPath = 'probe_results_' .. sessionId .. '.jsonl'
  }

  function o:write(record)
    record.timestamp = record.timestamp or utcNow()
    record.sessionId = self.sessionId
    local line = json.encode(record)
    if not appendLine(self.resultPath, line) then
      appendLine(self.fallbackPath, line)
    end
  end

  return o
end

return writer

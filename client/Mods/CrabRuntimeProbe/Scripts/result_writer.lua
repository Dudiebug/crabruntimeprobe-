local json = require('json')
local writer = {}

local function utcNow()
  return os.date('!%Y-%m-%dT%H:%M:%SZ')
end

local function appendLine(path, line)
  local f = io.open(path, 'a')
  if f then
    f:write(line .. '\n')
    f:close()
    return true
  end

  if io and type(io.writefile) == 'function' then
    local ok = pcall(function()
      io.writefile(path, line .. '\n', true)
    end)
    return ok == true
  end

  return false
end

function writer.new(sessionId, config)
  local o = {
    sessionId = sessionId,
    config = config,
    resultPath = 'Mods/CrabRuntimeProbe/Scripts/results/probe_results_' .. sessionId .. '.jsonl',
    fallbackPath = 'Mods/CrabRuntimeProbe/Scripts/probe_results_' .. sessionId .. '.jsonl'
  }

  function o:write(record)
    if self.config.writeJsonlResults == false then return true end
    record.timestamp = record.timestamp or utcNow()
    record.sessionId = self.sessionId
    local line = json.encode(record)
    if not appendLine(self.resultPath, line) then
      return appendLine(self.fallbackPath, line)
    end
    return true
  end

  return o
end

return writer

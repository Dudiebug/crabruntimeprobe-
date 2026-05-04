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
  return false
end

function writer.new(sessionId, config)
  local o = {
    sessionId = sessionId,
    config = config,
    resultPath = 'Mods/CrabRuntimeProbe/Scripts/results/probe_results_' .. sessionId .. '.jsonl',
    fallbackPath = 'Mods/CrabRuntimeProbe/Scripts/probe_results_' .. sessionId .. '.jsonl',
    warnedFallback = false,
    warnedFailure = false
  }

  function o:write(record)
    if self.config.writeJsonlResults == false then return true end
    record.timestamp = record.timestamp or utcNow()
    record.sessionId = self.sessionId
    local line = json.encode(record)
    if not appendLine(self.resultPath, line) then
      if appendLine(self.fallbackPath, line) then
        if not self.warnedFallback then
          print('[CrabRuntimeProbe] primary result path unavailable; using fallback')
          self.warnedFallback = true
        end
        return true
      end
      if not self.warnedFailure then
        print('[CrabRuntimeProbe] ERROR: result write failed for primary and fallback')
        self.warnedFailure = true
      end
      return false
    end
    return true
  end

  return o
end

return writer

local crpLog = require('crp_log')
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

local function tryCreateDirectory(path)
  if type(os.execute) ~= 'function' then return end
  pcall(function()
    os.execute('if not exist "' .. path .. '" mkdir "' .. path .. '"')
  end)
end

function writer.new(sessionId, config)
  local o = {
    sessionId = sessionId,
    config = config,
    resultDir = 'Mods/CrabRuntimeProbe/Scripts/results',
    resultPath = 'Mods/CrabRuntimeProbe/Scripts/results/probe_results_' .. sessionId .. '.jsonl',
    fallbackPath = 'Mods/CrabRuntimeProbe/Scripts/probe_results_' .. sessionId .. '.jsonl',
    triedCreateResultDir = false,
    warnedFallback = false,
    warnedFailure = false
  }

  function o:write(record)
    if self.config.writeJsonlResults == false then return true end
    record.timestamp = record.timestamp or utcNow()
    record.sessionId = self.sessionId
    local line = json.encode(record)
    if not self.triedCreateResultDir then
      tryCreateDirectory(self.resultDir)
      self.triedCreateResultDir = true
    end
    if not appendLine(self.resultPath, line) then
      if appendLine(self.fallbackPath, line) then
        if not self.warnedFallback then
          crpLog.line('[CrabRuntimeProbe] primary result path unavailable; using fallback')
          self.warnedFallback = true
        end
        return true
      end
      if not self.warnedFailure then
        crpLog.line('[CrabRuntimeProbe] ERROR: result write failed for primary and fallback')
        self.warnedFailure = true
      end
      return false
    end
    return true
  end

  return o
end

return writer

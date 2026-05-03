package.path = package.path .. ';./?.lua'
local runner = require('probe_runner')
local writer = require('result_writer')

local function log(msg)
  print(msg)
end

local function readConfig(path)
  local cfg = {}
  for line in io.lines(path) do
    local k, v = line:match('^%s*([%w_]+)%s*=%s*(.-)%s*$')
    if k then
      if v == 'true' then cfg[k] = true
      elseif v == 'false' then cfg[k] = false
      elseif tonumber(v) then cfg[k] = tonumber(v)
      else cfg[k] = v end
    end
  end
  return cfg
end

local config = readConfig('config.txt')
if not config.enabled then return end

local sessionId = tostring(os.time())
writer.init(sessionId)
runner.init(config)

local state = { sessionId = sessionId, role = 'unknown', inMenu = true }
for _ = 1, config.maxProbesPerSession * config.probeIntervalTicks + config.startupWarmupTicks do
  local row = runner.step(state, log)
  if row and config.writeJsonlResults then writer.write(row) end
end

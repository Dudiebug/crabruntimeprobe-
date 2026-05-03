local safe = require('safe_access')
local runtime = require('runtime_context')
local registry = require('probe_registry')
local runner = require('probe_runner')
local writer = require('result_writer')

local function parseConfig(path)
  local cfg = {}
  local f = io.open(path, 'r')
  if not f then return cfg end
  for line in f:lines() do
    line = line:gsub('#.*$', '')
    local k, v = line:match('^%s*([%w_]+)%s*=%s*(.-)%s*$')
    if k then
      if v == 'true' then cfg[k] = true
      elseif v == 'false' then cfg[k] = false
      elseif tonumber(v) then cfg[k] = tonumber(v)
      else cfg[k] = v end
    end
  end
  f:close()
  return cfg
end

local config = parseConfig('Mods/CrabRuntimeProbe/Scripts/config.txt')
if config.enabled == false then return end
local state = { tick = 0, traveling = false, dead = false }
local sessionId = tostring(os.time())
local resultPath = 'Mods/CrabRuntimeProbe/Scripts/results/probe_results_' .. sessionId .. '.jsonl'
local crumbPath = 'Mods/CrabRuntimeProbe/Scripts/results/breadcrumbs_' .. sessionId .. '.log'
local probes = registry.sets[config.probeSet or 'shallow-core'] or registry.sets['shallow-core']
local probeIndex = 1

RegisterTick(function()
  state.tick = state.tick + 1
  if state.tick < (config.startupWarmupTicks or 60) then return end
  local context, role = runtime.detect(safe, state)
  if config.mode == 'observe' then
    writer.writeResult(resultPath, {timestamp=os.date('!%Y-%m-%dT%H:%M:%SZ'),sessionId=sessionId,tick=state.tick,mode='observe',probeId='Observe.Core',context=context,role=role,result='ok',valueKind='state',valueSummary='passive sample'})
    return
  end
  if probeIndex > #probes or probeIndex > (config.maxProbesPerSession or 100) then return end
  if state.tick % (config.probeIntervalTicks or 10) ~= 0 then return end
  local probeId = probes[probeIndex]
  local run, reason = runner.shouldRunProbe(config, probeId, context)
  writer.breadcrumb(crumbPath, 'enter ' .. probeId)
  local result = run and 'ok' or reason
  writer.writeResult(resultPath, {timestamp=os.date('!%Y-%m-%dT%H:%M:%SZ'),sessionId=sessionId,tick=state.tick,mode='active',probeId=probeId,context=context,role=role,result=result})
  writer.breadcrumb(crumbPath, 'exit ' .. probeId .. ' result=' .. result)
  probeIndex = probeIndex + 1
end)

local SCRIPT_DIR = 'Mods/CrabRuntimeProbe/Scripts/'
package.path = package.path .. ';' .. SCRIPT_DIR .. '?.lua'

local crpLog = require('crp_log')
local writerFactory = require('result_writer')
local evidenceWriterFactory = require('evidence_writer')

local DEFAULT_CONFIG = {
  enabled = true,
  mode = 'observe',
  tickDriver = 'none',
  debugBreadcrumbs = true,
  debugTickHeartbeat = false,
  debugWriterSelfTest = false,
  allowHudTickHook = false,
  writeJsonlResults = true,
  writeMarkdownSnapshots = false,
  observeIntervalTicks = 10,
  probeIntervalTicks = 10,
  startupWarmupTicks = 60,
  contextStableTicksRequired = 10,
  maxProbesPerSession = 100,
  repeatProbeSet = false,
  allowUnknownRoleProbes = false,
  allowJoinedClientDeepProbes = false,
  allowDeepArrayProbes = false,
  allowInventoryInfoProbes = false,
  allowHealthProbes = false,
  allowWriteProbes = false,
  allowRpcProbes = false,
  probeSet = 'shallow-core'
}

local ALLOWED_TICK_DRIVERS = {
  none = true,
  registerTick = true,
  executeDelay = true,
  loopAsync = true,
  hud = true
}

local log = crpLog.line

local function parseConfig(path)
  local config = {}
  for k, v in pairs(DEFAULT_CONFIG) do
    config[k] = v
  end

  local f = io.open(path, 'r')
  if not f then
    return config
  end

  for line in f:lines() do
    local cleaned = line:gsub('%s*#.*$', '')
    local k, v = cleaned:match('^%s*([%w_]+)%s*=%s*(.-)%s*$')
    if k and v then
      if v == 'true' then v = true
      elseif v == 'false' then v = false
      elseif tonumber(v) ~= nil then v = tonumber(v)
      end
      config[k] = v
    end
  end

  f:close()
  return config
end

local function writeStartupRecord(writer, cfg, eventName, summary)
  return writer:write({
    event = eventName,
    tick = 0,
    mode = cfg.mode,
    tickDriver = tostring(cfg.tickDriver),
    probeId = eventName,
    probeName = eventName,
    category = 'debug',
    context = 'startup',
    role = 'unknown',
    lifecycleState = 'startup',
    result = 'ok',
    valueKind = 'startup',
    valueSummary = summary,
    error = ''
  })
end

local function readBuildInfo(path)
  local lines = {}
  local f = io.open(path, 'r')
  if not f then
    return lines
  end
  for line in f:lines() do
    lines[#lines + 1] = line
    if #lines >= 8 then break end
  end
  f:close()
  return lines
end

local cfg = parseConfig(SCRIPT_DIR .. 'config.txt')
log('[CrabRuntimeProbe] boot phase: config loaded')

if cfg.enabled == false then
  log('[CrabRuntimeProbe] disabled in config')
  return
end

if type(cfg.tickDriver) ~= 'string' or ALLOWED_TICK_DRIVERS[cfg.tickDriver] ~= true then
  log('[CrabRuntimeProbe] ERROR: invalid tickDriver=' .. tostring(cfg.tickDriver))
  return
end

local sessionId = os.date('!%Y%m%dT%H%M%SZ')
local writer = writerFactory.new(sessionId, cfg)
local evidenceWriter = evidenceWriterFactory.new(sessionId, cfg)
log('[CrabRuntimeProbe] boot phase: writer initialized')

log('[CrabRuntimeProbe] started session=' .. sessionId .. ' mode=' .. tostring(cfg.mode))
log('[CrabRuntimeProbe] config path=Mods/CrabRuntimeProbe/Scripts/config.txt')
log('[CrabRuntimeProbe] mode=' .. tostring(cfg.mode))
log('[CrabRuntimeProbe] tickDriver=' .. tostring(cfg.tickDriver))
local buildInfoLines = readBuildInfo(SCRIPT_DIR .. 'build_info.txt')
if #buildInfoLines == 0 then
  log('[CrabRuntimeProbe] build info unavailable')
else
  for _, line in ipairs(buildInfoLines) do
    log('[CrabRuntimeProbe] build ' .. tostring(line))
  end
end
evidenceWriter:writeSessionManifest(buildInfoLines)
log('[CrabRuntimeProbe] safety allowHudTickHook=' .. tostring(cfg.allowHudTickHook)
  .. ' allowDeepArrayProbes=' .. tostring(cfg.allowDeepArrayProbes)
  .. ' allowInventoryInfoProbes=' .. tostring(cfg.allowInventoryInfoProbes)
  .. ' allowHealthProbes=' .. tostring(cfg.allowHealthProbes)
  .. ' allowWriteProbes=' .. tostring(cfg.allowWriteProbes)
  .. ' allowRpcProbes=' .. tostring(cfg.allowRpcProbes))
log('[CrabRuntimeProbe] results primary=' .. tostring(writer.resultPath))
log('[CrabRuntimeProbe] results fallback=' .. tostring(writer.fallbackPath))
log('[CrabRuntimeProbe] evidence primary=' .. tostring(evidenceWriter.evidencePath))
log('[CrabRuntimeProbe] evidence fallback=' .. tostring(evidenceWriter.fallbackEvidencePath))

log('[CrabRuntimeProbe] boot phase: startup smoke write begin')
writeStartupRecord(writer, cfg, 'Debug.StartupSmoke', 'startup smoke')
log('[CrabRuntimeProbe] boot phase: startup smoke write complete')

if cfg.debugWriterSelfTest == true then
  writeStartupRecord(writer, cfg, 'Debug.WriterSelfTest', 'writer self-test')
end

log('[CrabRuntimeProbe] boot phase: tick driver decision')

if cfg.tickDriver == 'none' then
  log('[CrabRuntimeProbe] tick driver disabled: none')
  log('[CrabRuntimeProbe] startup smoke complete')
  log('[CrabRuntimeProbe] boot phase: startup complete')
  return
end

local safe = require('safe_access')
local runner = require('probe_runner')
local state = runner.new(cfg, safe, writer, evidenceWriter)

local function tickOnce()
  local ok, err = pcall(function()
    state:onTick()
  end)
  if not ok then
    log('[CrabRuntimeProbe] tick error: ' .. tostring(err))
  end
end

local function registerSelectedTickDriver(driver)
  log('[CrabRuntimeProbe] boot phase: tick registration begin')
  log('[CrabRuntimeProbe] tick driver register begin: ' .. tostring(driver))

  if driver == 'registerTick' then
    if type(RegisterTick) ~= 'function' then
      log('[CrabRuntimeProbe] tick driver unavailable: registerTick')
      return false
    end
    RegisterTick(function()
      tickOnce()
    end)
  elseif driver == 'executeDelay' then
    if type(ExecuteWithDelay) ~= 'function' then
      log('[CrabRuntimeProbe] tick driver unavailable: executeDelay')
      return false
    end
    local function scheduleDelayedTick()
      ExecuteWithDelay(100, function()
        tickOnce()
        scheduleDelayedTick()
      end)
    end
    scheduleDelayedTick()
  elseif driver == 'loopAsync' then
    if type(LoopAsync) ~= 'function' then
      log('[CrabRuntimeProbe] tick driver unavailable: loopAsync')
      return false
    end
    LoopAsync(100, function()
      tickOnce()
      return true
    end)
  elseif driver == 'hud' then
    if cfg.allowHudTickHook ~= true then
      log('[CrabRuntimeProbe] tick driver blocked by allowHudTickHook=false: hud')
      return false
    end
    if type(RegisterHook) ~= 'function' then
      log('[CrabRuntimeProbe] tick driver unavailable: hud')
      return false
    end
    RegisterHook('/Script/Engine.HUD:ReceiveDrawHUD', function()
      tickOnce()
    end)
  end

  log('[CrabRuntimeProbe] tick source registered: ' .. tostring(driver))
  log('[CrabRuntimeProbe] boot phase: tick registration complete')
  return true
end

local ok, registeredOrError = pcall(function()
  return registerSelectedTickDriver(cfg.tickDriver)
end)

if not ok then
  log('[CrabRuntimeProbe] ERROR: tick driver registration failed: ' .. tostring(registeredOrError))
  return
end

if registeredOrError ~= true then
  log('[CrabRuntimeProbe] boot phase: startup complete')
  return
end

log('[CrabRuntimeProbe] boot phase: startup complete')

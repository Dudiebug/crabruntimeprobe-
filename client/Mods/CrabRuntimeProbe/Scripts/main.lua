local SCRIPT_DIR = 'Mods/CrabRuntimeProbe/Scripts/'
package.path = package.path .. ';' .. SCRIPT_DIR .. '?.lua'

local safe = require('safe_access')
local runner = require('probe_runner')
local writerFactory = require('result_writer')

local DEFAULT_CONFIG = {
  enabled = true,
  mode = 'observe',
  debugBreadcrumbs = true,
  debugTickHeartbeat = false,
  debugWriterSelfTest = false,
  writeJsonlResults = true,
  writeMarkdownSnapshots = false,
  observeIntervalTicks = 10,
  probeIntervalTicks = 10,
  startupWarmupTicks = 60,
  contextStableTicksRequired = 10,
  maxProbesPerSession = 100,
  allowUnknownRoleProbes = false,
  allowJoinedClientDeepProbes = false,
  allowDeepArrayProbes = false,
  allowInventoryInfoProbes = false,
  allowHealthProbes = false,
  allowWriteProbes = false,
  allowRpcProbes = false,
  probeSet = 'shallow-core'
}

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

local cfg = parseConfig(SCRIPT_DIR .. 'config.txt')
if cfg.enabled == false then
  print('[CrabRuntimeProbe] disabled in config')
  return
end

local sessionId = os.date('!%Y%m%dT%H%M%SZ')
local writer = writerFactory.new(sessionId, cfg)
local state = runner.new(cfg, safe, writer)

print('[CrabRuntimeProbe] started session=' .. sessionId .. ' mode=' .. tostring(cfg.mode))
print('[CrabRuntimeProbe] config path=Mods/CrabRuntimeProbe/Scripts/config.txt')
print('[CrabRuntimeProbe] mode=' .. tostring(cfg.mode))
print('[CrabRuntimeProbe] results primary=' .. tostring(writer.resultPath))
print('[CrabRuntimeProbe] results fallback=' .. tostring(writer.fallbackPath))

if cfg.debugWriterSelfTest == true then
  writer:write({
    tick = 0,
    mode = cfg.mode,
    probeId = 'Debug.WriterSelfTest',
    probeName = 'Debug.WriterSelfTest',
    category = 'debug',
    context = 'startup',
    role = 'unknown',
    lifecycleState = 'startup',
    result = 'ok',
    valueKind = '',
    valueSummary = 'writer self-test',
    error = ''
  })
end

if type(RegisterHook) == 'function' then
  pcall(function()
    RegisterHook('/Script/Engine.PlayerController:ClientRestart', function()
      print('[CrabRuntimeProbe][hook] ClientRestart')
    end)
  end)
end

local function tickOnce()
  local ok, err = pcall(function()
    state:onTick()
  end)
  if not ok then
    print('[CrabRuntimeProbe] tick error: ' .. tostring(err))
  end
end

local tickRegistered = false

if type(RegisterHook) == 'function' then
  local okHud = pcall(function()
    RegisterHook('/Script/Engine.HUD:ReceiveDrawHUD', function()
      tickOnce()
    end)
  end)

  if okHud then
    tickRegistered = true
    print('[CrabRuntimeProbe] tick source registered: HUD ReceiveDrawHUD')
  end
end

if not tickRegistered and type(RegisterTick) == 'function' then
  local okTick = pcall(function()
    RegisterTick(function()
      tickOnce()
    end)
  end)

  if okTick then
    tickRegistered = true
    print('[CrabRuntimeProbe] tick source registered: RegisterTick')
  end
end

if not tickRegistered and type(LoopAsync) == 'function' then
  local okLoop = pcall(function()
    LoopAsync(100, function()
      tickOnce()
      return true
    end)
  end)

  if okLoop then
    tickRegistered = true
    print('[CrabRuntimeProbe] tick source registered: LoopAsync')
  end
end

if not tickRegistered then
  print('[CrabRuntimeProbe] ERROR: no supported tick source registered')
end

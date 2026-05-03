local SCRIPT_DIR = 'Mods/CrabRuntimeProbe/Scripts/'
package.path = package.path .. ';' .. SCRIPT_DIR .. '?.lua'

local safe = require('safe_access')
local runner = require('probe_runner')
local writerFactory = require('result_writer')

local DEFAULT_CONFIG = {
  enabled = true,
  mode = 'observe',
  debugBreadcrumbs = true,
  writeJsonlResults = true,
  writeMarkdownSnapshots = false,
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

RegisterHook('/Script/Engine.PlayerController:ClientRestart', function()
  print('[CrabRuntimeProbe][hook] ClientRestart')
end)

if type(LoopAsync) == 'function' then
  LoopAsync(100, function()
    state:onTick()
    return true
  end)
elseif type(RegisterTick) == 'function' then
  RegisterTick(function()
    state:onTick()
  end)
else
  print('[CrabRuntimeProbe] no supported tick API found')
end

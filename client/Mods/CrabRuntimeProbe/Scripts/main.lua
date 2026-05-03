package.path = package.path .. ';./?.lua'

local safe = require('safe_access')
local runner = require('probe_runner')
local writerFactory = require('result_writer')

local function parseConfig(path)
  local config = {}
  for line in io.lines(path) do
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
  return config
end

local cfg = parseConfig('config.txt')
local sessionId = os.date('!%Y%m%dT%H%M%SZ')
local writer = writerFactory.new(sessionId, cfg)
local state = runner.new(cfg, safe, writer)

print('[CrabRuntimeProbe] started session=' .. sessionId .. ' mode=' .. tostring(cfg.mode))

RegisterHook('/Script/Engine.PlayerController:ClientRestart', function()
  print('[CrabRuntimeProbe][hook] ClientRestart')
end)

LoopAsync(100, function()
  state:onTick()
  return true
end)

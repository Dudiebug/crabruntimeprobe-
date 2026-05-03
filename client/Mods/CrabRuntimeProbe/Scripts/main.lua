package.path = package.path .. ";Mods/CrabRuntimeProbe/Scripts/?.lua"

local safe = require("safe_access")
local registry = require("probe_registry")
local result_writer = require("result_writer")
local probe_runner = require("probe_runner")

local function parseConfig(path)
  local cfg = {
    enabled = true,
    mode = "observe",
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
    probeSet = "shallow-core",
  }
  local f = io.open(path, "r")
  if not f then return cfg end
  for line in f:lines() do
    local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    if k and v then
      if v == "true" then cfg[k] = true
      elseif v == "false" then cfg[k] = false
      elseif tonumber(v) then cfg[k] = tonumber(v)
      else cfg[k] = v end
    end
  end
  f:close()
  return cfg
end

local config = parseConfig("Mods/CrabRuntimeProbe/Scripts/config.txt")
if not config.enabled then
  print("[CrabRuntimeProbe] disabled in config")
  return
end

local sessionId = os.date("!%Y%m%dT%H%M%SZ")
local writer = result_writer.new(sessionId, config)
local runner = probe_runner.new(config, safe, registry, writer)

RegisterHook("/Script/Engine.HUD:ReceiveDrawHUD", function()
  probe_runner.step(runner)
end)

print("[CrabRuntimeProbe] started session " .. sessionId .. " mode=" .. config.mode)

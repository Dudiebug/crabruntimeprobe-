local safe = require('safe_access')
local ctx = require('runtime_context')
local registry = require('probe_registry')

local runner = { tick = 0, probeIndex = 1, probes = {} }

function runner.init(config)
  runner.config = config
  runner.probes = registry.forSet(config.probeSet)
end

local function blocked(p, cfg, context)
  if p.gate and not cfg[p.gate] then return 'unsafe_disabled' end
  if context == 'joined-client' and not cfg.allowJoinedClientDeepProbes and p.set == 'inventory-array-deep' then return 'skipped_context' end
  return nil
end

function runner.step(state, emit)
  runner.tick = runner.tick + 1
  if runner.tick < runner.config.startupWarmupTicks then return end
  local context = ctx.detect({
    traveling = state.traveling, inMenu = state.inMenu, inLobby = state.inLobby,
    isSolo = state.isSolo, isHost = state.isHost, isJoined = state.isJoined,
    dead = state.dead, contextStableTicksRequired = runner.config.contextStableTicksRequired,
  })
  if context == 'unstable' then return end
  if runner.tick % runner.config.probeIntervalTicks ~= 0 then return end
  if runner.probeIndex > #runner.probes or runner.probeIndex > runner.config.maxProbesPerSession then return end

  local p = runner.probes[runner.probeIndex]
  runner.probeIndex = runner.probeIndex + 1
  local block = blocked(p, runner.config, context)
  local row = {
    timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'), sessionId = state.sessionId, tick = runner.tick,
    mode = runner.config.mode, probeId = p.id, probeName = p.id, category = p.category,
    context = context, role = state.role or 'unknown', lifecycleState = 'stable', step = 'run',
    result = block or 'ok', valueKind = 'unknown', valueSummary = '', error = '', durationMs = 0
  }
  if emit then emit('[CRP] breadcrumb before ' .. p.id) end
  if emit then emit('[CRP] breadcrumb after ' .. p.id) end
  return row
end

return runner

local runtimeContext = require('runtime_context')
local probeRegistry = require('probe_registry')

local runner = {}

function runner.new(config, safe, writer)
  local state = {
    tick = 0,
    started = false,
    cache = {},
    stableTicks = 0,
    probesRun = 0,
    lastContext = 'unknown',
    role = 'unknown',
    inMenu = false,
    inLobby = false,
    inSolo = false,
    isHost = false,
    isJoinedClient = false,
    traveling = false,
    deadOrRespawning = false,
    unstableTicks = 0
  }

  local probes = probeRegistry.build(safe)
  local idx = 1

  local function breadcrumb(msg)
    if config.debugBreadcrumbs then
      print('[CrabRuntimeProbe][breadcrumb] ' .. msg)
    end
  end

  local function emit(probe, result, kind, summary, err)
    writer:write({
      tick = state.tick,
      mode = config.mode,
      probeId = probe.id,
      probeName = probe.id,
      category = probe.category,
      context = state.lastContext,
      role = state.role,
      lifecycleState = state.stableTicks >= config.contextStableTicksRequired and 'stable' or 'warming',
      step = probe.step,
      result = result or 'unknown',
      valueKind = kind or '',
      valueSummary = summary or '',
      error = err or '',
      durationMs = 0
    })
  end

  local function allowedByConfig(probe)
    if probe.set == 'inventory-array-deep' and not config.allowDeepArrayProbes then return false, 'unsafe_disabled' end
    if probe.set == 'inventory-info' and not config.allowInventoryInfoProbes then return false, 'unsafe_disabled' end
    if probe.set == 'health-read' and not config.allowHealthProbes then return false, 'unsafe_disabled' end
    if probe.set == 'rpc-dryrun' and not config.allowRpcProbes then return false, 'unsafe_disabled' end
    if probe.set ~= config.probeSet and config.probeSet ~= 'all-readonly' then return false, 'skipped_by_config' end
    return true
  end

  function state:onTick()
    if not config.enabled then return end
    self.tick = self.tick + 1
    self.lastContext = runtimeContext.detect(safe, self)
    self.role = runtimeContext.detectRole(self)
    if self.lastContext ~= 'unstable' and self.lastContext ~= 'unknown' then self.stableTicks = self.stableTicks + 1 end

    if self.tick <= config.startupWarmupTicks then return end
    if self.stableTicks < config.contextStableTicksRequired then return end
    if self.probesRun >= config.maxProbesPerSession then return end
    if (self.tick % config.probeIntervalTicks) ~= 0 then return end

    local probe = probes[idx]
    if not probe then return end
    idx = idx + 1

    local allowed, reason = allowedByConfig(probe)
    if not allowed then
      emit(probe, reason)
      return
    end

    breadcrumb(probe.id .. ' enter')
    local result, kind, summary, err = probe.run(self)
    breadcrumb(probe.id .. ' exit')
    emit(probe, result, kind, summary, err)
    self.probesRun = self.probesRun + 1
  end

  return state
end

return runner

local crpLog = require('crp_log')
local runtimeContext = require('runtime_context')

local runner = {}

function runner.new(config, safe, writer, evidenceWriter)
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

  local probes = {}
  if config.mode == 'active' then
    local probeRegistry = require('probe_registry')
    local registeredProbes = probeRegistry.build(safe)
    for _, probe in ipairs(registeredProbes) do
      if config.probeSet == 'all-readonly' or probe.set == config.probeSet then
        probes[#probes + 1] = probe
      end
    end
  end
  local idx = 1

  local function breadcrumb(msg)
    if config.debugBreadcrumbs then
      crpLog.line('[CrabRuntimeProbe][breadcrumb] ' .. msg)
    end
  end

  local function positiveNumber(value, fallback)
    if type(value) == 'number' and value > 0 then return value end
    return fallback
  end

  local function runtimeStatus(result)
    if result == 'ok' then return 'SAFE' end
    if result == 'nil' then return 'RETURNS_NIL' end
    if result == 'lua_error' then return 'LUA_ERROR' end
    if result == 'skipped_context' then return 'SKIPPED_CONTEXT' end
    if result == 'skipped_by_config' then return 'SKIPPED_BY_CONFIG' end
    if result == 'unsafe_disabled' then return 'UNSAFE_DISABLED' end
    return 'UNTESTED'
  end

  local function writeEvidence(probe, result, kind, summary, err)
    if not evidenceWriter then return end
    evidenceWriter:writeEvidence({
      probeId = probe.id,
      probeName = probe.id,
      probeSet = probe.set or '',
      category = probe.category or '',
      symbol = probe.symbol or probe.id,
      owner = probe.owner or '',
      member = probe.member or '',
      accessMethod = probe.accessMethod or '',
      accessKind = probe.accessKind or '',
      mode = config.mode,
      tickDriver = tostring(config.tickDriver),
      tick = state.tick,
      context = state.lastContext,
      role = state.role,
      lifecycleState = state.lifecycleState,
      result = result or 'unknown',
      runtimeStatus = runtimeStatus(result),
      valueKind = kind or '',
      valueSummary = summary or '',
      error = err or ''
    })
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
      lifecycleState = state.lifecycleState,
      step = probe.step,
      result = result or 'unknown',
      valueKind = kind or '',
      valueSummary = summary or '',
      error = err or '',
      durationMs = 0
    })
    writeEvidence(probe, result, kind, summary, err)
  end

  local function allowedByConfig(probe)
    if probe.set == 'inventory-array-deep' and not config.allowDeepArrayProbes then return false, 'unsafe_disabled' end
    if probe.set == 'inventory-info' and not config.allowInventoryInfoProbes then return false, 'unsafe_disabled' end
    if probe.set == 'health-read' and not config.allowHealthProbes then return false, 'unsafe_disabled' end
    if probe.set == 'rpc-dryrun' and not config.allowRpcProbes then return false, 'unsafe_disabled' end
    if probe.set == 'write' and not config.allowWriteProbes then return false, 'unsafe_disabled' end
    if state.role == 'unknown' and not config.allowUnknownRoleProbes then return false, 'skipped_context' end
    if state.role == 'joined-client' and probe.set ~= 'shallow-core' and not config.allowJoinedClientDeepProbes then return false, 'skipped_context' end
    if probe.set ~= config.probeSet and config.probeSet ~= 'all-readonly' then return false, 'skipped_by_config' end
    return true
  end

  local function updateContext()
    local facts = runtimeContext.snapshot(safe, state)
    state.lastContext = facts.context
    state.role = facts.role
    state.lifecycleState = 'warming'

    local stableContext = facts.context ~= 'unknown'
      and facts.context ~= 'unstable'
      and facts.context ~= 'traveling'
      and facts.context ~= 'dead-or-respawning'

    if stableContext and facts.context == state.previousContext then
      state.stableTicks = state.stableTicks + 1
    elseif stableContext then
      state.stableTicks = 1
    else
      state.stableTicks = 0
    end

    state.previousContext = facts.context
    if state.stableTicks >= config.contextStableTicksRequired then
      state.lifecycleState = 'stable'
    end

    return facts
  end

  local function observe(facts)
    writer:write({
      tick = state.tick,
      mode = 'observe',
      probeId = 'Observe.Context',
      probeName = 'Observe.Context',
      category = 'observe',
      context = facts.context,
      role = facts.role,
      lifecycleState = state.lifecycleState,
      result = facts.result,
      crabPcExists = facts.crabPcExists,
      crabPcValid = facts.crabPcValid,
      playerStateExists = facts.playerStateExists,
      playerStateValid = facts.playerStateValid,
      error = facts.error
    })
    if evidenceWriter then
      evidenceWriter:writeEvidence({
        probeId = 'Observe.Context',
        probeName = 'Observe.Context',
        probeSet = tostring(config.probeSet),
        category = 'observe',
        symbol = 'Runtime.Context',
        owner = 'Runtime',
        member = 'Context',
        accessMethod = 'observe',
        accessKind = 'context',
        mode = 'observe',
        tickDriver = tostring(config.tickDriver),
        tick = state.tick,
        context = facts.context,
        role = facts.role,
        lifecycleState = state.lifecycleState,
        result = facts.result,
        runtimeStatus = 'SAFE',
        valueKind = 'context',
        valueSummary = tostring(facts.context) .. ' role=' .. tostring(facts.role),
        error = facts.error or '',
        localNotes = 'context observation only; not arbitrary object access'
      })
    end
  end

  function state:onTick()
    if not config.enabled then return end
    self.tick = self.tick + 1

    if config.debugTickHeartbeat == true and (self.tick % 100) == 0 then
      crpLog.line('[CrabRuntimeProbe] tick heartbeat tick=' .. tostring(self.tick) .. ' mode=' .. tostring(config.mode))
    end

    if config.mode == 'observe' then
      if self.tick <= config.startupWarmupTicks then return end
      local observeInterval = positiveNumber(config.observeIntervalTicks, positiveNumber(config.probeIntervalTicks, 10))
      if (self.tick % observeInterval) ~= 0 then return end
      local facts = updateContext()
      observe(facts)
      return
    end

    if config.mode ~= 'active' then
      return
    end

    if self.tick <= config.startupWarmupTicks then return end
    updateContext()
    if self.stableTicks < config.contextStableTicksRequired then return end
    if self.probesRun >= config.maxProbesPerSession then return end
    local probeInterval = positiveNumber(config.probeIntervalTicks, 10)
    if (self.tick % probeInterval) ~= 0 then return end

    local probe = probes[idx]
    if not probe then return end
    idx = idx + 1

    local allowed, reason = allowedByConfig(probe)
    if not allowed then
      emit(probe, reason)
      return
    end

    breadcrumb(probe.id .. ' enter')
    local ok, result, kind, summary, err = pcall(probe.run, self)
    if not ok then
      err = tostring(result)
      result = 'lua_error'
      kind = nil
      summary = nil
    end
    breadcrumb(probe.id .. ' exit')
    emit(probe, result, kind, summary, err)
    self.probesRun = self.probesRun + 1
  end

  return state
end

return runner

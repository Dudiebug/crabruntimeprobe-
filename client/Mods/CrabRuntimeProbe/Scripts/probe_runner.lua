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
    config = config,
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

  local function writeEvidence(probe, result, kind, summary, err, meta)
    if not evidenceWriter then return end
    local record = {
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
      error = err or '',
      sourceScope = probe.sourceScope or ''
    }
    if type(meta) == 'table' then
      record.fullName = meta.fullName or ''
      record.shortName = meta.shortName or ''
      record.nameSource = meta.nameSource or ''
      record.objectClass = meta.objectClass or ''
      record.sourceScope = meta.sourceScope or record.sourceScope
      record.localNotes = meta.localNotes or nil
      record.currentHealth = meta.currentHealth
      record.currentMaxHealth = meta.currentMaxHealth
      record.baseMaxHealth = meta.baseMaxHealth
      record.maxHealthMultiplier = meta.maxHealthMultiplier
      record.sampleIndex = meta.sampleIndex
      record.localPlayerPresent = meta.localPlayerPresent
      record.visiblePlayerCount = meta.visiblePlayerCount
      record.visiblePlayerCap = meta.visiblePlayerCap
      record.displayNameFingerprints = meta.displayNameFingerprints
      record.stableIdFingerprints = meta.stableIdFingerprints
      record.sourcePath = meta.sourcePath
      record.sourceClass = meta.sourceClass
      record.sourceName = meta.sourceName
      record.candidateClasses = meta.candidateClasses
      record.playerArrayValueKind = meta.playerArrayValueKind
      record.playerArrayTableSampleCount = meta.playerArrayTableSampleCount
      record.rosterSourceResolved = meta.rosterSourceResolved
      record.hostClientRoleConsistent = meta.hostClientRoleConsistent
      record.identityRawRedacted = meta.identityRawRedacted
      record.rawIdentityEvidence = meta.rawIdentityEvidence
      record.rawDisplayNames = meta.rawDisplayNames
      record.rawStableIds = meta.rawStableIds
      record.sampledPlayerStateCount = meta.sampledPlayerStateCount
      record.readableCrystalsCount = meta.readableCrystalsCount
      record.readableKeysCount = meta.readableKeysCount
      record.readableSlotsCount = meta.readableSlotsCount
      record.readableEquipmentCount = meta.readableEquipmentCount
      record.readableInventoryArrayCount = meta.readableInventoryArrayCount
      record.readableHealthCount = meta.readableHealthCount
      record.resourceVisibilityClass = meta.resourceVisibilityClass
      record.supportsP2PResourceMerge = meta.supportsP2PResourceMerge
      record.fieldsVisibleAcrossMultiple = meta.fieldsVisibleAcrossMultiple
      record.fieldsOnlyVisibleOnLocal = meta.fieldsOnlyVisibleOnLocal
      record.fieldsNilOrErrors = meta.fieldsNilOrErrors
      record.nonIdentityResourceCategoryEvaluated = meta.nonIdentityResourceCategoryEvaluated
      record.crystalsReadAttempted = meta.crystalsReadAttempted
      record.crystalsPresent = meta.crystalsPresent
      record.crystalsValue = meta.crystalsValue
      record.crystalsValueKind = meta.crystalsValueKind
      record.crystalsIntegerLike = meta.crystalsIntegerLike
      record.crystalsInUInt32Range = meta.crystalsInUInt32Range
      record.slotsReadAttempted = meta.slotsReadAttempted
      record.slotFieldNames = meta.slotFieldNames
      record.slotValueKinds = meta.slotValueKinds
      record.slotIntegerLike = meta.slotIntegerLike
      record.slotValuesInByteRange = meta.slotValuesInByteRange
      record.lockedSlotModel = meta.lockedSlotModel
      record.localPlayerStatePresent = meta.localPlayerStatePresent
      record.arrayFieldName = meta.arrayFieldName
      record.arrayFieldNames = meta.arrayFieldNames
      record.arrayValueKind = meta.arrayValueKind
      record.arrayValueKinds = meta.arrayValueKinds
      record.arrayCount = meta.arrayCount
      record.arrayCounts = meta.arrayCounts
      record.arrayCountCap = meta.arrayCountCap
      record.arrayPropertiesPresent = meta.arrayPropertiesPresent
      record.arrayTostringKinds = meta.arrayTostringKinds
      record.slotScalarValues = meta.slotScalarValues
      record.fieldResults = meta.fieldResults
      record.fieldsReadable = meta.fieldsReadable
      record.fieldsNilOrUnsupported = meta.fieldsNilOrUnsupported
      record.valueKinds = meta.valueKinds
      record.tostringKinds = meta.tostringKinds
      record.tostringPrefixes = meta.tostringPrefixes
      record.metatableKinds = meta.metatableKinds
      record.metatableKeys = meta.metatableKeys
      record.metatableErrors = meta.metatableErrors
      record.lenOperatorAttempted = meta.lenOperatorAttempted
      record.lenOperatorResults = meta.lenOperatorResults
      record.lenOperatorErrors = meta.lenOperatorErrors
      record.noElementDereference = meta.noElementDereference
      record.noArrayCount = meta.noArrayCount
      record.noArrayTraversal = meta.noArrayTraversal
      record.noInventoryInfo = meta.noInventoryInfo
      record.noEnhancements = meta.noEnhancements
      record.noWrites = meta.noWrites
      record.noRpcs = meta.noRpcs
      record.noHud = meta.noHud
      record.noDeepArrays = meta.noDeepArrays
      record.noInventoryArrays = meta.noInventoryArrays
      record.noDataAssetMutation = meta.noDataAssetMutation
      record.noFunctionCalls = meta.noFunctionCalls
      record.passiveOnly = meta.passiveOnly
      record.discoveryAttempted = meta.discoveryAttempted
      record.discoveryMethod = meta.discoveryMethod
      record.catalogFound = meta.catalogFound
      record.catalogEntryCount = meta.catalogEntryCount
      record.catalogCandidateCount = meta.catalogCandidateCount
      record.catalogCandidateCap = meta.catalogCandidateCap
      record.catalogFieldCap = meta.catalogFieldCap
      record.catalogEntries = meta.catalogEntries
      record.catalogFieldNames = meta.catalogFieldNames
      record.catalogReadStatuses = meta.catalogReadStatuses
      record.catalogValueKinds = meta.catalogValueKinds
      record.catalogObjectReferenceSummaries = meta.catalogObjectReferenceSummaries
      record.notFoundClassification = meta.notFoundClassification
      record.crashAttributionMarker = meta.crashAttributionMarker
      record.playerStatePresent = meta.playerStatePresent
      record.sampleReason = meta.sampleReason
      record.sampleChanged = meta.sampleChanged
      record.safeWatchSampleCount = meta.safeWatchSampleCount
      record.safeWatchLoggedCount = meta.safeWatchLoggedCount
      record.safeWatchFirstValues = meta.safeWatchFirstValues
      record.safeWatchLatestValues = meta.safeWatchLatestValues
      record.safeWatchMinValues = meta.safeWatchMinValues
      record.safeWatchMaxValues = meta.safeWatchMaxValues
      record.safeWatchChangedFields = meta.safeWatchChangedFields
      record.safeWatchChangeCounts = meta.safeWatchChangeCounts
      record.safeWatchNoChangeSamples = meta.safeWatchNoChangeSamples
      record.safeWatchChangedSamples = meta.safeWatchChangedSamples
      record.maxSafePlayScalarSampleCount = meta.maxSafePlayScalarSampleCount
      record.maxSafePlayScalarLoggedCount = meta.maxSafePlayScalarLoggedCount
      record.maxSafePlayFirstValues = meta.maxSafePlayFirstValues
      record.maxSafePlayLatestValues = meta.maxSafePlayLatestValues
      record.maxSafePlayMinValues = meta.maxSafePlayMinValues
      record.maxSafePlayMaxValues = meta.maxSafePlayMaxValues
      record.maxSafePlayChangedFields = meta.maxSafePlayChangedFields
      record.maxSafePlayChangeCounts = meta.maxSafePlayChangeCounts
      record.maxSafePlayNoChangeSamples = meta.maxSafePlayNoChangeSamples
      record.maxSafePlayChangedSamples = meta.maxSafePlayChangedSamples
      record.maxSafePlayCatalogSnapshotCount = meta.maxSafePlayCatalogSnapshotCount
      record.maxSafePlayCatalogLoggedCount = meta.maxSafePlayCatalogLoggedCount
      record.maxSafePlayNewDataAssets = meta.maxSafePlayNewDataAssets
      record.maxSafePlayChangedCatalogEntries = meta.maxSafePlayChangedCatalogEntries
      record.maxSafePlayCatalogKnownEntryCount = meta.maxSafePlayCatalogKnownEntryCount
      record.maxSafePlayNilCount = meta.maxSafePlayNilCount
      record.maxSafePlayErrorCount = meta.maxSafePlayErrorCount
      record.tastyOrangeFound = meta.tastyOrangeFound
      record.collectorFound = meta.collectorFound
      record.firstContext = meta.firstContext
      record.lastContext = meta.lastContext
      record.firstRole = meta.firstRole
      record.lastRole = meta.lastRole
    end
    evidenceWriter:writeEvidence(record)
  end

  local function emit(probe, result, kind, summary, err, meta)
    local row = {
      event = probe.id,
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
    }
    if type(meta) == 'table' then
      row.currentHealth = meta.currentHealth
      row.currentMaxHealth = meta.currentMaxHealth
      row.baseMaxHealth = meta.baseMaxHealth
      row.maxHealthMultiplier = meta.maxHealthMultiplier
      row.sampleIndex = meta.sampleIndex
      row.sourceScope = meta.sourceScope
      row.localNotes = meta.localNotes
      row.localPlayerPresent = meta.localPlayerPresent
      row.visiblePlayerCount = meta.visiblePlayerCount
      row.visiblePlayerCap = meta.visiblePlayerCap
      row.displayNameFingerprints = meta.displayNameFingerprints
      row.stableIdFingerprints = meta.stableIdFingerprints
      row.sourcePath = meta.sourcePath
      row.sourceClass = meta.sourceClass
      row.sourceName = meta.sourceName
      row.candidateClasses = meta.candidateClasses
      row.playerArrayValueKind = meta.playerArrayValueKind
      row.playerArrayTableSampleCount = meta.playerArrayTableSampleCount
      row.rosterSourceResolved = meta.rosterSourceResolved
      row.hostClientRoleConsistent = meta.hostClientRoleConsistent
      row.identityRawRedacted = meta.identityRawRedacted
      row.rawIdentityEvidence = meta.rawIdentityEvidence
      row.rawDisplayNames = meta.rawDisplayNames
      row.rawStableIds = meta.rawStableIds
      row.sampledPlayerStateCount = meta.sampledPlayerStateCount
      row.readableCrystalsCount = meta.readableCrystalsCount
      row.readableKeysCount = meta.readableKeysCount
      row.readableSlotsCount = meta.readableSlotsCount
      row.readableEquipmentCount = meta.readableEquipmentCount
      row.readableInventoryArrayCount = meta.readableInventoryArrayCount
      row.readableHealthCount = meta.readableHealthCount
      row.resourceVisibilityClass = meta.resourceVisibilityClass
      row.supportsP2PResourceMerge = meta.supportsP2PResourceMerge
      row.fieldsVisibleAcrossMultiple = meta.fieldsVisibleAcrossMultiple
      row.fieldsOnlyVisibleOnLocal = meta.fieldsOnlyVisibleOnLocal
      row.fieldsNilOrErrors = meta.fieldsNilOrErrors
      row.nonIdentityResourceCategoryEvaluated = meta.nonIdentityResourceCategoryEvaluated
      row.crystalsReadAttempted = meta.crystalsReadAttempted
      row.crystalsPresent = meta.crystalsPresent
      row.crystalsValue = meta.crystalsValue
      row.crystalsValueKind = meta.crystalsValueKind
      row.crystalsIntegerLike = meta.crystalsIntegerLike
      row.crystalsInUInt32Range = meta.crystalsInUInt32Range
      row.slotsReadAttempted = meta.slotsReadAttempted
      row.slotFieldNames = meta.slotFieldNames
      row.slotValueKinds = meta.slotValueKinds
      row.slotIntegerLike = meta.slotIntegerLike
      row.slotValuesInByteRange = meta.slotValuesInByteRange
      row.lockedSlotModel = meta.lockedSlotModel
      row.localPlayerStatePresent = meta.localPlayerStatePresent
      row.arrayFieldName = meta.arrayFieldName
      row.arrayFieldNames = meta.arrayFieldNames
      row.arrayValueKind = meta.arrayValueKind
      row.arrayValueKinds = meta.arrayValueKinds
      row.arrayCount = meta.arrayCount
      row.arrayCounts = meta.arrayCounts
      row.arrayCountCap = meta.arrayCountCap
      row.arrayPropertiesPresent = meta.arrayPropertiesPresent
      row.arrayTostringKinds = meta.arrayTostringKinds
      row.slotScalarValues = meta.slotScalarValues
      row.fieldResults = meta.fieldResults
      row.fieldsReadable = meta.fieldsReadable
      row.fieldsNilOrUnsupported = meta.fieldsNilOrUnsupported
      row.valueKinds = meta.valueKinds
      row.tostringKinds = meta.tostringKinds
      row.tostringPrefixes = meta.tostringPrefixes
      row.metatableKinds = meta.metatableKinds
      row.metatableKeys = meta.metatableKeys
      row.metatableErrors = meta.metatableErrors
      row.lenOperatorAttempted = meta.lenOperatorAttempted
      row.lenOperatorResults = meta.lenOperatorResults
      row.lenOperatorErrors = meta.lenOperatorErrors
      row.noElementDereference = meta.noElementDereference
      row.noArrayCount = meta.noArrayCount
      row.noArrayTraversal = meta.noArrayTraversal
      row.noInventoryInfo = meta.noInventoryInfo
      row.noEnhancements = meta.noEnhancements
      row.noWrites = meta.noWrites
      row.noRpcs = meta.noRpcs
      row.noHud = meta.noHud
      row.noDeepArrays = meta.noDeepArrays
      row.noInventoryArrays = meta.noInventoryArrays
      row.noDataAssetMutation = meta.noDataAssetMutation
      row.noFunctionCalls = meta.noFunctionCalls
      row.passiveOnly = meta.passiveOnly
      row.discoveryAttempted = meta.discoveryAttempted
      row.discoveryMethod = meta.discoveryMethod
      row.catalogFound = meta.catalogFound
      row.catalogEntryCount = meta.catalogEntryCount
      row.catalogCandidateCount = meta.catalogCandidateCount
      row.catalogCandidateCap = meta.catalogCandidateCap
      row.catalogFieldCap = meta.catalogFieldCap
      row.catalogEntries = meta.catalogEntries
      row.catalogFieldNames = meta.catalogFieldNames
      row.catalogReadStatuses = meta.catalogReadStatuses
      row.catalogValueKinds = meta.catalogValueKinds
      row.catalogObjectReferenceSummaries = meta.catalogObjectReferenceSummaries
      row.notFoundClassification = meta.notFoundClassification
      row.crashAttributionMarker = meta.crashAttributionMarker
      row.playerStatePresent = meta.playerStatePresent
      row.sampleReason = meta.sampleReason
      row.sampleChanged = meta.sampleChanged
      row.safeWatchSampleCount = meta.safeWatchSampleCount
      row.safeWatchLoggedCount = meta.safeWatchLoggedCount
      row.safeWatchFirstValues = meta.safeWatchFirstValues
      row.safeWatchLatestValues = meta.safeWatchLatestValues
      row.safeWatchMinValues = meta.safeWatchMinValues
      row.safeWatchMaxValues = meta.safeWatchMaxValues
      row.safeWatchChangedFields = meta.safeWatchChangedFields
      row.safeWatchChangeCounts = meta.safeWatchChangeCounts
      row.safeWatchNoChangeSamples = meta.safeWatchNoChangeSamples
      row.safeWatchChangedSamples = meta.safeWatchChangedSamples
      row.maxSafePlayScalarSampleCount = meta.maxSafePlayScalarSampleCount
      row.maxSafePlayScalarLoggedCount = meta.maxSafePlayScalarLoggedCount
      row.maxSafePlayFirstValues = meta.maxSafePlayFirstValues
      row.maxSafePlayLatestValues = meta.maxSafePlayLatestValues
      row.maxSafePlayMinValues = meta.maxSafePlayMinValues
      row.maxSafePlayMaxValues = meta.maxSafePlayMaxValues
      row.maxSafePlayChangedFields = meta.maxSafePlayChangedFields
      row.maxSafePlayChangeCounts = meta.maxSafePlayChangeCounts
      row.maxSafePlayNoChangeSamples = meta.maxSafePlayNoChangeSamples
      row.maxSafePlayChangedSamples = meta.maxSafePlayChangedSamples
      row.maxSafePlayCatalogSnapshotCount = meta.maxSafePlayCatalogSnapshotCount
      row.maxSafePlayCatalogLoggedCount = meta.maxSafePlayCatalogLoggedCount
      row.maxSafePlayNewDataAssets = meta.maxSafePlayNewDataAssets
      row.maxSafePlayChangedCatalogEntries = meta.maxSafePlayChangedCatalogEntries
      row.maxSafePlayCatalogKnownEntryCount = meta.maxSafePlayCatalogKnownEntryCount
      row.maxSafePlayNilCount = meta.maxSafePlayNilCount
      row.maxSafePlayErrorCount = meta.maxSafePlayErrorCount
      row.tastyOrangeFound = meta.tastyOrangeFound
      row.collectorFound = meta.collectorFound
      row.firstContext = meta.firstContext
      row.lastContext = meta.lastContext
      row.firstRole = meta.firstRole
      row.lastRole = meta.lastRole
    end
    writer:write(row)
    writeEvidence(probe, result, kind, summary, err, meta)
  end

  local function allowedByConfig(probe)
    if probe.set == 'inventory-array-deep' and not config.allowDeepArrayProbes then return false, 'unsafe_disabled' end
    if probe.set == 'inventory-info' and not config.allowInventoryInfoProbes then return false, 'unsafe_disabled' end
    if (probe.set == 'health-read' or probe.set == 'health-baseline-read' or probe.set == 'health-playerstate-read' or probe.set == 'health-playerstate-watch' or probe.set == 'health-hc-discovery-read') and not config.allowHealthProbes then return false, 'unsafe_disabled' end
    if probe.set == 'multiplayer-roster-read' and not config.allowIdentityProbes then return false, 'unsafe_disabled' end
    if probe.set == 'multiplayer-resource-visibility-read' and not (config.allowIdentityProbes and config.allowHealthProbes and config.allowResourceVisibilityProbes) then return false, 'unsafe_disabled' end
    if probe.set == 'crystals-read' and not config.allowCrystalsReadProbes then return false, 'unsafe_disabled' end
    if probe.set == 'slots-read' and not config.allowSlotsReadProbes then return false, 'unsafe_disabled' end
    if probe.set == 'safe-scalar-watch' and not config.allowSafeScalarWatchProbes then return false, 'unsafe_disabled' end
    if probe.set == 'perk-da-catalog-read' and not config.allowPerkDataAssetCatalogProbes then return false, 'unsafe_disabled' end
    if probe.set == 'max-safe-play-recorder' and not config.allowMaxSafePlayRecorderProbes then return false, 'unsafe_disabled' end
    if probe.set == 'local-inventory-array-shallow-read' and not config.allowInventoryArrayShallowProbes then return false, 'unsafe_disabled' end
    if probe.set == 'local-inventory-array-shape-confirm' and not config.allowInventoryArrayShapeConfirmProbes then return false, 'unsafe_disabled' end
    if probe.set == 'local-inventory-userdata-introspection' and not config.allowInventoryUserdataIntrospectionProbes then return false, 'unsafe_disabled' end
    if probe.set == 'rpc-dryrun' and not config.allowRpcProbes then return false, 'unsafe_disabled' end
    if probe.set == 'write' and not config.allowWriteProbes then return false, 'unsafe_disabled' end
    if state.role == 'unknown' and probe.set ~= 'multiplayer-roster-read' and probe.set ~= 'multiplayer-resource-visibility-read' and probe.set ~= 'crystals-read' and probe.set ~= 'slots-read' and probe.set ~= 'safe-scalar-watch' and probe.set ~= 'perk-da-catalog-read' and probe.set ~= 'max-safe-play-recorder' and probe.set ~= 'local-inventory-array-shallow-read' and probe.set ~= 'local-inventory-array-shape-confirm' and probe.set ~= 'local-inventory-userdata-introspection' and not config.allowUnknownRoleProbes then return false, 'skipped_context' end
    if state.role == 'joined-client' and probe.set ~= 'shallow-core' and probe.set ~= 'multiplayer-roster-read' and probe.set ~= 'multiplayer-resource-visibility-read' and probe.set ~= 'crystals-read' and probe.set ~= 'slots-read' and probe.set ~= 'safe-scalar-watch' and probe.set ~= 'perk-da-catalog-read' and probe.set ~= 'max-safe-play-recorder' and probe.set ~= 'local-inventory-array-shallow-read' and probe.set ~= 'local-inventory-array-shape-confirm' and probe.set ~= 'local-inventory-userdata-introspection' and not config.allowJoinedClientDeepProbes then return false, 'skipped_context' end
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
    if not probe then
      if config.repeatProbeSet == true and #probes > 0 then
        idx = 1
        probe = probes[idx]
      else
        return
      end
    end
    idx = idx + 1

    local allowed, reason = allowedByConfig(probe)
    if not allowed then
      emit(probe, reason)
      return
    end

    breadcrumb(probe.id .. ' enter')
    local ok, result, kind, summary, err, meta = pcall(probe.run, self)
    if not ok then
      err = tostring(result)
      result = 'lua_error'
      kind = nil
      summary = nil
    end
    breadcrumb(probe.id .. ' exit')
    if type(meta) == 'table' and meta.suppressEmit == true then
      return
    end
    emit(probe, result, kind, summary, err, meta)
    self.probesRun = self.probesRun + 1
  end

  return state
end

return runner

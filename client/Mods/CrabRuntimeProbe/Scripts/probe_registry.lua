local registry = {}

local function mk(id, category, setName, step, fn, opts)
  opts = opts or {}
  return {
    id = id,
    category = category,
    set = setName,
    step = step,
    run = fn,
    requires = opts.requires or {},
    symbol = opts.symbol or id,
    owner = opts.owner or '',
    member = opts.member or '',
    accessMethod = opts.accessMethod or step,
    accessKind = opts.accessKind or step,
    sourceScope = opts.sourceScope or ''
  }
end

function registry.build(safe)
  local probes = {}

  local function getCrabPlayerState(ctx)
    local crabPc, crabPcErr = safe.findFirst('CrabPC')
    ctx.cache.CrabPC = crabPc
    if crabPcErr then return nil, crabPcErr end
    local crabPs, crabPsErr = safe.getProperty(crabPc, 'PlayerState')
    ctx.cache.CrabPS = crabPs
    return crabPs, crabPsErr
  end

  local function readPlayerStateHealthSample(ctx)
    local crabPs, crabPsErr = getCrabPlayerState(ctx)
    if crabPsErr then return 'lua_error', nil, nil, crabPsErr end
    if not safe.isValidObject(crabPs) then return 'nil', 'object', 'PlayerState invalid' end

    local healthInfo, healthInfoErr = safe.getProperty(crabPs, 'HealthInfo')
    ctx.cache.CrabPSHealthInfo = healthInfo
    if healthInfoErr then return 'lua_error', nil, nil, healthInfoErr end
    if healthInfo == nil then return 'nil', 'table', 'HealthInfo nil' end

    local currentHealth, currentHealthErr = safe.getStructField(healthInfo, 'CurrentHealth')
    if currentHealthErr then return 'lua_error', nil, nil, 'HealthInfo.CurrentHealth: ' .. tostring(currentHealthErr) end
    local currentMaxHealth, currentMaxHealthErr = safe.getStructField(healthInfo, 'CurrentMaxHealth')
    if currentMaxHealthErr then return 'lua_error', nil, nil, 'HealthInfo.CurrentMaxHealth: ' .. tostring(currentMaxHealthErr) end
    local baseMaxHealth, baseMaxHealthErr = safe.getProperty(crabPs, 'BaseMaxHealth')
    if baseMaxHealthErr then return 'lua_error', nil, nil, 'BaseMaxHealth: ' .. tostring(baseMaxHealthErr) end
    local maxHealthMultiplier, multiplierErr = safe.getProperty(crabPs, 'MaxHealthMultiplier')
    if multiplierErr then return 'lua_error', nil, nil, 'MaxHealthMultiplier: ' .. tostring(multiplierErr) end

    ctx.cache.HealthPlayerStateWatchSampleIndex = (ctx.cache.HealthPlayerStateWatchSampleIndex or 0) + 1
    local summary = 'currentHealth=' .. tostring(currentHealth)
      .. ' currentMaxHealth=' .. tostring(currentMaxHealth)
      .. ' baseMaxHealth=' .. tostring(baseMaxHealth)
      .. ' maxHealthMultiplier=' .. tostring(maxHealthMultiplier)
    return 'ok', 'health_sample', summary, nil, {
      sourceScope = 'player_state_scoped',
      localNotes = 'CrabPC -> PlayerState -> CrabPS -> HealthInfo read-only sample',
      currentHealth = currentHealth,
      currentMaxHealth = currentMaxHealth,
      baseMaxHealth = baseMaxHealth,
      maxHealthMultiplier = maxHealthMultiplier,
      sampleIndex = ctx.cache.HealthPlayerStateWatchSampleIndex
    }
  end

  local function summarizeIdentityOrDefault(obj, fallback)
    local summary, summaryErr, identity = safe.summarizeObjectIdentity(obj)
    return summary or fallback, summaryErr, identity
  end

  local function readScalar(value)
    if value == nil then return 'nil' end
    return 'ok', type(value), tostring(value)
  end

  local function fingerprintValue(value)
    local text = tostring(value or '')
    if text == '' then return '', 0 end
    local hash = 2166136261
    for i = 1, #text do
      hash = (hash * 16777619 + string.byte(text, i)) % 4294967296
    end
    return string.format('%08x', hash), #text
  end

  local function readFirstProperty(obj, names)
    for _, name in ipairs(names) do
      local value, err = safe.getProperty(obj, name)
      if err == nil and value ~= nil and tostring(value) ~= '' then
        return value, name, nil
      end
    end
    return nil, '', nil
  end

  local function samplePlayerStateIdentity(playerState, config)
    local sample = {
      playerStatePresent = safe.isValidObject(playerState),
      displayNameSource = '',
      displayNameFingerprint = '',
      displayNameLength = 0,
      stableIdSource = '',
      stableIdFingerprint = '',
      stableIdLength = 0,
      rawDisplayName = nil,
      rawStableId = nil
    }
    if not sample.playerStatePresent then return sample end

    local displayName, displaySource = readFirstProperty(playerState, {
      'PlayerName',
      'PlayerNamePrivate',
      'DisplayName',
      'Name'
    })
    if displayName ~= nil then
      sample.displayNameSource = displaySource
      sample.displayNameFingerprint, sample.displayNameLength = fingerprintValue(displayName)
      if config.allowRawIdentityEvidence == true then
        sample.rawDisplayName = tostring(displayName)
      end
    end

    local stableId, idSource = readFirstProperty(playerState, {
      'UniqueId',
      'PlayerId',
      'PlatformId',
      'SteamId',
      'NetId'
    })
    if stableId ~= nil then
      sample.stableIdSource = idSource
      sample.stableIdFingerprint, sample.stableIdLength = fingerprintValue(stableId)
      if config.allowRawIdentityEvidence == true then
        sample.rawStableId = tostring(stableId)
      end
    end

    return sample
  end

  local function summarizeIdentitySamples(samples, prefix)
    local display = {}
    local ids = {}
    local displaySources = {}
    local idSources = {}
    for _, sample in ipairs(samples) do
      if sample.displayNameFingerprint ~= '' then
        display[#display + 1] = sample.displayNameFingerprint .. ':len' .. tostring(sample.displayNameLength)
        displaySources[sample.displayNameSource] = true
      end
      if sample.stableIdFingerprint ~= '' then
        ids[#ids + 1] = sample.stableIdFingerprint .. ':len' .. tostring(sample.stableIdLength)
        idSources[sample.stableIdSource] = true
      end
    end

    local displaySourceList = {}
    for source, _ in pairs(displaySources) do displaySourceList[#displaySourceList + 1] = source end
    local idSourceList = {}
    for source, _ in pairs(idSources) do idSourceList[#idSourceList + 1] = source end

    local summary = prefix
      .. ' displayFingerprints=' .. (#display > 0 and table.concat(display, ',') or 'none')
      .. ' idFingerprints=' .. (#ids > 0 and table.concat(ids, ',') or 'none')
      .. ' displaySources=' .. (#displaySourceList > 0 and table.concat(displaySourceList, ',') or 'none')
      .. ' idSources=' .. (#idSourceList > 0 and table.concat(idSourceList, ',') or 'none')
      .. ' rawIdentityEvidence=false'
    return summary, display, ids
  end

  local function getLocalPlayerState(ctx)
    local crabPc, crabPcErr = safe.findFirst('CrabPC')
    ctx.cache.CrabPC = crabPc
    if crabPcErr then return nil, crabPcErr end
    local playerState, playerStateErr = safe.getProperty(crabPc, 'PlayerState')
    ctx.cache.IdentityLocalPlayerState = playerState
    return playerState, playerStateErr
  end

  local function getGameState()
    local gameState, err = safe.findFirst('GameStateBase')
    if gameState ~= nil and err == nil then return gameState, 'GameStateBase', nil end
    local fallback, fallbackErr = safe.findFirst('GameState')
    return fallback, 'GameState', fallbackErr or err
  end

  local function inspectObjectSource(obj, sourcePath, sourceClass, note)
    local meta = {
      sourceScope = 'runtime_roster_candidate',
      sourcePath = sourcePath,
      sourceClass = sourceClass,
      sourceName = '',
      fullName = '',
      objectClass = '',
      valueKind = 'object',
      localPlayerPresent = false,
      visiblePlayerCount = 0,
      visiblePlayerCap = 0,
      displayNameFingerprints = {},
      stableIdFingerprints = {},
      identityRawRedacted = true,
      rawIdentityEvidence = false,
      rosterSourceResolved = false,
      localNotes = note
    }
    if not safe.isValidObject(obj) then
      return 'nil', 'object', 'sourcePath=' .. tostring(sourcePath) .. ' result=nil rawIdentityEvidence=false', nil, meta
    end

    local fullName, fullNameErr = safe.getFullName(obj)
    local name, nameErr = safe.getName(obj)
    local className, classErr = safe.getObjectClassName(obj)
    if fullNameErr then
      return 'lua_error', nil, nil, 'GetFullName: ' .. tostring(fullNameErr)
    end
    meta.fullName = tostring(fullName or '')
    meta.sourceName = nameErr and '' or tostring(name or '')
    meta.objectClass = tostring(className or sourceClass or '')
    if nameErr or classErr then
      meta.localNotes = tostring(note) .. '; optional source name/class read error: ' .. tostring(nameErr or '') .. tostring(classErr or '')
    end
    local summary = 'sourcePath=' .. tostring(sourcePath)
      .. ' sourceClass=' .. tostring(sourceClass)
      .. ' sourceName=' .. tostring(meta.sourceName)
      .. ' objectClass=' .. tostring(meta.objectClass)
      .. ' rawIdentityEvidence=false'
    return 'ok', 'object', summary, nil, meta
  end

  local function arrayShape(value)
    local kind = type(value)
    if value == nil then return 'nil', 0, false end
    if kind ~= 'table' then return kind, 0, false end
    local count = 0
    for _, _ in ipairs(value) do
      count = count + 1
      if count >= 16 then break end
    end
    return 'table', count, true
  end

  local function objectFromArrayElement(elem)
    local obj, err = safe.getArrayElement(elem)
    if err == nil and safe.isValidObject(obj) then return obj, nil end
    if safe.isValidObject(elem) then return elem, nil end
    return nil, err
  end

  local function collectPlayerStateSamplesFromArray(arr, cap, config)
    local samples = {}
    local rawNames = {}
    local rawIds = {}
    local count = 0
    safe.forEachArrayLimited(arr, cap, function(_, elem)
      local playerState = objectFromArrayElement(elem)
      if safe.isValidObject(playerState) then
        local sample = samplePlayerStateIdentity(playerState, config or {})
        samples[#samples + 1] = sample
        if config and config.allowRawIdentityEvidence == true then
          rawNames[#rawNames + 1] = sample.rawDisplayName or ''
          rawIds[#rawIds + 1] = sample.rawStableId or ''
        end
        count = count + 1
      end
    end)
    return samples, rawNames, rawIds, count
  end

  local function findAllAvailability()
    local ok, value = pcall(function() return type(FindAllOf) end)
    if not ok then return false, 'lua_error', tostring(value) end
    if value ~= 'function' then return false, 'nil', 'FindAllOf unavailable' end
    return true, 'ok', nil
  end

  local function collectFindAllPlayerStates(classNames, cap, config)
    local samples = {}
    local rawNames = {}
    local rawIds = {}
    local attempted = {}
    local count = 0
    for _, className in ipairs(classNames) do
      if count >= cap then break end
      attempted[#attempted + 1] = className
      local arr, err = safe.findAll(className)
      if err then return nil, nil, nil, count, table.concat(attempted, ','), err end
      if type(arr) == 'table' then
        safe.forEachArrayLimited(arr, cap - count, function(_, elem)
          local playerState = objectFromArrayElement(elem)
          if safe.isValidObject(playerState) then
            local sample = samplePlayerStateIdentity(playerState, config or {})
            samples[#samples + 1] = sample
            if config and config.allowRawIdentityEvidence == true then
              rawNames[#rawNames + 1] = sample.rawDisplayName or ''
              rawIds[#rawIds + 1] = sample.rawStableId or ''
            end
            count = count + 1
          end
        end)
      end
    end
    return samples, rawNames, rawIds, count, table.concat(attempted, ','), nil
  end

  local function collectResourceVisibilityCandidates(ctx, cap)
    local candidates = {}
    local seen = {}
    local attempted = {}
    local function addCandidate(playerState, sourcePath)
      if #candidates >= cap or not safe.isValidObject(playerState) then return end
      local key = tostring(playerState)
      if seen[key] then return end
      seen[key] = true
      candidates[#candidates + 1] = {
        object = playerState,
        sourcePath = sourcePath
      }
    end

    local available, availabilityResult, availabilityErr = findAllAvailability()
    if availabilityResult == 'lua_error' then return nil, '', availabilityErr end
    if available then
      for _, className in ipairs({ 'PlayerState', 'CrabPS' }) do
        if #candidates >= cap then break end
        attempted[#attempted + 1] = className
        local arr, err = safe.findAll(className)
        if err then return nil, table.concat(attempted, ','), err end
        if type(arr) == 'table' then
          safe.forEachArrayLimited(arr, cap, function(_, elem)
            local playerState = objectFromArrayElement(elem)
            addCandidate(playerState, 'FindAllOf(' .. className .. ')')
          end)
        end
      end

      for _, className in ipairs({ 'PlayerController', 'CrabPC' }) do
        if #candidates >= cap then break end
        attempted[#attempted + 1] = className
        local controllers, err = safe.findAll(className)
        if err then return nil, table.concat(attempted, ','), err end
        if type(controllers) == 'table' then
          safe.forEachArrayLimited(controllers, cap, function(_, elem)
            local controller = objectFromArrayElement(elem)
            if safe.isValidObject(controller) then
              local playerState = safe.getProperty(controller, 'PlayerState')
              addCandidate(playerState, 'FindAllOf(' .. className .. ').PlayerState')
            end
          end)
        end
      end
    end

    if #candidates == 0 then
      local localPlayerState = getLocalPlayerState(ctx)
      addCandidate(localPlayerState, 'CrabPC.PlayerState')
    end
    return candidates, table.concat(attempted, ','), nil
  end

  local function addReadableField(stats, fieldName, sampleIndex, isLocal)
    stats.fieldReadableCounts[fieldName] = (stats.fieldReadableCounts[fieldName] or 0) + 1
    if isLocal then stats.localReadableFields[fieldName] = true end
    stats.fieldReadAttempted[fieldName] = true
    if sampleIndex > 1 then stats.remoteReadableFields[fieldName] = true end
  end

  local function addNilOrErrorField(stats, fieldName)
    stats.fieldsNilOrErrorsMap[fieldName] = true
    stats.fieldReadAttempted[fieldName] = true
  end

  local function readResourceProperty(stats, playerState, fieldName, sampleIndex, isLocal)
    local value, err = safe.getProperty(playerState, fieldName)
    if err or value == nil then
      addNilOrErrorField(stats, fieldName)
      return false
    end
    addReadableField(stats, fieldName, sampleIndex, isLocal)
    return true
  end

  local function readResourceStructField(stats, value, fieldName, sampleIndex, isLocal)
    local fieldValue, err = safe.getStructField(value, fieldName)
    if err or fieldValue == nil then
      addNilOrErrorField(stats, 'HealthInfo.' .. fieldName)
      return false
    end
    addReadableField(stats, 'HealthInfo.' .. fieldName, sampleIndex, isLocal)
    return true
  end

  local function readInventoryArrayCount(stats, playerState, fieldName, sampleIndex, isLocal)
    local arr, err = safe.getProperty(playerState, fieldName)
    if err or arr == nil then
      addNilOrErrorField(stats, fieldName)
      return false
    end
    local count, countErr = safe.countArrayLimited(arr, 256)
    if countErr then
      addNilOrErrorField(stats, fieldName)
      return false
    end
    addReadableField(stats, fieldName, sampleIndex, isLocal)
    return true
  end

  local function keysSorted(map)
    local out = {}
    for key, _ in pairs(map or {}) do out[#out + 1] = key end
    table.sort(out)
    return out
  end

  local function buildResourceVisibilityCache(ctx)
    if ctx.cache.ResourceVisibility ~= nil then return ctx.cache.ResourceVisibility end
    local cap = 16
    local localPlayerState = getLocalPlayerState(ctx)
    local localKey = safe.isValidObject(localPlayerState) and tostring(localPlayerState) or ''
    local candidates, attempted, err = collectResourceVisibilityCandidates(ctx, cap)
    if err then
      ctx.cache.ResourceVisibility = {
        error = err,
        attempted = attempted or '',
        visiblePlayerCount = 0,
        sampledPlayerStateCount = 0,
        visiblePlayerCap = cap,
        samples = {},
        fieldReadableCounts = {},
        fieldsNilOrErrorsMap = {},
        localReadableFields = {},
        remoteReadableFields = {},
        rawIdentityEvidence = false,
        identityRawRedacted = true
      }
      return ctx.cache.ResourceVisibility
    end

    local stats = {
      attempted = attempted or '',
      visiblePlayerCount = #(candidates or {}),
      sampledPlayerStateCount = #(candidates or {}),
      visiblePlayerCap = cap,
      samples = {},
      fieldReadableCounts = {},
      fieldsNilOrErrorsMap = {},
      fieldReadAttempted = {},
      localReadableFields = {},
      remoteReadableFields = {},
      rawIdentityEvidence = false,
      identityRawRedacted = true,
      readableCrystalsCount = 0,
      readableKeysCount = 0,
      readableHealthCount = 0,
      readableSlotsCount = 0,
      readableEquipmentCount = 0,
      readableInventoryArrayCount = 0
    }

    for index, candidate in ipairs(candidates or {}) do
      local playerState = candidate.object
      local isLocal = localKey ~= '' and tostring(playerState) == localKey
      local identity = samplePlayerStateIdentity(playerState, { allowRawIdentityEvidence = false })
      stats.samples[#stats.samples + 1] = identity

      local healthInfo, healthInfoErr = safe.getProperty(playerState, 'HealthInfo')
      local healthReadable = false
      if healthInfoErr or healthInfo == nil then
        addNilOrErrorField(stats, 'HealthInfo')
      else
        addReadableField(stats, 'HealthInfo', index, isLocal)
        healthReadable = readResourceStructField(stats, healthInfo, 'CurrentHealth', index, isLocal) or healthReadable
        healthReadable = readResourceStructField(stats, healthInfo, 'CurrentMaxHealth', index, isLocal) or healthReadable
      end
      healthReadable = readResourceProperty(stats, playerState, 'BaseMaxHealth', index, isLocal) or healthReadable
      healthReadable = readResourceProperty(stats, playerState, 'MaxHealthMultiplier', index, isLocal) or healthReadable
      if healthReadable then stats.readableHealthCount = stats.readableHealthCount + 1 end

      if readResourceProperty(stats, playerState, 'Crystals', index, isLocal) then
        stats.readableCrystalsCount = stats.readableCrystalsCount + 1
      end
      if readResourceProperty(stats, playerState, 'Keys', index, isLocal) then
        stats.readableKeysCount = stats.readableKeysCount + 1
      end

      local slotsReadable = false
      for _, fieldName in ipairs({ 'NumWeaponModSlots', 'NumAbilityModSlots', 'NumMeleeModSlots', 'NumPerkSlots' }) do
        slotsReadable = readResourceProperty(stats, playerState, fieldName, index, isLocal) or slotsReadable
      end
      if slotsReadable then stats.readableSlotsCount = stats.readableSlotsCount + 1 end

      local equipmentReadable = false
      for _, fieldName in ipairs({ 'WeaponDA', 'AbilityDA', 'MeleeDA' }) do
        equipmentReadable = readResourceProperty(stats, playerState, fieldName, index, isLocal) or equipmentReadable
      end
      if equipmentReadable then stats.readableEquipmentCount = stats.readableEquipmentCount + 1 end

      local inventoryReadable = false
      for _, fieldName in ipairs({ 'WeaponMods', 'AbilityMods', 'MeleeMods', 'Perks', 'Relics' }) do
        inventoryReadable = readInventoryArrayCount(stats, playerState, fieldName, index, isLocal) or inventoryReadable
      end
      if inventoryReadable then stats.readableInventoryArrayCount = stats.readableInventoryArrayCount + 1 end
    end

    local fieldsVisibleAcrossMultipleMap = {}
    local fieldsOnlyVisibleOnLocalMap = {}
    for fieldName, count in pairs(stats.fieldReadableCounts) do
      if count > 1 then fieldsVisibleAcrossMultipleMap[fieldName] = true end
      if count == 1 and stats.localReadableFields[fieldName] == true then fieldsOnlyVisibleOnLocalMap[fieldName] = true end
    end
    stats.fieldsVisibleAcrossMultiple = keysSorted(fieldsVisibleAcrossMultipleMap)
    stats.fieldsOnlyVisibleOnLocal = keysSorted(fieldsOnlyVisibleOnLocalMap)
    stats.fieldsNilOrErrors = keysSorted(stats.fieldsNilOrErrorsMap)

    local anyNonIdentity = stats.readableCrystalsCount > 0
      or stats.readableKeysCount > 0
      or stats.readableSlotsCount > 0
      or stats.readableEquipmentCount > 0
      or stats.readableInventoryArrayCount > 0
      or stats.readableHealthCount > 0
    stats.nonIdentityResourceCategoryEvaluated = anyNonIdentity
    if stats.sampledPlayerStateCount < 2 then
      stats.resourceVisibilityClass = anyNonIdentity and 'local-only' or 'unresolved'
      stats.supportsP2PResourceMerge = 'no'
    elseif stats.readableCrystalsCount > 1 and stats.readableSlotsCount > 1 and stats.readableEquipmentCount > 1 and stats.readableInventoryArrayCount > 1 then
      stats.resourceVisibilityClass = 'remote-visible'
      stats.supportsP2PResourceMerge = 'yes'
    elseif #stats.fieldsVisibleAcrossMultiple > 0 then
      stats.resourceVisibilityClass = 'partial'
      stats.supportsP2PResourceMerge = 'partial'
    else
      stats.resourceVisibilityClass = 'unresolved'
      stats.supportsP2PResourceMerge = 'no'
    end

    local identitySummary, display, ids = summarizeIdentitySamples(stats.samples, 'visiblePlayerCount=' .. tostring(stats.visiblePlayerCount) .. ' sampledPlayerStateCount=' .. tostring(stats.sampledPlayerStateCount) .. ' cap=' .. tostring(cap) .. ' sourcePath=FindAllOf(PlayerState,CrabPS)+FindAllOf(PlayerController,CrabPC).PlayerState')
    stats.identitySummary = identitySummary
    stats.displayNameFingerprints = display
    stats.stableIdFingerprints = ids
    ctx.cache.ResourceVisibility = stats
    return stats
  end

  local function resourceVisibilityMeta(stats, note)
    return {
      sourceScope = 'runtime_resource_visibility',
      sourcePath = 'FindAllOf(PlayerState,CrabPS)+FindAllOf(PlayerController,CrabPC).PlayerState',
      sourceClass = 'PlayerState',
      candidateClasses = { 'PlayerState', 'CrabPS', 'PlayerController', 'CrabPC' },
      visiblePlayerCount = stats.visiblePlayerCount or 0,
      sampledPlayerStateCount = stats.sampledPlayerStateCount or 0,
      visiblePlayerCap = stats.visiblePlayerCap or 16,
      displayNameFingerprints = stats.displayNameFingerprints or {},
      stableIdFingerprints = stats.stableIdFingerprints or {},
      identityRawRedacted = true,
      rawIdentityEvidence = false,
      readableCrystalsCount = stats.readableCrystalsCount or 0,
      readableKeysCount = stats.readableKeysCount or 0,
      readableSlotsCount = stats.readableSlotsCount or 0,
      readableEquipmentCount = stats.readableEquipmentCount or 0,
      readableInventoryArrayCount = stats.readableInventoryArrayCount or 0,
      readableHealthCount = stats.readableHealthCount or 0,
      resourceVisibilityClass = stats.resourceVisibilityClass or 'unresolved',
      supportsP2PResourceMerge = stats.supportsP2PResourceMerge or 'no',
      fieldsVisibleAcrossMultiple = stats.fieldsVisibleAcrossMultiple or {},
      fieldsOnlyVisibleOnLocal = stats.fieldsOnlyVisibleOnLocal or {},
      fieldsNilOrErrors = stats.fieldsNilOrErrors or {},
      nonIdentityResourceCategoryEvaluated = stats.nonIdentityResourceCategoryEvaluated == true,
      localNotes = note
    }
  end

  local function resourceVisibilitySummary(stats, category)
    return 'category=' .. tostring(category)
      .. ' visiblePlayerCount=' .. tostring(stats.visiblePlayerCount or 0)
      .. ' sampledPlayerStateCount=' .. tostring(stats.sampledPlayerStateCount or 0)
      .. ' readableCrystals=' .. tostring(stats.readableCrystalsCount or 0)
      .. ' readableSlots=' .. tostring(stats.readableSlotsCount or 0)
      .. ' readableEquipment=' .. tostring(stats.readableEquipmentCount or 0)
      .. ' readableInventoryArrayCounts=' .. tostring(stats.readableInventoryArrayCount or 0)
      .. ' class=' .. tostring(stats.resourceVisibilityClass or 'unresolved')
      .. ' rawIdentityEvidence=false'
  end

  local LOCAL_INVENTORY_ARRAY_FIELDS = { 'WeaponMods', 'AbilityMods', 'MeleeMods', 'Perks', 'Relics' }
  local LOCAL_INVENTORY_ELEMENT_DA_FIELDS = {
    WeaponMods = 'WeaponModDA',
    AbilityMods = 'AbilityModDA',
    MeleeMods = 'MeleeModDA',
    Perks = 'PerkDA',
    Relics = 'RelicDA'
  }
  local LOCAL_INVENTORY_SLOT_FIELDS = { 'NumWeaponModSlots', 'NumAbilityModSlots', 'NumMeleeModSlots', 'NumPerkSlots' }
  local LOCAL_INVENTORY_ARRAY_COUNT_CAP = 64

  local function buildLocalInventoryArrayCache(ctx)
    if ctx.cache.LocalInventoryArrays then return ctx.cache.LocalInventoryArrays end

    local playerState, playerStateErr = getCrabPlayerState(ctx)
    if playerStateErr then
      ctx.cache.LocalInventoryArrays = { error = playerStateErr }
      return ctx.cache.LocalInventoryArrays
    end

    local stats = {
      sourceScope = 'local_player_state_inventory_arrays',
      sourcePath = 'CrabPC.PlayerState',
      sourceClass = 'CrabPS',
      localPlayerStatePresent = safe.isValidObject(playerState),
      arrayFieldNames = LOCAL_INVENTORY_ARRAY_FIELDS,
      arrayValueKinds = {},
      arrayCounts = {},
      arrayCountCap = LOCAL_INVENTORY_ARRAY_COUNT_CAP,
      slotScalarValues = {},
      fieldResults = {},
      fieldsReadable = {},
      fieldsNilOrUnsupported = {},
      noElementDereference = true
    }

    if not stats.localPlayerStatePresent then
      for _, fieldName in ipairs(LOCAL_INVENTORY_ARRAY_FIELDS) do
        stats.arrayValueKinds[fieldName] = 'nil'
        stats.fieldResults[fieldName] = 'no_local_player_state'
        stats.fieldsNilOrUnsupported[#stats.fieldsNilOrUnsupported + 1] = fieldName
      end
      ctx.cache.LocalInventoryArrays = stats
      return stats
    end

    for _, fieldName in ipairs(LOCAL_INVENTORY_SLOT_FIELDS) do
      local value, err = safe.getProperty(playerState, fieldName)
      if err then
        stats.slotScalarValues[fieldName] = 'error:' .. tostring(err)
      elseif value == nil then
        stats.slotScalarValues[fieldName] = nil
      else
        stats.slotScalarValues[fieldName] = value
      end
    end

    for _, fieldName in ipairs(LOCAL_INVENTORY_ARRAY_FIELDS) do
      local value, err = safe.getProperty(playerState, fieldName)
      if err then
        stats.arrayValueKinds[fieldName] = 'error'
        stats.fieldResults[fieldName] = 'error'
        stats.fieldsNilOrUnsupported[#stats.fieldsNilOrUnsupported + 1] = fieldName
      elseif value == nil then
        stats.arrayValueKinds[fieldName] = 'nil'
        stats.fieldResults[fieldName] = 'nil'
        stats.fieldsNilOrUnsupported[#stats.fieldsNilOrUnsupported + 1] = fieldName
      else
        local kind = type(value)
        stats.arrayValueKinds[fieldName] = kind
        if kind == 'table' then
          local count, countErr = safe.countArrayLimited(value, LOCAL_INVENTORY_ARRAY_COUNT_CAP)
          if countErr then
            stats.fieldResults[fieldName] = 'unsupported'
            stats.fieldsNilOrUnsupported[#stats.fieldsNilOrUnsupported + 1] = fieldName
          else
            stats.arrayCounts[fieldName] = count
            stats.fieldResults[fieldName] = 'count'
            stats.fieldsReadable[#stats.fieldsReadable + 1] = fieldName
          end
        elseif kind == 'userdata' then
          stats.fieldResults[fieldName] = 'shape'
          stats.fieldsReadable[#stats.fieldsReadable + 1] = fieldName
        else
          stats.fieldResults[fieldName] = 'unsupported'
          stats.fieldsNilOrUnsupported[#stats.fieldsNilOrUnsupported + 1] = fieldName
        end
      end
    end

    ctx.cache.LocalInventoryArrays = stats
    return stats
  end

  local function localInventoryMeta(stats, note)
    return {
      sourceScope = stats.sourceScope,
      sourcePath = stats.sourcePath,
      sourceClass = stats.sourceClass,
      candidateClasses = { 'CrabPC', 'CrabPS' },
      localPlayerStatePresent = stats.localPlayerStatePresent == true,
      arrayFieldNames = stats.arrayFieldNames,
      arrayValueKinds = stats.arrayValueKinds,
      arrayCounts = stats.arrayCounts,
      arrayCountCap = stats.arrayCountCap,
      slotScalarValues = stats.slotScalarValues,
      fieldResults = stats.fieldResults,
      fieldsReadable = stats.fieldsReadable,
      fieldsNilOrUnsupported = stats.fieldsNilOrUnsupported,
      noElementDereference = true,
      localNotes = note
    }
  end

  local function localInventorySummary(stats, category)
    return 'category=' .. tostring(category)
      .. ' localPlayerStatePresent=' .. tostring(stats.localPlayerStatePresent == true)
      .. ' fieldsReadable=' .. tostring(#(stats.fieldsReadable or {}))
      .. ' fieldsNilOrUnsupported=' .. tostring(#(stats.fieldsNilOrUnsupported or {}))
      .. ' countCap=' .. tostring(stats.arrayCountCap or LOCAL_INVENTORY_ARRAY_COUNT_CAP)
      .. ' noElementDereference=true'
  end

  local function safeTostringKind(value)
    local ok, text = pcall(function() return tostring(value) end)
    if not ok then return 'error' end
    return type(text)
  end

  local function safeTostringPrefix(value)
    local ok, text = pcall(function() return tostring(value) end)
    if not ok then return 'error:' .. tostring(text):sub(1, 32) end
    text = tostring(text or '')
    if text:match('^userdata:') then return 'userdata:<redacted>' end
    if #text > 48 then return text:sub(1, 48) end
    return text
  end

  local function cappedMetatableKeys(value, cap)
    cap = cap or 16
    local ok, meta = pcall(function() return getmetatable(value) end)
    if not ok then return 'error', {}, tostring(meta) end
    local metaKind = type(meta)
    if metaKind ~= 'table' then return metaKind, {}, nil end
    local keys = {}
    for key, _ in pairs(meta) do
      keys[#keys + 1] = tostring(key)
      if #keys >= cap then break end
    end
    table.sort(keys)
    return 'table', keys, nil
  end

  local function safeLenOperator(value)
    local ok, result = pcall(function() return #value end)
    if ok then return result, nil end
    return nil, tostring(result)
  end

  local function buildLocalInventoryShapeConfirmCache(ctx)
    if ctx.cache.LocalInventoryShapeConfirm then return ctx.cache.LocalInventoryShapeConfirm end

    local playerState, playerStateErr = getCrabPlayerState(ctx)
    if playerStateErr then
      ctx.cache.LocalInventoryShapeConfirm = { error = playerStateErr }
      return ctx.cache.LocalInventoryShapeConfirm
    end

    local stats = {
      sourceScope = 'local_player_state_inventory_shape_confirm',
      sourcePath = 'CrabPC.PlayerState',
      sourceClass = 'CrabPS',
      localPlayerStatePresent = safe.isValidObject(playerState),
      arrayFieldNames = LOCAL_INVENTORY_ARRAY_FIELDS,
      arrayValueKinds = {},
      arrayPropertiesPresent = {},
      arrayTostringKinds = {},
      slotScalarValues = {},
      fieldResults = {},
      fieldsReadable = {},
      fieldsNilOrUnsupported = {},
      noElementDereference = true,
      noArrayCount = true,
      noArrayTraversal = true,
      noInventoryInfo = true,
      noEnhancements = true,
      crashAttributionMarker = 'shape-confirm'
    }

    if not stats.localPlayerStatePresent then
      for _, fieldName in ipairs(LOCAL_INVENTORY_ARRAY_FIELDS) do
        stats.arrayValueKinds[fieldName] = 'nil'
        stats.arrayPropertiesPresent[fieldName] = false
        stats.fieldResults[fieldName] = 'no_local_player_state'
        stats.fieldsNilOrUnsupported[#stats.fieldsNilOrUnsupported + 1] = fieldName
      end
      ctx.cache.LocalInventoryShapeConfirm = stats
      return stats
    end

    for _, fieldName in ipairs(LOCAL_INVENTORY_SLOT_FIELDS) do
      local value, err = safe.getProperty(playerState, fieldName)
      if err then
        stats.slotScalarValues[fieldName] = 'error:' .. tostring(err)
      elseif value == nil then
        stats.slotScalarValues[fieldName] = nil
      else
        stats.slotScalarValues[fieldName] = value
      end
    end

    for _, fieldName in ipairs(LOCAL_INVENTORY_ARRAY_FIELDS) do
      local value, err = safe.getProperty(playerState, fieldName)
      if err then
        stats.arrayValueKinds[fieldName] = 'error'
        stats.arrayPropertiesPresent[fieldName] = false
        stats.fieldResults[fieldName] = 'error'
        stats.fieldsNilOrUnsupported[#stats.fieldsNilOrUnsupported + 1] = fieldName
      elseif value == nil then
        stats.arrayValueKinds[fieldName] = 'nil'
        stats.arrayPropertiesPresent[fieldName] = false
        stats.fieldResults[fieldName] = 'nil'
        stats.fieldsNilOrUnsupported[#stats.fieldsNilOrUnsupported + 1] = fieldName
      else
        local kind = type(value)
        stats.arrayValueKinds[fieldName] = kind
        stats.arrayPropertiesPresent[fieldName] = true
        stats.arrayTostringKinds[fieldName] = safeTostringKind(value)
        stats.fieldResults[fieldName] = 'present'
        stats.fieldsReadable[#stats.fieldsReadable + 1] = fieldName
      end
    end

    ctx.cache.LocalInventoryShapeConfirm = stats
    return stats
  end

  local function localInventoryShapeConfirmMeta(stats, note)
    return {
      sourceScope = stats.sourceScope,
      sourcePath = stats.sourcePath,
      sourceClass = stats.sourceClass,
      candidateClasses = { 'CrabPC', 'CrabPS' },
      localPlayerStatePresent = stats.localPlayerStatePresent == true,
      arrayFieldNames = stats.arrayFieldNames,
      arrayValueKinds = stats.arrayValueKinds,
      arrayPropertiesPresent = stats.arrayPropertiesPresent,
      arrayTostringKinds = stats.arrayTostringKinds,
      slotScalarValues = stats.slotScalarValues,
      fieldResults = stats.fieldResults,
      fieldsReadable = stats.fieldsReadable,
      fieldsNilOrUnsupported = stats.fieldsNilOrUnsupported,
      noElementDereference = true,
      noArrayCount = true,
      noArrayTraversal = true,
      noInventoryInfo = true,
      noEnhancements = true,
      crashAttributionMarker = 'shape-confirm',
      localNotes = note
    }
  end

  local function localInventoryShapeConfirmSummary(stats)
    return 'category=shape-confirm'
      .. ' localPlayerStatePresent=' .. tostring(stats.localPlayerStatePresent == true)
      .. ' fieldsReadable=' .. tostring(#(stats.fieldsReadable or {}))
      .. ' fieldsNilOrUnsupported=' .. tostring(#(stats.fieldsNilOrUnsupported or {}))
      .. ' noArrayCount=true noArrayTraversal=true noElementDereference=true crashAttributionMarker=shape-confirm'
  end

  local function buildLocalInventoryUserdataIntrospectionCache(ctx)
    if ctx.cache.LocalInventoryUserdataIntrospection then return ctx.cache.LocalInventoryUserdataIntrospection end

    local playerState, playerStateErr = getCrabPlayerState(ctx)
    if playerStateErr then
      ctx.cache.LocalInventoryUserdataIntrospection = { error = playerStateErr }
      return ctx.cache.LocalInventoryUserdataIntrospection
    end

    local stats = {
      sourceScope = 'local_player_state_inventory_userdata_introspection',
      sourcePath = 'CrabPC.PlayerState',
      sourceClass = 'CrabPS',
      localPlayerStatePresent = safe.isValidObject(playerState),
      arrayFieldNames = LOCAL_INVENTORY_ARRAY_FIELDS,
      valueKinds = {},
      tostringKinds = {},
      tostringPrefixes = {},
      metatableKinds = {},
      metatableKeys = {},
      metatableErrors = {},
      lenOperatorAttempted = {},
      lenOperatorResults = {},
      lenOperatorErrors = {},
      fieldResults = {},
      fieldsReadable = {},
      fieldsNilOrUnsupported = {},
      noElementDereference = true,
      noArrayTraversal = true,
      noInventoryInfo = true,
      noEnhancements = true,
      noWrites = true,
      noRpcs = true,
      noHud = true,
      noDeepArrays = true,
      crashAttributionMarker = 'userdata-introspection'
    }

    if not stats.localPlayerStatePresent then
      for _, fieldName in ipairs(LOCAL_INVENTORY_ARRAY_FIELDS) do
        stats.valueKinds[fieldName] = 'nil'
        stats.tostringKinds[fieldName] = 'nil'
        stats.metatableKinds[fieldName] = 'nil'
        stats.lenOperatorAttempted[fieldName] = false
        stats.fieldResults[fieldName] = 'no_local_player_state'
        stats.fieldsNilOrUnsupported[#stats.fieldsNilOrUnsupported + 1] = fieldName
      end
      ctx.cache.LocalInventoryUserdataIntrospection = stats
      return stats
    end

    for _, fieldName in ipairs(LOCAL_INVENTORY_ARRAY_FIELDS) do
      local value, err = safe.getProperty(playerState, fieldName)
      if err then
        stats.valueKinds[fieldName] = 'error'
        stats.tostringKinds[fieldName] = 'error'
        stats.metatableKinds[fieldName] = 'not_attempted'
        stats.lenOperatorAttempted[fieldName] = false
        stats.fieldResults[fieldName] = 'error'
        stats.fieldsNilOrUnsupported[#stats.fieldsNilOrUnsupported + 1] = fieldName
      elseif value == nil then
        stats.valueKinds[fieldName] = 'nil'
        stats.tostringKinds[fieldName] = 'nil'
        stats.metatableKinds[fieldName] = 'nil'
        stats.lenOperatorAttempted[fieldName] = false
        stats.fieldResults[fieldName] = 'nil'
        stats.fieldsNilOrUnsupported[#stats.fieldsNilOrUnsupported + 1] = fieldName
      else
        local valueKind = type(value)
        stats.valueKinds[fieldName] = valueKind
        stats.tostringKinds[fieldName] = safeTostringKind(value)
        stats.tostringPrefixes[fieldName] = safeTostringPrefix(value)
        local metaKind, metaKeys, metaErr = cappedMetatableKeys(value, 16)
        stats.metatableKinds[fieldName] = metaKind
        stats.metatableKeys[fieldName] = metaKeys
        if metaErr then stats.metatableErrors[fieldName] = metaErr end
        stats.lenOperatorAttempted[fieldName] = true
        local lenResult, lenErr = safeLenOperator(value)
        if lenErr then
          stats.lenOperatorErrors[fieldName] = lenErr
        else
          stats.lenOperatorResults[fieldName] = lenResult
        end
        stats.fieldResults[fieldName] = 'metadata'
        stats.fieldsReadable[#stats.fieldsReadable + 1] = fieldName
      end
    end

    ctx.cache.LocalInventoryUserdataIntrospection = stats
    return stats
  end

  local function localInventoryUserdataIntrospectionMeta(stats, note)
    return {
      sourceScope = stats.sourceScope,
      sourcePath = stats.sourcePath,
      sourceClass = stats.sourceClass,
      candidateClasses = { 'CrabPC', 'CrabPS' },
      localPlayerStatePresent = stats.localPlayerStatePresent == true,
      fieldNames = stats.arrayFieldNames,
      valueKinds = stats.valueKinds,
      tostringKinds = stats.tostringKinds,
      tostringPrefixes = stats.tostringPrefixes,
      metatableKinds = stats.metatableKinds,
      metatableKeys = stats.metatableKeys,
      metatableErrors = stats.metatableErrors,
      lenOperatorAttempted = stats.lenOperatorAttempted,
      lenOperatorResults = stats.lenOperatorResults,
      lenOperatorErrors = stats.lenOperatorErrors,
      fieldResults = stats.fieldResults,
      fieldsReadable = stats.fieldsReadable,
      fieldsNilOrUnsupported = stats.fieldsNilOrUnsupported,
      noElementDereference = true,
      noArrayTraversal = true,
      noInventoryInfo = true,
      noEnhancements = true,
      noWrites = true,
      noRpcs = true,
      noHud = true,
      noDeepArrays = true,
      crashAttributionMarker = 'userdata-introspection',
      localNotes = note
    }
  end

  local function localInventoryUserdataIntrospectionSummary(stats)
    return 'category=userdata-introspection'
      .. ' localPlayerStatePresent=' .. tostring(stats.localPlayerStatePresent == true)
      .. ' fieldsReadable=' .. tostring(#(stats.fieldsReadable or {}))
      .. ' fieldsNilOrUnsupported=' .. tostring(#(stats.fieldsNilOrUnsupported or {}))
      .. ' lenOperatorAttempted=true'
      .. ' noArrayTraversal=true noElementDereference=true noInventoryInfo=true noEnhancements=true'
      .. ' crashAttributionMarker=userdata-introspection'
  end

  local function buildInventoryArrayCountReadCache(ctx)
    if ctx.cache.InventoryArrayCountRead then return ctx.cache.InventoryArrayCountRead end

    local playerState, playerStateErr = getCrabPlayerState(ctx)
    if playerStateErr then
      ctx.cache.InventoryArrayCountRead = { error = playerStateErr }
      return ctx.cache.InventoryArrayCountRead
    end

    local stats = {
      sourceScope = 'local_player_state_inventory_array_count_read',
      sourcePath = 'CrabPC.PlayerState',
      sourceClass = 'CrabPS',
      localPlayerStatePresent = safe.isValidObject(playerState),
      arrayFieldNames = LOCAL_INVENTORY_ARRAY_FIELDS,
      arrayPropertiesPresent = {},
      valueKinds = {},
      tostringPrefixes = {},
      countAttempted = {},
      countMethods = {},
      countResults = {},
      countErrors = {},
      fieldResults = {},
      fieldsReadable = {},
      fieldsNilOrUnsupported = {},
      countResultFields = {},
      noWrites = true,
      noRpcs = true,
      noHud = true,
      noDeepArrays = true,
      noInventoryTraversal = true,
      noArrayTraversal = true,
      noElementDereference = true,
      noItemDataAssetRead = true,
      noInventoryInfo = true,
      noEnhancements = true,
      noDataAssetMutation = true,
      passiveOnly = true,
      crashAttributionMarker = 'inventory-array-count-read'
    }

    if not stats.localPlayerStatePresent then
      for _, fieldName in ipairs(LOCAL_INVENTORY_ARRAY_FIELDS) do
        stats.arrayPropertiesPresent[fieldName] = false
        stats.valueKinds[fieldName] = 'nil'
        stats.tostringPrefixes[fieldName] = 'nil'
        stats.countAttempted[fieldName] = false
        stats.countMethods[fieldName] = 'not_attempted'
        stats.fieldResults[fieldName] = 'no_local_player_state'
        stats.fieldsNilOrUnsupported[#stats.fieldsNilOrUnsupported + 1] = fieldName
      end
      ctx.cache.InventoryArrayCountRead = stats
      return stats
    end

    for _, fieldName in ipairs(LOCAL_INVENTORY_ARRAY_FIELDS) do
      local value, err = safe.getProperty(playerState, fieldName)
      if err then
        stats.arrayPropertiesPresent[fieldName] = false
        stats.valueKinds[fieldName] = 'error'
        stats.tostringPrefixes[fieldName] = 'error'
        stats.countAttempted[fieldName] = false
        stats.countMethods[fieldName] = 'not_attempted'
        stats.fieldResults[fieldName] = 'property_error'
        stats.countErrors[fieldName] = tostring(err)
        stats.fieldsNilOrUnsupported[#stats.fieldsNilOrUnsupported + 1] = fieldName
      elseif value == nil then
        stats.arrayPropertiesPresent[fieldName] = false
        stats.valueKinds[fieldName] = 'nil'
        stats.tostringPrefixes[fieldName] = 'nil'
        stats.countAttempted[fieldName] = false
        stats.countMethods[fieldName] = 'not_attempted'
        stats.fieldResults[fieldName] = 'nil'
        stats.fieldsNilOrUnsupported[#stats.fieldsNilOrUnsupported + 1] = fieldName
      else
        stats.arrayPropertiesPresent[fieldName] = true
        stats.valueKinds[fieldName] = type(value)
        stats.tostringPrefixes[fieldName] = safeTostringPrefix(value)
        stats.countAttempted[fieldName] = true
        stats.countMethods[fieldName] = 'lua_len_operator_pcall'
        local countResult, countErr = safeLenOperator(value)
        if countErr then
          stats.countErrors[fieldName] = countErr
          stats.fieldResults[fieldName] = 'count_unsupported'
          stats.fieldsNilOrUnsupported[#stats.fieldsNilOrUnsupported + 1] = fieldName
        elseif type(countResult) == 'number' then
          stats.countResults[fieldName] = countResult
          stats.fieldResults[fieldName] = 'count'
          stats.fieldsReadable[#stats.fieldsReadable + 1] = fieldName
          stats.countResultFields[#stats.countResultFields + 1] = fieldName
        else
          stats.fieldResults[fieldName] = 'count_unsupported'
          stats.fieldsNilOrUnsupported[#stats.fieldsNilOrUnsupported + 1] = fieldName
        end
      end
    end

    ctx.cache.InventoryArrayCountRead = stats
    return stats
  end

  local function inventoryArrayCountReadMeta(stats, note)
    return {
      sourceScope = stats.sourceScope,
      sourcePath = stats.sourcePath,
      sourceClass = stats.sourceClass,
      candidateClasses = { 'CrabPC', 'CrabPS' },
      localPlayerStatePresent = stats.localPlayerStatePresent == true,
      arrayFieldNames = stats.arrayFieldNames or LOCAL_INVENTORY_ARRAY_FIELDS,
      arrayPropertiesPresent = stats.arrayPropertiesPresent or {},
      valueKinds = stats.valueKinds or {},
      tostringPrefixes = stats.tostringPrefixes or {},
      countAttempted = stats.countAttempted or {},
      countMethods = stats.countMethods or {},
      countResults = stats.countResults or {},
      countErrors = stats.countErrors or {},
      fieldResults = stats.fieldResults or {},
      fieldsReadable = stats.fieldsReadable or {},
      fieldsNilOrUnsupported = stats.fieldsNilOrUnsupported or {},
      countResultFields = stats.countResultFields or {},
      noWrites = true,
      noRpcs = true,
      noHud = true,
      noDeepArrays = true,
      noInventoryTraversal = true,
      noArrayTraversal = true,
      noElementDereference = true,
      noItemDataAssetRead = true,
      noInventoryInfo = true,
      noEnhancements = true,
      noDataAssetMutation = true,
      passiveOnly = true,
      crashAttributionMarker = 'inventory-array-count-read',
      localNotes = note
    }
  end

  local function inventoryArrayCountReadSummary(stats)
    return 'category=inventory-array-count-read'
      .. ' localPlayerStatePresent=' .. tostring(stats.localPlayerStatePresent == true)
      .. ' fieldsReadable=' .. tostring(#(stats.fieldsReadable or {}))
      .. ' fieldsNilOrUnsupported=' .. tostring(#(stats.fieldsNilOrUnsupported or {}))
      .. ' countResultFields=' .. tostring(#(stats.countResultFields or {}))
      .. ' countMethod=lua_len_operator_pcall'
      .. ' noInventoryTraversal=true noArrayTraversal=true noElementDereference=true noItemDataAssetRead=true noInventoryInfo=true noEnhancements=true'
      .. ' noWrites=true noRpcs=true noHud=true noDeepArrays=true noDataAssetMutation=true passiveOnly=true'
      .. ' crashAttributionMarker=inventory-array-count-read'
  end

  local function buildInventoryElementDAReadCache(ctx)
    if ctx.cache.InventoryElementDARead then return ctx.cache.InventoryElementDARead end

    local playerState, playerStateErr = getCrabPlayerState(ctx)
    if playerStateErr then
      ctx.cache.InventoryElementDARead = { error = playerStateErr }
      return ctx.cache.InventoryElementDARead
    end

    local stats = {
      sourceScope = 'local_player_state_inventory_element_da_read',
      sourcePath = 'CrabPC.PlayerState',
      sourceClass = 'CrabPS',
      localPlayerStatePresent = safe.isValidObject(playerState),
      arrayFieldNames = LOCAL_INVENTORY_ARRAY_FIELDS,
      curatedDataAssetFieldNames = LOCAL_INVENTORY_ELEMENT_DA_FIELDS,
      arrayPropertiesPresent = {},
      valueKinds = {},
      tostringPrefixes = {},
      countAttempted = {},
      countMethods = {},
      countResults = {},
      countErrors = {},
      nonEmptyArrayFields = {},
      elementAccessAttempted = {},
      elementAccessMethods = {},
      elementAccessErrors = {},
      elementPresent = {},
      elementValueKinds = {},
      elementTostringPrefixes = {},
      elementIsValid = {},
      elementIdentities = {},
      dataAssetFieldNames = {},
      dataAssetFieldResults = {},
      dataAssetIdentities = {},
      fieldResults = {},
      fieldsReadable = {},
      fieldsNilOrUnsupported = {},
      elementAccessSupported = false,
      maxElementsPerArray = 1,
      noWrites = true,
      noRpcs = true,
      noHud = true,
      noDeepArrays = true,
      noBroadDeepArrays = true,
      noArrayTraversal = true,
      noFullArrayIteration = true,
      cappedElementAccess = true,
      noInventoryInfo = true,
      noEnhancements = true,
      noLevelRead = true,
      noAccumulatedBuffRead = true,
      noDataAssetMutation = true,
      noFunctionCalls = true,
      passiveOnly = true,
      crashAttributionMarker = 'inventory-element-da-read'
    }

    local function classifyNoPlayerState(fieldName)
      stats.arrayPropertiesPresent[fieldName] = false
      stats.valueKinds[fieldName] = 'nil'
      stats.tostringPrefixes[fieldName] = 'nil'
      stats.countAttempted[fieldName] = false
      stats.countMethods[fieldName] = 'not_attempted'
      stats.elementAccessAttempted[fieldName] = false
      stats.elementAccessMethods[fieldName] = 'not_attempted'
      stats.elementPresent[fieldName] = false
      stats.elementValueKinds[fieldName] = 'nil'
      stats.dataAssetFieldNames[fieldName] = LOCAL_INVENTORY_ELEMENT_DA_FIELDS[fieldName]
      stats.dataAssetFieldResults[fieldName] = 'not_attempted'
      stats.fieldResults[fieldName] = 'no_local_player_state'
      stats.fieldsNilOrUnsupported[#stats.fieldsNilOrUnsupported + 1] = fieldName
    end

    if not stats.localPlayerStatePresent then
      for _, fieldName in ipairs(LOCAL_INVENTORY_ARRAY_FIELDS) do classifyNoPlayerState(fieldName) end
      ctx.cache.InventoryElementDARead = stats
      return stats
    end

    for _, fieldName in ipairs(LOCAL_INVENTORY_ARRAY_FIELDS) do
      stats.dataAssetFieldNames[fieldName] = LOCAL_INVENTORY_ELEMENT_DA_FIELDS[fieldName]
      local value, err = safe.getProperty(playerState, fieldName)
      if err then
        stats.arrayPropertiesPresent[fieldName] = false
        stats.valueKinds[fieldName] = 'error'
        stats.tostringPrefixes[fieldName] = 'error'
        stats.countAttempted[fieldName] = false
        stats.countMethods[fieldName] = 'not_attempted'
        stats.elementAccessAttempted[fieldName] = false
        stats.elementAccessMethods[fieldName] = 'not_attempted'
        stats.elementPresent[fieldName] = false
        stats.elementValueKinds[fieldName] = 'error'
        stats.countErrors[fieldName] = tostring(err)
        stats.dataAssetFieldResults[fieldName] = 'not_attempted'
        stats.fieldResults[fieldName] = 'property_error'
        stats.fieldsNilOrUnsupported[#stats.fieldsNilOrUnsupported + 1] = fieldName
      elseif value == nil then
        stats.arrayPropertiesPresent[fieldName] = false
        stats.valueKinds[fieldName] = 'nil'
        stats.tostringPrefixes[fieldName] = 'nil'
        stats.countAttempted[fieldName] = false
        stats.countMethods[fieldName] = 'not_attempted'
        stats.elementAccessAttempted[fieldName] = false
        stats.elementAccessMethods[fieldName] = 'not_attempted'
        stats.elementPresent[fieldName] = false
        stats.elementValueKinds[fieldName] = 'nil'
        stats.dataAssetFieldResults[fieldName] = 'not_attempted'
        stats.fieldResults[fieldName] = 'nil'
        stats.fieldsNilOrUnsupported[#stats.fieldsNilOrUnsupported + 1] = fieldName
      else
        stats.arrayPropertiesPresent[fieldName] = true
        stats.valueKinds[fieldName] = type(value)
        stats.tostringPrefixes[fieldName] = safeTostringPrefix(value)
        stats.countAttempted[fieldName] = true
        stats.countMethods[fieldName] = 'lua_len_operator_pcall'
        local countResult, countErr = safeLenOperator(value)
        if countErr then
          stats.countErrors[fieldName] = countErr
          stats.elementAccessAttempted[fieldName] = false
          stats.elementAccessMethods[fieldName] = 'not_attempted_count_unsupported'
          stats.elementPresent[fieldName] = false
          stats.elementValueKinds[fieldName] = 'unknown'
          stats.dataAssetFieldResults[fieldName] = 'not_attempted'
          stats.fieldResults[fieldName] = 'count_unsupported'
          stats.fieldsNilOrUnsupported[#stats.fieldsNilOrUnsupported + 1] = fieldName
        elseif type(countResult) == 'number' then
          stats.countResults[fieldName] = countResult
          if countResult > 0 then
            stats.nonEmptyArrayFields[#stats.nonEmptyArrayFields + 1] = fieldName
            stats.elementAccessAttempted[fieldName] = false
            stats.elementAccessMethods[fieldName] = 'unsupported_no_safe_first_element_helper'
            stats.elementAccessErrors[fieldName] = 'no safe first-element helper exists without iteration or wrapper dereference'
            stats.elementPresent[fieldName] = false
            stats.elementValueKinds[fieldName] = 'unsupported'
            stats.elementTostringPrefixes[fieldName] = 'unsupported'
            stats.elementIsValid[fieldName] = false
            stats.dataAssetFieldResults[fieldName] = 'not_attempted_element_access_unsupported'
            stats.fieldResults[fieldName] = 'element_access_unsupported'
            stats.fieldsNilOrUnsupported[#stats.fieldsNilOrUnsupported + 1] = fieldName
          else
            stats.elementAccessAttempted[fieldName] = false
            stats.elementAccessMethods[fieldName] = 'not_attempted_empty_array'
            stats.elementPresent[fieldName] = false
            stats.elementValueKinds[fieldName] = 'nil'
            stats.elementTostringPrefixes[fieldName] = 'nil'
            stats.elementIsValid[fieldName] = false
            stats.dataAssetFieldResults[fieldName] = 'not_attempted_empty_array'
            stats.fieldResults[fieldName] = 'empty_array'
            stats.fieldsReadable[#stats.fieldsReadable + 1] = fieldName
          end
        else
          stats.elementAccessAttempted[fieldName] = false
          stats.elementAccessMethods[fieldName] = 'not_attempted_count_unsupported'
          stats.elementPresent[fieldName] = false
          stats.elementValueKinds[fieldName] = 'unknown'
          stats.dataAssetFieldResults[fieldName] = 'not_attempted'
          stats.fieldResults[fieldName] = 'count_unsupported'
          stats.fieldsNilOrUnsupported[#stats.fieldsNilOrUnsupported + 1] = fieldName
        end
      end
    end

    ctx.cache.InventoryElementDARead = stats
    return stats
  end

  local function inventoryElementDAReadMeta(stats, note)
    return {
      sourceScope = stats.sourceScope,
      sourcePath = stats.sourcePath,
      sourceClass = stats.sourceClass,
      candidateClasses = { 'CrabPC', 'CrabPS', 'CrabWeaponMod', 'CrabAbilityMod', 'CrabMeleeMod', 'CrabPerk', 'CrabRelic' },
      localPlayerStatePresent = stats.localPlayerStatePresent == true,
      arrayFieldNames = stats.arrayFieldNames or LOCAL_INVENTORY_ARRAY_FIELDS,
      curatedDataAssetFieldNames = stats.curatedDataAssetFieldNames or LOCAL_INVENTORY_ELEMENT_DA_FIELDS,
      arrayPropertiesPresent = stats.arrayPropertiesPresent or {},
      valueKinds = stats.valueKinds or {},
      tostringPrefixes = stats.tostringPrefixes or {},
      countAttempted = stats.countAttempted or {},
      countMethods = stats.countMethods or {},
      countResults = stats.countResults or {},
      countErrors = stats.countErrors or {},
      nonEmptyArrayFields = stats.nonEmptyArrayFields or {},
      elementAccessAttempted = stats.elementAccessAttempted or {},
      elementAccessMethods = stats.elementAccessMethods or {},
      elementAccessErrors = stats.elementAccessErrors or {},
      elementPresent = stats.elementPresent or {},
      elementValueKinds = stats.elementValueKinds or {},
      elementTostringPrefixes = stats.elementTostringPrefixes or {},
      elementIsValid = stats.elementIsValid or {},
      elementIdentities = stats.elementIdentities or {},
      dataAssetFieldNames = stats.dataAssetFieldNames or {},
      dataAssetFieldResults = stats.dataAssetFieldResults or {},
      dataAssetIdentities = stats.dataAssetIdentities or {},
      fieldResults = stats.fieldResults or {},
      fieldsReadable = stats.fieldsReadable or {},
      fieldsNilOrUnsupported = stats.fieldsNilOrUnsupported or {},
      elementAccessSupported = stats.elementAccessSupported == true,
      maxElementsPerArray = 1,
      noWrites = true,
      noRpcs = true,
      noHud = true,
      noDeepArrays = true,
      noBroadDeepArrays = true,
      noArrayTraversal = true,
      noFullArrayIteration = true,
      cappedElementAccess = true,
      noInventoryInfo = true,
      noEnhancements = true,
      noLevelRead = true,
      noAccumulatedBuffRead = true,
      noDataAssetMutation = true,
      noFunctionCalls = true,
      passiveOnly = true,
      crashAttributionMarker = 'inventory-element-da-read',
      localNotes = note
    }
  end

  local function inventoryElementDAReadSummary(stats)
    return 'category=inventory-element-da-read'
      .. ' localPlayerStatePresent=' .. tostring(stats.localPlayerStatePresent == true)
      .. ' nonEmptyArrayFields=' .. tostring(#(stats.nonEmptyArrayFields or {}))
      .. ' elementAccessSupported=' .. tostring(stats.elementAccessSupported == true)
      .. ' maxElementsPerArray=1'
      .. ' curatedDAFields=WeaponModDA,AbilityModDA,MeleeModDA,PerkDA,RelicDA'
      .. ' noArrayTraversal=true noFullArrayIteration=true cappedElementAccess=true noInventoryInfo=true noEnhancements=true noLevelRead=true noAccumulatedBuffRead=true'
      .. ' noWrites=true noRpcs=true noHud=true noBroadDeepArrays=true noDataAssetMutation=true noFunctionCalls=true passiveOnly=true'
      .. ' crashAttributionMarker=inventory-element-da-read'
  end

  local function integerLikeUInt32(value)
    if type(value) ~= 'number' then return false, false end
    if value ~= value or value == math.huge or value == -math.huge then return false, false end
    local integerLike = math.floor(value) == value
    local inRange = integerLike and value >= 0 and value <= 4294967295
    return integerLike, inRange
  end

  local function integerLikeByte(value)
    if type(value) ~= 'number' then return false, false end
    if value ~= value or value == math.huge or value == -math.huge then return false, false end
    local integerLike = math.floor(value) == value
    local inRange = integerLike and value >= 0 and value <= 255
    return integerLike, inRange
  end

  local function buildCrystalsReadCache(ctx)
    if ctx.cache.CrystalsRead then return ctx.cache.CrystalsRead end

    local playerState, playerStateErr = getCrabPlayerState(ctx)
    if playerStateErr then
      ctx.cache.CrystalsRead = { error = playerStateErr }
      return ctx.cache.CrystalsRead
    end

    local stats = {
      sourceScope = 'local_player_state_crystals',
      sourcePath = 'CrabPC.PlayerState',
      sourceClass = 'CrabPS',
      localPlayerStatePresent = safe.isValidObject(playerState),
      crystalsReadAttempted = false,
      crystalsPresent = false,
      crystalsValue = nil,
      crystalsValueKind = 'nil',
      crystalsIntegerLike = false,
      crystalsInUInt32Range = false,
      noElementDereference = true,
      noArrayCount = true,
      noArrayTraversal = true,
      noInventoryInfo = true,
      noEnhancements = true,
      noWrites = true,
      noRpcs = true,
      noHud = true,
      noDeepArrays = true,
      crashAttributionMarker = 'crystals-read'
    }

    if not stats.localPlayerStatePresent then
      ctx.cache.CrystalsRead = stats
      return stats
    end

    stats.crystalsReadAttempted = true
    local value, err = safe.getProperty(playerState, 'Crystals')
    if err then
      stats.error = 'Crystals: ' .. tostring(err)
      ctx.cache.CrystalsRead = stats
      return stats
    end
    stats.crystalsValueKind = type(value)
    if value ~= nil then
      stats.crystalsPresent = true
      stats.crystalsValue = value
      stats.crystalsIntegerLike, stats.crystalsInUInt32Range = integerLikeUInt32(value)
    end

    ctx.cache.CrystalsRead = stats
    return stats
  end

  local function crystalsReadMeta(stats, note)
    return {
      sourceScope = stats.sourceScope,
      sourcePath = stats.sourcePath,
      sourceClass = stats.sourceClass,
      candidateClasses = { 'CrabPC', 'CrabPS' },
      localPlayerStatePresent = stats.localPlayerStatePresent == true,
      crystalsReadAttempted = stats.crystalsReadAttempted == true,
      crystalsPresent = stats.crystalsPresent == true,
      crystalsValue = stats.crystalsValue,
      crystalsValueKind = stats.crystalsValueKind,
      crystalsIntegerLike = stats.crystalsIntegerLike == true,
      crystalsInUInt32Range = stats.crystalsInUInt32Range == true,
      noElementDereference = true,
      noArrayCount = true,
      noArrayTraversal = true,
      noInventoryInfo = true,
      noEnhancements = true,
      noWrites = true,
      noRpcs = true,
      noHud = true,
      noDeepArrays = true,
      crashAttributionMarker = 'crystals-read',
      localNotes = note
    }
  end

  local function crystalsReadSummary(stats)
    return 'category=crystals-read'
      .. ' localPlayerStatePresent=' .. tostring(stats.localPlayerStatePresent == true)
      .. ' crystalsReadAttempted=' .. tostring(stats.crystalsReadAttempted == true)
      .. ' crystalsPresent=' .. tostring(stats.crystalsPresent == true)
      .. ' crystalsValueKind=' .. tostring(stats.crystalsValueKind or 'nil')
      .. ' crystalsIntegerLike=' .. tostring(stats.crystalsIntegerLike == true)
      .. ' crystalsInUInt32Range=' .. tostring(stats.crystalsInUInt32Range == true)
      .. ' noArrayTraversal=true noElementDereference=true noInventoryInfo=true noEnhancements=true'
      .. ' noWrites=true noRpcs=true noHud=true noDeepArrays=true crashAttributionMarker=crystals-read'
  end

  local function buildSlotsReadCache(ctx)
    if ctx.cache.SlotsRead then return ctx.cache.SlotsRead end

    local playerState, playerStateErr = getCrabPlayerState(ctx)
    if playerStateErr then
      ctx.cache.SlotsRead = { error = playerStateErr }
      return ctx.cache.SlotsRead
    end

    local stats = {
      sourceScope = 'local_player_state_slots',
      sourcePath = 'CrabPC.PlayerState',
      sourceClass = 'CrabPS',
      localPlayerStatePresent = safe.isValidObject(playerState),
      slotsReadAttempted = false,
      slotFieldNames = LOCAL_INVENTORY_SLOT_FIELDS,
      slotScalarValues = {},
      slotValueKinds = {},
      slotIntegerLike = {},
      slotValuesInByteRange = {},
      fieldResults = {},
      fieldsReadable = {},
      fieldsNilOrUnsupported = {},
      lockedSlotModel = 'unresolved; no separate locked/max/total slot field found in tracked objectdump-derived notes',
      noElementDereference = true,
      noArrayCount = true,
      noArrayTraversal = true,
      noInventoryInfo = true,
      noEnhancements = true,
      noWrites = true,
      noRpcs = true,
      noHud = true,
      noDeepArrays = true,
      crashAttributionMarker = 'slots-read'
    }

    if not stats.localPlayerStatePresent then
      for _, fieldName in ipairs(LOCAL_INVENTORY_SLOT_FIELDS) do
        stats.slotValueKinds[fieldName] = 'nil'
        stats.fieldResults[fieldName] = 'no_local_player_state'
        stats.fieldsNilOrUnsupported[#stats.fieldsNilOrUnsupported + 1] = fieldName
      end
      ctx.cache.SlotsRead = stats
      return stats
    end

    stats.slotsReadAttempted = true
    for _, fieldName in ipairs(LOCAL_INVENTORY_SLOT_FIELDS) do
      local value, err = safe.getProperty(playerState, fieldName)
      if err then
        stats.slotValueKinds[fieldName] = 'error'
        stats.fieldResults[fieldName] = 'error: ' .. tostring(err)
        stats.fieldsNilOrUnsupported[#stats.fieldsNilOrUnsupported + 1] = fieldName
      elseif value == nil then
        stats.slotValueKinds[fieldName] = 'nil'
        stats.fieldResults[fieldName] = 'nil'
        stats.fieldsNilOrUnsupported[#stats.fieldsNilOrUnsupported + 1] = fieldName
      else
        local integerLike, inRange = integerLikeByte(value)
        stats.slotScalarValues[fieldName] = value
        stats.slotValueKinds[fieldName] = type(value)
        stats.slotIntegerLike[fieldName] = integerLike
        stats.slotValuesInByteRange[fieldName] = inRange
        stats.fieldResults[fieldName] = inRange and 'byte' or 'out_of_byte_range'
        stats.fieldsReadable[#stats.fieldsReadable + 1] = fieldName
      end
    end

    ctx.cache.SlotsRead = stats
    return stats
  end

  local function slotsReadMeta(stats, note)
    return {
      sourceScope = stats.sourceScope,
      sourcePath = stats.sourcePath,
      sourceClass = stats.sourceClass,
      candidateClasses = { 'CrabPC', 'CrabPS' },
      localPlayerStatePresent = stats.localPlayerStatePresent == true,
      slotsReadAttempted = stats.slotsReadAttempted == true,
      slotFieldNames = stats.slotFieldNames or LOCAL_INVENTORY_SLOT_FIELDS,
      slotScalarValues = stats.slotScalarValues or {},
      slotValueKinds = stats.slotValueKinds or {},
      slotIntegerLike = stats.slotIntegerLike or {},
      slotValuesInByteRange = stats.slotValuesInByteRange or {},
      fieldResults = stats.fieldResults or {},
      fieldsReadable = stats.fieldsReadable or {},
      fieldsNilOrUnsupported = stats.fieldsNilOrUnsupported or {},
      lockedSlotModel = stats.lockedSlotModel,
      noElementDereference = true,
      noArrayCount = true,
      noArrayTraversal = true,
      noInventoryInfo = true,
      noEnhancements = true,
      noWrites = true,
      noRpcs = true,
      noHud = true,
      noDeepArrays = true,
      crashAttributionMarker = 'slots-read',
      localNotes = note
    }
  end

  local function slotsReadSummary(stats)
    return 'category=slots-read'
      .. ' localPlayerStatePresent=' .. tostring(stats.localPlayerStatePresent == true)
      .. ' slotsReadAttempted=' .. tostring(stats.slotsReadAttempted == true)
      .. ' fieldsReadable=' .. tostring(#(stats.fieldsReadable or {}))
      .. ' fieldsNilOrUnsupported=' .. tostring(#(stats.fieldsNilOrUnsupported or {}))
      .. ' lockedSlotModel=unresolved'
      .. ' noArrayCount=true noArrayTraversal=true noElementDereference=true noInventoryInfo=true noEnhancements=true'
      .. ' noWrites=true noRpcs=true noHud=true noDeepArrays=true crashAttributionMarker=slots-read'
  end

  local SAFE_SCALAR_WATCH_EQUIPMENT_FIELDS = { 'WeaponDA', 'AbilityDA', 'MeleeDA' }
  local SAFE_SCALAR_WATCH_HEALTH_FIELDS = { 'CurrentHealth', 'CurrentMaxHealth', 'BaseMaxHealth', 'MaxHealthMultiplier' }

  local function copyTable(input)
    local output = {}
    for key, value in pairs(input or {}) do
      if type(value) == 'table' then
        output[key] = copyTable(value)
      else
        output[key] = value
      end
    end
    return output
  end

  local function sortedKeys(map)
    local keys = {}
    for key, _ in pairs(map or {}) do
      keys[#keys + 1] = tostring(key)
    end
    table.sort(keys)
    return keys
  end

  local function valueKey(value)
    if value == nil then return '<nil>' end
    return type(value) .. ':' .. tostring(value)
  end

  local function tableContains(list, value)
    for _, item in ipairs(list or {}) do
      if item == value then return true end
    end
    return false
  end

  local function positiveConfigNumber(value, fallback)
    if type(value) == 'number' and value > 0 then return value end
    return fallback
  end

  local function safeScalarWatchReadProperty(stats, playerState, fieldName)
    local value, err = safe.getProperty(playerState, fieldName)
    if err then
      stats.values[fieldName] = nil
      stats.valueKinds[fieldName] = 'error'
      stats.fieldResults[fieldName] = 'error: ' .. tostring(err)
      return
    end
    stats.values[fieldName] = value
    stats.valueKinds[fieldName] = type(value)
    stats.fieldResults[fieldName] = value == nil and 'nil' or 'read'
  end

  local function safeScalarWatchReadEquipment(stats, playerState, fieldName)
    local value, err = safe.getProperty(playerState, fieldName)
    if err then
      stats.values[fieldName] = nil
      stats.valueKinds[fieldName] = 'error'
      stats.fieldResults[fieldName] = 'error: ' .. tostring(err)
      return
    end
    stats.valueKinds[fieldName] = type(value)
    if value == nil then
      stats.values[fieldName] = nil
      stats.fieldResults[fieldName] = 'nil'
      return
    end
    local summary, summaryErr = summarizeIdentityOrDefault(value, fieldName .. ' via property')
    stats.values[fieldName] = summary
    stats.fieldResults[fieldName] = summaryErr and ('identity_error: ' .. tostring(summaryErr)) or 'read'
  end

  local function safeScalarWatchReadHealth(stats, playerState)
    local healthInfo, healthInfoErr = safe.getProperty(playerState, 'HealthInfo')
    stats.valueKinds.HealthInfo = type(healthInfo)
    if healthInfoErr then
      stats.fieldResults.HealthInfo = 'error: ' .. tostring(healthInfoErr)
      for _, fieldName in ipairs({ 'CurrentHealth', 'CurrentMaxHealth' }) do
        stats.values[fieldName] = nil
        stats.valueKinds[fieldName] = 'error'
        stats.fieldResults[fieldName] = 'HealthInfo error'
      end
    elseif healthInfo == nil then
      stats.fieldResults.HealthInfo = 'nil'
      for _, fieldName in ipairs({ 'CurrentHealth', 'CurrentMaxHealth' }) do
        stats.values[fieldName] = nil
        stats.valueKinds[fieldName] = 'nil'
        stats.fieldResults[fieldName] = 'HealthInfo nil'
      end
    else
      stats.fieldResults.HealthInfo = 'read'
      for _, fieldName in ipairs({ 'CurrentHealth', 'CurrentMaxHealth' }) do
        local value, err = safe.getStructField(healthInfo, fieldName)
        if err then
          stats.values[fieldName] = nil
          stats.valueKinds[fieldName] = 'error'
          stats.fieldResults[fieldName] = 'error: ' .. tostring(err)
        else
          stats.values[fieldName] = value
          stats.valueKinds[fieldName] = type(value)
          stats.fieldResults[fieldName] = value == nil and 'nil' or 'read'
        end
      end
    end

    for _, fieldName in ipairs({ 'BaseMaxHealth', 'MaxHealthMultiplier' }) do
      safeScalarWatchReadProperty(stats, playerState, fieldName)
    end
  end

  local function buildSafeScalarWatchSample(ctx)
    local stats = {
      sourceScope = 'local_safe_scalar_watch',
      sourcePath = 'CrabPC.PlayerState',
      sourceClass = 'CrabPS',
      playerStatePresent = false,
      values = {
        context = tostring(ctx.lastContext or 'unknown'),
        role = tostring(ctx.role or 'unknown'),
        lifecycleState = tostring(ctx.lifecycleState or 'unknown')
      },
      valueKinds = {
        context = 'string',
        role = 'string',
        lifecycleState = 'string'
      },
      fieldResults = {
        context = 'runtime_context',
        role = 'runtime_context',
        lifecycleState = 'runtime_context'
      },
      error = nil
    }

    local playerState, playerStateErr = getCrabPlayerState(ctx)
    if playerStateErr then
      stats.error = playerStateErr
      stats.fieldResults.PlayerState = 'error: ' .. tostring(playerStateErr)
      return stats
    end

    stats.playerStatePresent = safe.isValidObject(playerState)
    stats.values.playerStatePresent = stats.playerStatePresent
    stats.valueKinds.playerStatePresent = 'boolean'
    stats.fieldResults.PlayerState = stats.playerStatePresent and 'read' or 'absent'
    if not stats.playerStatePresent then
      return stats
    end

    for _, fieldName in ipairs(SAFE_SCALAR_WATCH_EQUIPMENT_FIELDS) do
      safeScalarWatchReadEquipment(stats, playerState, fieldName)
    end
    safeScalarWatchReadProperty(stats, playerState, 'Crystals')
    for _, fieldName in ipairs(LOCAL_INVENTORY_SLOT_FIELDS) do
      safeScalarWatchReadProperty(stats, playerState, fieldName)
    end
    safeScalarWatchReadHealth(stats, playerState)

    return stats
  end

  local function safeScalarWatchChangedFields(previous, current)
    local changed = {}
    local seen = {}
    for key, _ in pairs(previous or {}) do seen[key] = true end
    for key, _ in pairs(current or {}) do seen[key] = true end
    for _, key in ipairs(sortedKeys(seen)) do
      if valueKey(previous and previous[key]) ~= valueKey(current and current[key]) then
        changed[#changed + 1] = key
      end
    end
    return changed
  end

  local function updateSafeScalarWatchAggregates(state, sample, changed)
    state.latestValues = copyTable(sample.values)
    state.lastContext = sample.values.context
    state.lastRole = sample.values.role
    if not state.firstValues then
      state.firstValues = copyTable(sample.values)
      state.firstContext = sample.values.context
      state.firstRole = sample.values.role
    end

    for fieldName, value in pairs(sample.values or {}) do
      if type(value) == 'number' then
        if state.minValues[fieldName] == nil or value < state.minValues[fieldName] then
          state.minValues[fieldName] = value
        end
        if state.maxValues[fieldName] == nil or value > state.maxValues[fieldName] then
          state.maxValues[fieldName] = value
        end
      end
    end

    if #changed > 0 then
      state.changedSamples = state.changedSamples + 1
      for _, fieldName in ipairs(changed) do
        if state.changeCounts[fieldName] == nil then state.changeCounts[fieldName] = 0 end
        state.changeCounts[fieldName] = state.changeCounts[fieldName] + 1
        if not tableContains(state.changedFields, fieldName) then
          state.changedFields[#state.changedFields + 1] = fieldName
          table.sort(state.changedFields)
        end
      end
    else
      state.noChangeSamples = state.noChangeSamples + 1
    end
  end

  local function safeScalarWatchMeta(sample, watchState, reason, changed)
    local slotChanged = false
    for _, fieldName in ipairs(LOCAL_INVENTORY_SLOT_FIELDS) do
      if tableContains(watchState.changedFields, fieldName) then
        slotChanged = true
      end
    end
    local slotStatus = slotChanged
      and 'Num*Slots changed across lifecycle/gameplay state; locked/max/total slot model unresolved'
      or 'observed scalar slot counters / candidate unlocked or usable slot counters; locked/max/total slot model unresolved'
    return {
      sourceScope = sample.sourceScope,
      sourcePath = sample.sourcePath,
      sourceClass = sample.sourceClass,
      candidateClasses = { 'CrabPC', 'CrabPS' },
      playerStatePresent = sample.playerStatePresent == true,
      localPlayerStatePresent = sample.playerStatePresent == true,
      sampleReason = reason,
      sampleChanged = #changed > 0,
      safeWatchSampleCount = watchState.sampleCount,
      safeWatchLoggedCount = watchState.loggedCount,
      safeWatchFirstValues = watchState.firstValues or {},
      safeWatchLatestValues = watchState.latestValues or {},
      safeWatchMinValues = watchState.minValues or {},
      safeWatchMaxValues = watchState.maxValues or {},
      safeWatchChangedFields = watchState.changedFields or {},
      safeWatchChangeCounts = watchState.changeCounts or {},
      safeWatchNoChangeSamples = watchState.noChangeSamples,
      safeWatchChangedSamples = watchState.changedSamples,
      firstContext = watchState.firstContext or '',
      lastContext = watchState.lastContext or '',
      firstRole = watchState.firstRole or '',
      lastRole = watchState.lastRole or '',
      fieldResults = sample.fieldResults or {},
      valueKinds = sample.valueKinds or {},
      slotScalarValues = {
        NumWeaponModSlots = sample.values.NumWeaponModSlots,
        NumAbilityModSlots = sample.values.NumAbilityModSlots,
        NumMeleeModSlots = sample.values.NumMeleeModSlots,
        NumPerkSlots = sample.values.NumPerkSlots
      },
      lockedSlotModel = slotStatus,
      noElementDereference = true,
      noArrayCount = true,
      noArrayTraversal = true,
      noInventoryInfo = true,
      noEnhancements = true,
      noWrites = true,
      noRpcs = true,
      noHud = true,
      noDeepArrays = true,
      crashAttributionMarker = 'safe-scalar-watch',
      localNotes = 'Read-only watch of already confirmed local scalar/property paths; no inventory arrays, array count/traversal, InventoryInfo, Enhancements, writes, RPCs, HUD, or deep arrays'
    }
  end

  local function safeScalarWatchSummary(sample, watchState, reason, changed)
    local changedText = #changed > 0 and table.concat(changed, ',') or 'none'
    return 'category=safe-scalar-watch'
      .. ' sampleCount=' .. tostring(watchState.sampleCount)
      .. ' loggedCount=' .. tostring(watchState.loggedCount)
      .. ' reason=' .. tostring(reason)
      .. ' playerStatePresent=' .. tostring(sample.playerStatePresent == true)
      .. ' changed=' .. tostring(#changed > 0)
      .. ' changedFields=' .. changedText
      .. ' slotModel=observed scalar slot counters / candidate unlocked or usable slot counters; locked/max/total unresolved'
      .. ' noArrayCount=true noArrayTraversal=true noElementDereference=true noInventoryInfo=true noEnhancements=true'
      .. ' noWrites=true noRpcs=true noHud=true noDeepArrays=true crashAttributionMarker=safe-scalar-watch'
  end

  local function readSafeScalarWatchSample(ctx)
    local cfg = ctx.config or {}
    local intervalSeconds = positiveConfigNumber(cfg.safeScalarWatchIntervalSeconds, 5)
    local heartbeatSeconds = positiveConfigNumber(cfg.safeScalarWatchHeartbeatSeconds, 60)
    local maxSamples = positiveConfigNumber(cfg.safeScalarWatchMaxSamples, 240)
    local now = os.time()
    local state = ctx.cache.SafeScalarWatch
    if not state then
      state = {
        sampleCount = 0,
        loggedCount = 0,
        noChangeSamples = 0,
        changedSamples = 0,
        changedFields = {},
        changeCounts = {},
        minValues = {},
        maxValues = {},
        firstValues = nil,
        latestValues = {},
        lastLoggedValues = nil,
        lastSampleAt = nil,
        lastHeartbeatAt = nil,
        firstContext = '',
        lastContext = '',
        firstRole = '',
        lastRole = ''
      }
      ctx.cache.SafeScalarWatch = state
    end

    if state.sampleCount >= maxSamples then
      return 'skipped_by_config', 'safe_scalar_watch', 'safe scalar watch maxSamples reached', nil, { suppressEmit = true }
    end
    if state.lastSampleAt ~= nil and (now - state.lastSampleAt) < intervalSeconds then
      return 'skipped_by_config', 'safe_scalar_watch', 'waiting for next safe scalar watch interval', nil, { suppressEmit = true }
    end

    local sample = buildSafeScalarWatchSample(ctx)
    state.sampleCount = state.sampleCount + 1
    state.lastSampleAt = now

    local firstLoggedSample = state.lastLoggedValues == nil
    local changed = firstLoggedSample and {} or safeScalarWatchChangedFields(state.lastLoggedValues, sample.values)
    updateSafeScalarWatchAggregates(state, sample, changed)

    local reason = nil
    if firstLoggedSample then
      reason = sample.playerStatePresent and 'first_successful_sample' or 'playerstate_absent'
    elseif #changed > 0 then
      reason = 'changed'
    elseif state.lastHeartbeatAt == nil or (now - state.lastHeartbeatAt) >= heartbeatSeconds then
      reason = 'heartbeat'
    else
      return 'ok', 'safe_scalar_watch', 'safe scalar watch sample unchanged', nil, { suppressEmit = true }
    end

    if reason == 'heartbeat' then
      state.lastHeartbeatAt = now
    end
    state.loggedCount = state.loggedCount + 1
    state.lastLoggedValues = copyTable(sample.values)

    local meta = safeScalarWatchMeta(sample, state, reason, changed)
    local summary = safeScalarWatchSummary(sample, state, reason, changed)
    if sample.error then
      return 'lua_error', 'safe_scalar_watch', summary, sample.error, meta
    end
    return sample.playerStatePresent and 'ok' or 'nil', 'safe_scalar_watch', summary, nil, meta
  end

  local PERK_DA_CLASS_CANDIDATES = {
    'CrabPerkDA',
    'CrabPerkDataAsset',
    'PerkDataAsset',
    'CrabPerk'
  }

  local PERK_DA_SOURCE_REF_FIELDS = {
    CrabPerk = 'PerkDA'
  }

  local CATALOG_REJECTION_REASON_ORDER = {
    'invalid_uobject',
    'class_filter_mismatch',
    'name_filter_mismatch',
    'class_and_name_filter_mismatch',
    'no_dataasset_reference',
    'field_read_errors',
    'unsupported_value_types',
    'duplicate_catalog_entry'
  }

  local PERK_DA_FIELD_ALLOWLIST = {
    'Name',
    'DisplayName',
    'Title',
    'Description',
    'DescriptionText',
    'ShortDescription',
    'FlavorText',
    'Rarity',
    'PerkRarity',
    'Tier',
    'PerkTier',
    'Type',
    'PerkType',
    'Category',
    'Tags',
    'GameplayTag',
    'Icon',
    'Texture',
    'Material',
    'Color',
    'MaxStacks',
    'StackLimit',
    'BaseValue',
    'Value',
    'Multiplier',
    'Cooldown',
    'Duration',
    'Weight',
    'bEnabled',
    'bCanStack',
    'bHidden',
    'bUnlockedByDefault'
  }

  local function clampCatalogLimit(value, fallback, hardCap)
    local numberValue = tonumber(value)
    if numberValue == nil or numberValue < 1 then numberValue = fallback end
    numberValue = math.floor(numberValue)
    if numberValue > hardCap then numberValue = hardCap end
    return numberValue
  end

  local function sanitizeCatalogText(value)
    local text = tostring(value or '')
    text = text:gsub('[\r\n\t]+', ' ')
    text = text:gsub('%s%s+', ' ')
    if #text > 160 then text = text:sub(1, 157) .. '...' end
    return text
  end

  local function perkCatalogSafetyMeta(extra)
    local meta = {
      sourceScope = 'perk_data_asset_catalog',
      sourcePath = 'objectdump/docs-index curated class list -> FindAllOf(CrabPerkDA,CrabPerkDataAsset,PerkDataAsset,CrabPerk.PerkDA)',
      sourceClass = 'CrabPerkDA',
      candidateClasses = PERK_DA_CLASS_CANDIDATES,
      noWrites = true,
      noRpcs = true,
      noHud = true,
      noDeepArrays = true,
      noInventoryArrays = true,
      noArrayCount = true,
      noArrayTraversal = true,
      noElementDereference = true,
      noInventoryInfo = true,
      noEnhancements = true,
      noDataAssetMutation = true,
      noFunctionCalls = true,
      passiveOnly = true,
      crashAttributionMarker = 'perk-da-catalog-read',
      localNotes = 'Read-only curated FindAllOf class/name discovery for perk DataAssets; no live inventory arrays, InventoryInfo, Enhancements, DataAsset mutation, gameplay/RPC calls, or nested object walking'
    }
    for key, value in pairs(extra or {}) do meta[key] = value end
    return meta
  end

  local function addCatalogPattern(patterns, seen, value)
    local text = tostring(value or '')
    if text == '' or seen[text] then return end
    seen[text] = true
    patterns[#patterns + 1] = text
  end

  local function perkDataAssetIdentitySignals(identity, className)
    local fullName = tostring((identity and identity.fullName) or '')
    local shortName = tostring((identity and identity.shortName) or '')
    local objectClass = tostring(className or (identity and identity.objectClass) or '')
    local combined = fullName .. ' ' .. shortName .. ' ' .. objectClass
    local patterns = {}
    local seen = {}
    local classMatch = false
    local nameMatch = false
    if objectClass:find('CrabPerk') or objectClass:find('PerkDA') or objectClass:find('PerkDataAsset') then
      classMatch = true
      addCatalogPattern(patterns, seen, 'class:' .. objectClass)
    end
    if combined:find('CrabPerk') or combined:find('PerkDA') or combined:find('PerkDataAsset') then
      nameMatch = true
      addCatalogPattern(patterns, seen, 'identity:PerkDataAsset')
    end
    if fullName:find('/Perk') or fullName:find('/Perks') or shortName:find('DA_Perk') or shortName:find('Perk') then
      nameMatch = true
      addCatalogPattern(patterns, seen, 'name:path-or-da-perk')
    end
    return (classMatch or nameMatch), classMatch, nameMatch, patterns
  end

  local function isPerkDataAssetIdentity(identity, className)
    local accepted = perkDataAssetIdentitySignals(identity, className)
    return accepted == true
  end

  local function summarizeCatalogObjectReference(value)
    if value == nil then
      return 'exists=false valid=false'
    end
    if type(value) ~= 'userdata' then
      return 'exists=true valid=unsupported kind=' .. type(value)
    end
    local valid = safe.isValidObject(value)
    if not valid then return 'exists=true valid=false' end
    local fullName = safe.getFullName(value)
    local className = safe.getObjectClassName(value)
    return 'exists=true valid=true class=' .. sanitizeCatalogText(className or '') .. ' fullName=' .. sanitizeCatalogText(fullName or '')
  end

  local function classifyCatalogValue(fieldName, value)
    if value == nil then return 'nil', 'nil' end
    local kind = type(value)
    local fieldText = tostring(fieldName or '')
    if fieldText:find('Rarity') or fieldText:find('Tier') or fieldText:find('Type') or fieldText:find('Category') then
      return 'enum', sanitizeCatalogText(value)
    end
    if kind == 'boolean' then return 'bool', tostring(value) end
    if kind == 'number' then return 'scalar', tostring(value) end
    if kind == 'string' then return 'string', sanitizeCatalogText(value) end
    if kind == 'userdata' then
      return 'object_ref', summarizeCatalogObjectReference(value)
    end
    return kind, sanitizeCatalogText(value)
  end

  local function readPerkDataAssetFields(obj, fieldCap)
    local fields = {}
    local fieldNames = {}
    local statuses = {}
    local valueKinds = {}
    local objectRefs = {}
    local attempted = 0
    for _, fieldName in ipairs(PERK_DA_FIELD_ALLOWLIST) do
      if attempted >= fieldCap then break end
      attempted = attempted + 1
      fieldNames[#fieldNames + 1] = fieldName
      local value, err = safe.getProperty(obj, fieldName)
      local status = 'read'
      if err then status = 'error'
      elseif value == nil then status = 'nil' end
      local valueKind, summary = classifyCatalogValue(fieldName, value)
      if err then
        valueKind = 'unsupported'
        summary = sanitizeCatalogText(err)
      end
      fields[#fields + 1] = {
        fieldName = fieldName,
        status = status,
        valueKind = valueKind,
        valueSummary = summary
      }
      statuses[fieldName] = status
      valueKinds[fieldName] = valueKind
      if valueKind == 'object_ref' then objectRefs[fieldName] = summary end
    end
    return fields, fieldNames, statuses, valueKinds, objectRefs
  end

  local function summarizePerkCatalogFieldResults(fields)
    local summary = {
      attempted = 0,
      read = 0,
      nilCount = 0,
      errorCount = 0,
      unsupportedValueTypeCount = 0
    }
    for _, field in ipairs(fields or {}) do
      summary.attempted = summary.attempted + 1
      if field.status == 'read' then summary.read = summary.read + 1 end
      if field.status == 'nil' then summary.nilCount = summary.nilCount + 1 end
      if field.status == 'error' then summary.errorCount = summary.errorCount + 1 end
      local kind = tostring(field.valueKind or '')
      if field.status == 'read' and kind ~= 'nil' and kind ~= 'bool' and kind ~= 'scalar' and kind ~= 'string' and kind ~= 'enum' and kind ~= 'object_ref' then
        summary.unsupportedValueTypeCount = summary.unsupportedValueTypeCount + 1
      end
    end
    return summary
  end

  local function perkCatalogReadStatus(fieldSummary)
    if (fieldSummary.read or 0) > 0 and (fieldSummary.errorCount or 0) == 0 and (fieldSummary.unsupportedValueTypeCount or 0) == 0 then
      return 'allowlisted_fields_readable'
    end
    if (fieldSummary.read or 0) > 0 and (fieldSummary.unsupportedValueTypeCount or 0) > 0 then
      return 'allowlisted_fields_partially_readable_with_unsupported_value_types'
    end
    if (fieldSummary.read or 0) > 0 and (fieldSummary.errorCount or 0) > 0 then
      return 'allowlisted_fields_partially_readable_with_errors'
    end
    if (fieldSummary.errorCount or 0) > 0 then
      return 'identity_only_field_read_errors'
    end
    if (fieldSummary.unsupportedValueTypeCount or 0) > 0 then
      return 'identity_only_unsupported_value_types'
    end
    return 'identity_only_no_allowlisted_fields_readable'
  end

  local function incrementCatalogReason(reasonCounts, reason)
    local key = tostring(reason or 'unknown')
    reasonCounts[key] = (reasonCounts[key] or 0) + 1
  end

  local function appendCatalogRejection(diagnostics, reasonCounts, diagnostic, cap)
    incrementCatalogReason(reasonCounts, diagnostic.reason)
    if #diagnostics < cap then
      diagnostics[#diagnostics + 1] = diagnostic
    end
  end

  local function formatCatalogReasonCounts(reasonCounts)
    local parts = {}
    local used = {}
    for _, reason in ipairs(CATALOG_REJECTION_REASON_ORDER) do
      local count = reasonCounts[reason]
      if count and count > 0 then
        parts[#parts + 1] = reason .. '=' .. tostring(count)
        used[reason] = true
      end
    end
    for reason, count in pairs(reasonCounts or {}) do
      if not used[reason] and count and count > 0 then
        parts[#parts + 1] = tostring(reason) .. '=' .. tostring(count)
      end
    end
    return #parts > 0 and table.concat(parts, ',') or 'none'
  end

  local function addPerkCatalogPatterns(foundPatterns, foundPatternMap, patterns)
    for _, pattern in ipairs(patterns or {}) do
      addCatalogPattern(foundPatterns, foundPatternMap, pattern)
    end
  end

  local function collectPerkDataAssetCatalog(ctx)
    local candidateCap = clampCatalogLimit((ctx.config or {}).perkDataAssetCatalogMaxCandidates, 64, 128)
    local fieldCap = clampCatalogLimit((ctx.config or {}).perkDataAssetCatalogMaxFields, 32, #PERK_DA_FIELD_ALLOWLIST)
    local rejectionCap = clampCatalogLimit((ctx.config or {}).perkDataAssetCatalogMaxRejectionDiagnostics, 16, 64)
    local available, availabilityResult, availabilityErr = findAllAvailability()
    if availabilityResult == 'lua_error' then
      return 'lua_error', nil, nil, availabilityErr, perkCatalogSafetyMeta({
        discoveryAttempted = true,
        discoveryMethod = 'FindAllOfAvailability',
        catalogFound = false,
        catalogEntryCount = 0,
        catalogCandidateCount = 0,
        catalogCandidateCap = candidateCap,
        catalogFieldCap = fieldCap,
        catalogRejectionDiagnosticCap = rejectionCap
      })
    end
    if not available then
      return 'nil', 'perk_da_catalog', 'category=perk-da-catalog-read discoveryAttempted=true found=0 reason=FindAllOf unavailable noWrites=true noRpcs=true noHud=true noDeepArrays=true noInventoryArrays=true noArrayCount=true noArrayTraversal=true noElementDereference=true noInventoryInfo=true noEnhancements=true noDataAssetMutation=true noFunctionCalls=true', nil, perkCatalogSafetyMeta({
        discoveryAttempted = true,
        discoveryMethod = 'FindAllOfAvailability',
        catalogFound = false,
        catalogEntryCount = 0,
        catalogCandidateCount = 0,
        catalogCandidateCap = candidateCap,
        catalogFieldCap = fieldCap,
        catalogRejectionDiagnosticCap = rejectionCap,
        notFoundClassification = 'perk_da_catalog_not_found'
      })
    end

    local entries = {}
    local seen = {}
    local attemptedClasses = {}
    local candidateCount = 0
    local rejectedCount = 0
    local rejectionDiagnostics = {}
    local rejectionReasonCounts = {}
    local foundPatterns = {}
    local foundPatternMap = {}
    local latestFieldNames = {}
    local latestStatuses = {}
    local latestValueKinds = {}
    local latestObjectRefs = {}
    for _, className in ipairs(PERK_DA_CLASS_CANDIDATES) do
      if candidateCount >= candidateCap then break end
      attemptedClasses[#attemptedClasses + 1] = className
      local arr, err = safe.findAll(className)
      if not err and type(arr) == 'table' then
        safe.forEachArrayLimited(arr, candidateCap - candidateCount, function(_, elem)
          if candidateCount >= candidateCap then return end
          candidateCount = candidateCount + 1
          local obj = elem
          local rawValid = safe.isValidObject(obj)
          local rawSummary, rawIdentityErr, rawIdentity = safe.summarizeObjectIdentity(obj)
          local rawObjectClass, rawClassErr = safe.getObjectClassName(obj)
          local diagnosticBase = {
            candidateIndex = candidateCount,
            sourceClass = className,
            shortName = sanitizeCatalogText((rawIdentity and rawIdentity.shortName) or ''),
            fullName = sanitizeCatalogText((rawIdentity and rawIdentity.fullName) or ''),
            className = sanitizeCatalogText(rawClassErr and '' or rawObjectClass or ''),
            isValid = rawValid == true
          }

          if not rawValid then
            rejectedCount = rejectedCount + 1
            diagnosticBase.reason = 'invalid_uobject'
            diagnosticBase.identityStatus = sanitizeCatalogText(rawSummary or rawIdentityErr or 'invalid')
            appendCatalogRejection(rejectionDiagnostics, rejectionReasonCounts, diagnosticBase, rejectionCap)
            return
          end

          local catalogObj = obj
          local sourceRefField = PERK_DA_SOURCE_REF_FIELDS[className]
          local sourceShortName = diagnosticBase.shortName
          local sourceFullName = diagnosticBase.fullName
          if sourceRefField then
            local refValue, refErr = safe.getProperty(obj, sourceRefField)
            if refErr or refValue == nil or type(refValue) ~= 'userdata' or not safe.isValidObject(refValue) then
              rejectedCount = rejectedCount + 1
              diagnosticBase.reason = refErr and 'field_read_errors' or 'no_dataasset_reference'
              diagnosticBase.fieldName = sourceRefField
              diagnosticBase.fieldReadError = sanitizeCatalogText(refErr or '')
              appendCatalogRejection(rejectionDiagnostics, rejectionReasonCounts, diagnosticBase, rejectionCap)
              return
            end
            catalogObj = refValue
          end

          local _, identityErr, identity = safe.summarizeObjectIdentity(catalogObj)
          local objectClass, classErr = safe.getObjectClassName(catalogObj)
          local accepted, classMatch, nameMatch, patterns = perkDataAssetIdentitySignals(identity, classErr and '' or objectClass)
          addPerkCatalogPatterns(foundPatterns, foundPatternMap, patterns)
          if identityErr ~= nil then
            diagnosticBase.identityError = sanitizeCatalogText(identityErr)
          end
          if not accepted then
            rejectedCount = rejectedCount + 1
            diagnosticBase.shortName = sanitizeCatalogText((identity and identity.shortName) or diagnosticBase.shortName)
            diagnosticBase.fullName = sanitizeCatalogText((identity and identity.fullName) or diagnosticBase.fullName)
            diagnosticBase.className = sanitizeCatalogText(classErr and '' or objectClass or '')
            diagnosticBase.reason = (not classMatch and not nameMatch) and 'class_and_name_filter_mismatch' or ((not classMatch) and 'class_filter_mismatch' or 'name_filter_mismatch')
            diagnosticBase.classMatched = classMatch == true
            diagnosticBase.nameMatched = nameMatch == true
            appendCatalogRejection(rejectionDiagnostics, rejectionReasonCounts, diagnosticBase, rejectionCap)
            return
          end

          local key = tostring((identity and identity.fullName) or tostring(catalogObj))
          if seen[key] then
            rejectedCount = rejectedCount + 1
            diagnosticBase.reason = 'duplicate_catalog_entry'
            diagnosticBase.shortName = sanitizeCatalogText((identity and identity.shortName) or '')
            diagnosticBase.fullName = sanitizeCatalogText((identity and identity.fullName) or '')
            diagnosticBase.className = sanitizeCatalogText(classErr and '' or objectClass or '')
            appendCatalogRejection(rejectionDiagnostics, rejectionReasonCounts, diagnosticBase, rejectionCap)
            return
          end
          seen[key] = true

          local fields, fieldNames, statuses, valueKinds, objectRefs = readPerkDataAssetFields(catalogObj, fieldCap)
          local fieldSummary = summarizePerkCatalogFieldResults(fields)
          latestFieldNames = fieldNames
          latestStatuses = statuses
          latestValueKinds = valueKinds
          latestObjectRefs = objectRefs
          if fieldSummary.errorCount > 0 then incrementCatalogReason(rejectionReasonCounts, 'field_read_errors') end
          if fieldSummary.unsupportedValueTypeCount > 0 then incrementCatalogReason(rejectionReasonCounts, 'unsupported_value_types') end
          if fieldSummary.read == 0 then incrementCatalogReason(rejectionReasonCounts, 'no_allowlisted_fields_readable') end
          entries[#entries + 1] = {
            catalogIndex = #entries + 1,
            shortName = (identity and identity.shortName) or '',
            fullName = (identity and identity.fullName) or '',
            className = tostring(objectClass or (identity and identity.objectClass) or className),
            isValid = true,
            readStatus = perkCatalogReadStatus(fieldSummary),
            fieldResults = fieldSummary,
            fields = fields,
            sourceClass = className,
            sourceField = sourceRefField or '',
            sourceShortName = sourceShortName,
            sourceFullName = sourceFullName
          }
        end)
      end
    end

    table.sort(entries, function(a, b)
      return tostring(a.fullName or a.shortName or '') < tostring(b.fullName or b.shortName or '')
    end)
    for index, entry in ipairs(entries) do entry.catalogIndex = index end

    local found = #entries > 0
    local summary = 'category=perk-da-catalog-read discoveryAttempted=true found=' .. tostring(#entries)
      .. ' candidateCount=' .. tostring(candidateCount)
      .. ' rejectedCount=' .. tostring(rejectedCount)
      .. ' candidateCap=' .. tostring(candidateCap)
      .. ' fieldCap=' .. tostring(fieldCap)
      .. ' rejectionDiagnosticCap=' .. tostring(rejectionCap)
      .. ' topRejectionReasons=' .. formatCatalogReasonCounts(rejectionReasonCounts)
      .. ' foundPatterns=' .. (#foundPatterns > 0 and table.concat(foundPatterns, ',') or 'none')
      .. ' classes=' .. table.concat(attemptedClasses, ',')
      .. ' noWrites=true noRpcs=true noHud=true noDeepArrays=true noInventoryArrays=true noArrayCount=true noArrayTraversal=true noElementDereference=true noInventoryInfo=true noEnhancements=true noDataAssetMutation=true noFunctionCalls=true'
    local meta = perkCatalogSafetyMeta({
      discoveryAttempted = true,
      discoveryMethod = 'FindAllOfCappedCuratedClasses',
      candidateClasses = attemptedClasses,
      catalogFound = found,
      catalogEntryCount = #entries,
      catalogCandidateCount = candidateCount,
      catalogRejectedCandidateCount = rejectedCount,
      catalogCandidateCap = candidateCap,
      catalogFieldCap = fieldCap,
      catalogRejectionDiagnosticCap = rejectionCap,
      catalogRejectionDiagnostics = rejectionDiagnostics,
      catalogRejectionReasons = rejectionReasonCounts,
      catalogTopRejectionReasons = formatCatalogReasonCounts(rejectionReasonCounts),
      catalogFoundPatterns = foundPatterns,
      catalogEntries = entries,
      catalogFieldNames = latestFieldNames,
      catalogReadStatuses = latestStatuses,
      catalogValueKinds = latestValueKinds,
      catalogObjectReferenceSummaries = latestObjectRefs,
      notFoundClassification = found and '' or (candidateCount > 0 and 'perk_da_catalog_candidates_rejected' or 'perk_da_catalog_not_found')
    })
    return found and 'ok' or 'nil', 'perk_da_catalog', summary, nil, meta
  end

  local function maxSafePlayState(ctx)
    if not ctx.cache.MaxSafePlay then
      ctx.cache.MaxSafePlay = {
        scalar = {
          sampleCount = 0,
          loggedCount = 0,
          noChangeSamples = 0,
          changedSamples = 0,
          changedFields = {},
          changeCounts = {},
          minValues = {},
          maxValues = {},
          firstValues = nil,
          latestValues = {},
          lastLoggedValues = nil,
          lastSampleAt = nil,
          lastHeartbeatAt = nil,
          firstContext = '',
          lastContext = '',
          firstRole = '',
          lastRole = ''
        },
        catalog = {
          snapshotCount = 0,
          loggedCount = 0,
          knownEntries = {},
          knownEntryCount = 0,
          lastSnapshotAt = nil,
          nilCount = 0,
          errorCount = 0,
          rejectedCount = 0,
          topRejectionReasons = 'none',
          foundPatterns = {},
          tastyOrangeFound = false,
          collectorFound = false
        },
        lastHeartbeatAt = nil,
        lastSummaryAt = nil
      }
    end
    return ctx.cache.MaxSafePlay
  end

  local function maxSafePlayBaseSafetyMeta()
    return {
      noElementDereference = true,
      noArrayCount = true,
      noArrayTraversal = true,
      noInventoryInfo = true,
      noEnhancements = true,
      noWrites = true,
      noRpcs = true,
      noHud = true,
      noDeepArrays = true,
      noInventoryArrays = true,
      noDataAssetMutation = true,
      noFunctionCalls = true,
      passiveOnly = true,
      crashAttributionMarker = 'max-safe-play-recorder'
    }
  end

  local function addMaxSafePlaySafety(meta)
    local safety = maxSafePlayBaseSafetyMeta()
    for key, value in pairs(safety) do meta[key] = value end
    return meta
  end

  local function maxSafePlayScalarMeta(sample, recorderState, reason, changed)
    local meta = safeScalarWatchMeta(sample, recorderState.scalar, reason, changed)
    meta.sourceScope = 'max_safe_play_recorder_scalar'
    meta.localNotes = 'Max-safe play scalar recorder; read-only reuse of proven safe scalar paths only'
    meta.maxSafePlayScalarSampleCount = recorderState.scalar.sampleCount
    meta.maxSafePlayScalarLoggedCount = recorderState.scalar.loggedCount
    meta.maxSafePlayFirstValues = recorderState.scalar.firstValues or {}
    meta.maxSafePlayLatestValues = recorderState.scalar.latestValues or {}
    meta.maxSafePlayMinValues = recorderState.scalar.minValues or {}
    meta.maxSafePlayMaxValues = recorderState.scalar.maxValues or {}
    meta.maxSafePlayChangedFields = recorderState.scalar.changedFields or {}
    meta.maxSafePlayChangeCounts = recorderState.scalar.changeCounts or {}
    meta.maxSafePlayNoChangeSamples = recorderState.scalar.noChangeSamples
    meta.maxSafePlayChangedSamples = recorderState.scalar.changedSamples
    meta.maxSafePlayCatalogSnapshotCount = recorderState.catalog.snapshotCount
    meta.maxSafePlayCatalogKnownEntryCount = recorderState.catalog.knownEntryCount
    meta.maxSafePlayCatalogRejectedCount = recorderState.catalog.rejectedCount
    meta.maxSafePlayCatalogTopRejectionReasons = recorderState.catalog.topRejectionReasons
    meta.maxSafePlayCatalogFoundPatterns = recorderState.catalog.foundPatterns
    meta.maxSafePlayNilCount = recorderState.catalog.nilCount
    meta.maxSafePlayErrorCount = recorderState.catalog.errorCount
    meta.tastyOrangeFound = recorderState.catalog.tastyOrangeFound
    meta.collectorFound = recorderState.catalog.collectorFound
    return addMaxSafePlaySafety(meta)
  end

  local function maxSafePlayScalarSummary(sample, recorderState, reason, changed)
    local changedText = #changed > 0 and table.concat(changed, ',') or 'none'
    return 'category=max-safe-play-recorder scalar sampleCount=' .. tostring(recorderState.scalar.sampleCount)
      .. ' loggedCount=' .. tostring(recorderState.scalar.loggedCount)
      .. ' reason=' .. tostring(reason)
      .. ' playerStatePresent=' .. tostring(sample.playerStatePresent == true)
      .. ' changed=' .. tostring(#changed > 0)
      .. ' changedFields=' .. changedText
      .. ' noWrites=true noRpcs=true noHud=true noDeepArrays=true noInventoryArrays=true'
      .. ' noArrayCount=true noArrayTraversal=true noElementDereference=true noInventoryInfo=true noEnhancements=true'
      .. ' noDataAssetMutation=true noFunctionCalls=true passiveOnly=true crashAttributionMarker=max-safe-play-recorder'
  end

  local function readMaxSafePlayScalarSample(ctx)
    local cfg = ctx.config or {}
    local intervalSeconds = positiveConfigNumber(cfg.maxSafePlayIntervalSeconds, 5)
    local heartbeatSeconds = positiveConfigNumber(cfg.maxSafePlayHeartbeatSeconds, 60)
    local maxSamples = positiveConfigNumber(cfg.maxSafePlayMaxSamples, 720)
    local now = os.time()
    local recorderState = maxSafePlayState(ctx)
    local state = recorderState.scalar

    if state.sampleCount >= maxSamples then
      return 'skipped_by_config', 'max_safe_play_scalar', 'max-safe play scalar maxSamples reached', nil, { suppressEmit = true }
    end
    if state.lastSampleAt ~= nil and (now - state.lastSampleAt) < intervalSeconds then
      return 'skipped_by_config', 'max_safe_play_scalar', 'waiting for next max-safe play scalar interval', nil, { suppressEmit = true }
    end

    local sample = buildSafeScalarWatchSample(ctx)
    state.sampleCount = state.sampleCount + 1
    state.lastSampleAt = now

    local firstLoggedSample = state.lastLoggedValues == nil
    local changed = firstLoggedSample and {} or safeScalarWatchChangedFields(state.lastLoggedValues, sample.values)
    updateSafeScalarWatchAggregates(state, sample, changed)

    local reason = nil
    if firstLoggedSample then
      reason = sample.playerStatePresent and 'first_sample' or 'playerstate_absent'
    elseif #changed > 0 then
      reason = 'changed'
    elseif cfg.maxSafePlayLogUnchangedHeartbeat ~= false and (state.lastHeartbeatAt == nil or (now - state.lastHeartbeatAt) >= heartbeatSeconds) then
      reason = 'heartbeat'
    else
      return 'ok', 'max_safe_play_scalar', 'max-safe play scalar sample unchanged', nil, { suppressEmit = true }
    end

    if reason == 'heartbeat' then
      state.lastHeartbeatAt = now
    end
    state.loggedCount = state.loggedCount + 1
    state.lastLoggedValues = copyTable(sample.values)

    local meta = maxSafePlayScalarMeta(sample, recorderState, reason, changed)
    local summary = maxSafePlayScalarSummary(sample, recorderState, reason, changed)
    if sample.error then
      return 'lua_error', 'max_safe_play_scalar', summary, sample.error, meta
    end
    return sample.playerStatePresent and 'ok' or 'nil', 'max_safe_play_scalar', summary, nil, meta
  end

  local function catalogEntryKey(entry)
    return tostring((entry and (entry.fullName or entry.shortName)) or '')
  end

  local function catalogEntryFingerprint(entry)
    local parts = {
      tostring(entry and entry.shortName or ''),
      tostring(entry and entry.fullName or ''),
      tostring(entry and entry.className or '')
    }
    for _, field in ipairs((entry and entry.fields) or {}) do
      parts[#parts + 1] = tostring(field.fieldName or '') .. '=' .. tostring(field.status or '') .. ':' .. tostring(field.valueKind or '') .. ':' .. tostring(field.valueSummary or '')
    end
    return table.concat(parts, '|')
  end

  local function countCatalogNilErrors(entries)
    local nilCount = 0
    local errorCount = 0
    for _, entry in ipairs(entries or {}) do
      for _, field in ipairs(entry.fields or {}) do
        if field.status == 'nil' then nilCount = nilCount + 1 end
        if field.status == 'error' then errorCount = errorCount + 1 end
      end
    end
    return nilCount, errorCount
  end

  local function updateNamedPerkFlags(recorderState, entries)
    for _, entry in ipairs(entries or {}) do
      local text = tostring(entry.shortName or '') .. ' ' .. tostring(entry.fullName or '')
      if text:find('TastyOrange') then recorderState.catalog.tastyOrangeFound = true end
      if text:find('Collector') then recorderState.catalog.collectorFound = true end
    end
  end

  local function readMaxSafePlayPerkCatalogSnapshot(ctx)
    local cfg = ctx.config or {}
    local intervalSeconds = positiveConfigNumber(cfg.maxSafePlayPerkCatalogIntervalSeconds, 60)
    local maxSnapshots = positiveConfigNumber(cfg.maxSafePlayMaxPerkCatalogSnapshots, 60)
    local now = os.time()
    local recorderState = maxSafePlayState(ctx)
    local catalogState = recorderState.catalog

    if catalogState.snapshotCount >= maxSnapshots then
      return 'skipped_by_config', 'max_safe_play_perk_catalog', 'max-safe play perk catalog max snapshots reached', nil, { suppressEmit = true }
    end
    if catalogState.lastSnapshotAt ~= nil and (now - catalogState.lastSnapshotAt) < intervalSeconds then
      return 'skipped_by_config', 'max_safe_play_perk_catalog', 'waiting for next max-safe play perk catalog interval', nil, { suppressEmit = true }
    end

    local result, kind, summary, err, meta = collectPerkDataAssetCatalog(ctx)
    catalogState.snapshotCount = catalogState.snapshotCount + 1
    catalogState.lastSnapshotAt = now

    meta = meta or {}
    local entries = meta.catalogEntries or {}
    updateNamedPerkFlags(recorderState, entries)
    local nilCount, errorCount = countCatalogNilErrors(entries)
    catalogState.nilCount = catalogState.nilCount + nilCount
    catalogState.errorCount = catalogState.errorCount + errorCount
    catalogState.rejectedCount = meta.catalogRejectedCandidateCount or catalogState.rejectedCount or 0
    catalogState.topRejectionReasons = meta.catalogTopRejectionReasons or catalogState.topRejectionReasons or 'none'
    catalogState.foundPatterns = meta.catalogFoundPatterns or catalogState.foundPatterns or {}

    local newEntries = {}
    local changedEntries = {}
    for _, entry in ipairs(entries) do
      local key = catalogEntryKey(entry)
      if key ~= '' then
        local fingerprint = catalogEntryFingerprint(entry)
        if catalogState.knownEntries[key] == nil then
          newEntries[#newEntries + 1] = entry
          catalogState.knownEntries[key] = fingerprint
          catalogState.knownEntryCount = catalogState.knownEntryCount + 1
        elseif catalogState.knownEntries[key] ~= fingerprint then
          changedEntries[#changedEntries + 1] = entry
          catalogState.knownEntries[key] = fingerprint
        end
      end
    end

    local firstSnapshot = catalogState.snapshotCount == 1
    local entriesToLog = firstSnapshot and entries or {}
    if not firstSnapshot then
      for _, entry in ipairs(newEntries) do entriesToLog[#entriesToLog + 1] = entry end
      for _, entry in ipairs(changedEntries) do entriesToLog[#entriesToLog + 1] = entry end
    end
    local reason = firstSnapshot and 'first_full_catalog_snapshot' or ((#newEntries > 0 or #changedEntries > 0) and 'new_or_changed_catalog_entries' or 'catalog_heartbeat')
    catalogState.loggedCount = catalogState.loggedCount + 1

    meta.sourceScope = 'max_safe_play_recorder_perk_catalog'
    meta.catalogEntries = entriesToLog
    meta.maxSafePlayCatalogSnapshotCount = catalogState.snapshotCount
    meta.maxSafePlayCatalogLoggedCount = catalogState.loggedCount
    meta.maxSafePlayNewDataAssets = newEntries
    meta.maxSafePlayChangedCatalogEntries = changedEntries
    meta.maxSafePlayCatalogKnownEntryCount = catalogState.knownEntryCount
    meta.maxSafePlayCatalogRejectedCount = catalogState.rejectedCount
    meta.maxSafePlayCatalogTopRejectionReasons = catalogState.topRejectionReasons
    meta.maxSafePlayCatalogFoundPatterns = catalogState.foundPatterns
    meta.maxSafePlayScalarSampleCount = recorderState.scalar.sampleCount
    meta.maxSafePlayScalarLoggedCount = recorderState.scalar.loggedCount
    meta.maxSafePlayNilCount = catalogState.nilCount
    meta.maxSafePlayErrorCount = catalogState.errorCount
    meta.tastyOrangeFound = catalogState.tastyOrangeFound
    meta.collectorFound = catalogState.collectorFound
    meta.sampleReason = reason
    meta.localNotes = 'Max-safe play capped perk DataAsset catalog snapshot; normal entries only, no special cases, no mutation or function calls'
    addMaxSafePlaySafety(meta)
    meta.crashAttributionMarker = 'max-safe-play-recorder'

    local maxSummary = 'category=max-safe-play-recorder perkCatalog snapshotCount=' .. tostring(catalogState.snapshotCount)
      .. ' loggedCount=' .. tostring(catalogState.loggedCount)
      .. ' reason=' .. reason
      .. ' entryCount=' .. tostring(meta.catalogEntryCount or 0)
      .. ' candidateCount=' .. tostring(meta.catalogCandidateCount or 0)
      .. ' rejectedCount=' .. tostring(meta.catalogRejectedCandidateCount or 0)
      .. ' knownEntryCount=' .. tostring(catalogState.knownEntryCount)
      .. ' topRejectionReasons=' .. tostring(meta.catalogTopRejectionReasons or 'none')
      .. ' foundPatterns=' .. (#(meta.catalogFoundPatterns or {}) > 0 and table.concat(meta.catalogFoundPatterns, ',') or 'none')
      .. ' newDataAssets=' .. tostring(#newEntries)
      .. ' changedCatalogEntries=' .. tostring(#changedEntries)
      .. ' tastyOrangeFound=' .. tostring(catalogState.tastyOrangeFound)
      .. ' collectorFound=' .. tostring(catalogState.collectorFound)
      .. ' noWrites=true noRpcs=true noHud=true noDeepArrays=true noInventoryArrays=true'
      .. ' noArrayCount=true noArrayTraversal=true noElementDereference=true noInventoryInfo=true noEnhancements=true'
      .. ' noDataAssetMutation=true noFunctionCalls=true passiveOnly=true crashAttributionMarker=max-safe-play-recorder'
    return result, 'max_safe_play_perk_catalog', maxSummary, err, meta
  end

  local function maxSafePlaySessionMeta(ctx, reason)
    local recorderState = maxSafePlayState(ctx)
    return addMaxSafePlaySafety({
      sourceScope = 'max_safe_play_recorder_session',
      sampleReason = reason,
      maxSafePlayScalarSampleCount = recorderState.scalar.sampleCount,
      maxSafePlayScalarLoggedCount = recorderState.scalar.loggedCount,
      maxSafePlayFirstValues = recorderState.scalar.firstValues or {},
      maxSafePlayLatestValues = recorderState.scalar.latestValues or {},
      maxSafePlayMinValues = recorderState.scalar.minValues or {},
      maxSafePlayMaxValues = recorderState.scalar.maxValues or {},
      maxSafePlayChangedFields = recorderState.scalar.changedFields or {},
      maxSafePlayChangeCounts = recorderState.scalar.changeCounts or {},
      maxSafePlayCatalogSnapshotCount = recorderState.catalog.snapshotCount,
      maxSafePlayCatalogLoggedCount = recorderState.catalog.loggedCount,
      maxSafePlayCatalogKnownEntryCount = recorderState.catalog.knownEntryCount,
      maxSafePlayCatalogRejectedCount = recorderState.catalog.rejectedCount,
      maxSafePlayCatalogTopRejectionReasons = recorderState.catalog.topRejectionReasons,
      maxSafePlayCatalogFoundPatterns = recorderState.catalog.foundPatterns,
      maxSafePlayNilCount = recorderState.catalog.nilCount,
      maxSafePlayErrorCount = recorderState.catalog.errorCount,
      tastyOrangeFound = recorderState.catalog.tastyOrangeFound,
      collectorFound = recorderState.catalog.collectorFound,
      firstContext = recorderState.scalar.firstContext or '',
      lastContext = recorderState.scalar.lastContext or '',
      firstRole = recorderState.scalar.firstRole or '',
      lastRole = recorderState.scalar.lastRole or '',
      localNotes = 'Compact max-safe play recorder session aggregate; no live inventory arrays, writes, RPCs, HUD, deep arrays, InventoryInfo, or Enhancements'
    })
  end

  local function readMaxSafePlaySessionHeartbeat(ctx)
    local cfg = ctx.config or {}
    local heartbeatSeconds = positiveConfigNumber(cfg.maxSafePlayHeartbeatSeconds, 60)
    local now = os.time()
    local recorderState = maxSafePlayState(ctx)
    if recorderState.lastHeartbeatAt ~= nil and (now - recorderState.lastHeartbeatAt) < heartbeatSeconds then
      return 'skipped_by_config', 'max_safe_play_session', 'waiting for max-safe play heartbeat', nil, { suppressEmit = true }
    end
    recorderState.lastHeartbeatAt = now
    local meta = maxSafePlaySessionMeta(ctx, 'heartbeat')
    local summary = 'category=max-safe-play-recorder heartbeat scalarSamples=' .. tostring(meta.maxSafePlayScalarSampleCount)
      .. ' scalarLogged=' .. tostring(meta.maxSafePlayScalarLoggedCount)
      .. ' catalogSnapshots=' .. tostring(meta.maxSafePlayCatalogSnapshotCount)
      .. ' catalogKnownEntries=' .. tostring(meta.maxSafePlayCatalogKnownEntryCount)
      .. ' catalogRejected=' .. tostring(meta.maxSafePlayCatalogRejectedCount)
      .. ' catalogTopRejectionReasons=' .. tostring(meta.maxSafePlayCatalogTopRejectionReasons or 'none')
      .. ' changedFields=' .. (#(meta.maxSafePlayChangedFields or {}) > 0 and table.concat(meta.maxSafePlayChangedFields, ',') or 'none')
      .. ' passiveOnly=true'
    return 'ok', 'max_safe_play_session', summary, nil, meta
  end

  local function readMaxSafePlaySessionSummary(ctx)
    local cfg = ctx.config or {}
    local heartbeatSeconds = positiveConfigNumber(cfg.maxSafePlayHeartbeatSeconds, 60)
    local now = os.time()
    local recorderState = maxSafePlayState(ctx)
    if recorderState.lastSummaryAt ~= nil and (now - recorderState.lastSummaryAt) < heartbeatSeconds then
      return 'skipped_by_config', 'max_safe_play_session', 'waiting for max-safe play summary', nil, { suppressEmit = true }
    end
    if recorderState.scalar.sampleCount == 0 and recorderState.catalog.snapshotCount == 0 then
      return 'skipped_by_config', 'max_safe_play_session', 'max-safe play summary waiting for data', nil, { suppressEmit = true }
    end
    recorderState.lastSummaryAt = now
    local meta = maxSafePlaySessionMeta(ctx, 'summary')
    local summary = 'category=max-safe-play-recorder summary scalarSamples=' .. tostring(meta.maxSafePlayScalarSampleCount)
      .. ' scalarLogged=' .. tostring(meta.maxSafePlayScalarLoggedCount)
      .. ' catalogSnapshots=' .. tostring(meta.maxSafePlayCatalogSnapshotCount)
      .. ' catalogKnownEntries=' .. tostring(meta.maxSafePlayCatalogKnownEntryCount)
      .. ' catalogRejected=' .. tostring(meta.maxSafePlayCatalogRejectedCount)
      .. ' catalogTopRejectionReasons=' .. tostring(meta.maxSafePlayCatalogTopRejectionReasons or 'none')
      .. ' nilCount=' .. tostring(meta.maxSafePlayNilCount)
      .. ' errorCount=' .. tostring(meta.maxSafePlayErrorCount)
      .. ' passiveOnly=true'
    return 'ok', 'max_safe_play_session', summary, nil, meta
  end

  local function classifyCrabHCSource(fullName)
    local text = tostring(fullName or '')
    if text:find('Destructible') or text:find('Barrel') or text:find('ChaoticBarrel') then
      return 'non_player', 'unscoped CrabHC appears non-player/destructible; do not use as player health'
    end
    return 'ambiguous', 'unscoped CrabHC; ownership not established'
  end

  probes[#probes + 1] = mk('FindFirstOf.CrabPC', 'core', 'shallow-core', 'findFirst', function(ctx)
    local obj, err = safe.findFirst('CrabPC')
    ctx.cache.CrabPC = obj
    if err then return 'lua_error', nil, err end
    if obj == nil then return 'nil' end
    return 'ok', 'object', 'CrabPC found'
  end, {
    symbol = 'CrabPC',
    owner = 'Runtime',
    member = 'CrabPC',
    accessMethod = 'FindFirstOf',
    accessKind = 'findFirst'
  })

  probes[#probes + 1] = mk('CrabPC.IsValid', 'core', 'shallow-core', 'isValid', function(ctx)
    local ok = safe.isValidObject(ctx.cache.CrabPC)
    return ok and 'ok' or 'nil', 'boolean', tostring(ok)
  end, {
    symbol = 'CrabPC',
    owner = 'CrabPC',
    member = 'IsValid',
    accessMethod = 'IsValid',
    accessKind = 'isValid'
  })

  probes[#probes + 1] = mk('CrabPC.GetFullName', 'core', 'shallow-core', 'fullname', function(ctx)
    local v, err = safe.getFullName(ctx.cache.CrabPC)
    if err then return 'lua_error', nil, err end
    if not v then return 'nil' end
    return 'ok', 'string', v
  end, {
    symbol = 'CrabPC',
    owner = 'CrabPC',
    member = 'GetFullName',
    accessMethod = 'GetFullName',
    accessKind = 'getFullName'
  })

  probes[#probes + 1] = mk('CrabPC.GetPropertyValue.PlayerState', 'core', 'shallow-core', 'playerstate', function(ctx)
    local v, err = safe.getProperty(ctx.cache.CrabPC, 'PlayerState')
    ctx.cache.CrabPS = v
    if err then return 'lua_error', nil, err end
    if not v then return 'nil' end
    return 'ok', 'object', 'PlayerState obtained'
  end, {
    symbol = 'CrabPC.PlayerState',
    owner = 'CrabPC',
    member = 'PlayerState',
    accessMethod = 'GetPropertyValue',
    accessKind = 'getProperty'
  })

  probes[#probes + 1] = mk('CrabPS.IsValid', 'core', 'shallow-core', 'isValid', function(ctx)
    local ok = safe.isValidObject(ctx.cache.CrabPS)
    return ok and 'ok' or 'nil', 'boolean', tostring(ok)
  end, {
    symbol = 'CrabPS',
    owner = 'CrabPS',
    member = 'IsValid',
    accessMethod = 'IsValid',
    accessKind = 'isValid'
  })

  probes[#probes + 1] = mk('CrabPS.GetFullName', 'core', 'shallow-core', 'fullname', function(ctx)
    local v, err = safe.getFullName(ctx.cache.CrabPS)
    if err then return 'lua_error', nil, err end
    if not v then return 'nil' end
    return 'ok', 'string', v
  end, {
    symbol = 'CrabPS',
    owner = 'CrabPS',
    member = 'GetFullName',
    accessMethod = 'GetFullName',
    accessKind = 'getFullName'
  })

  local equipmentFields = { 'WeaponDA', 'AbilityDA', 'MeleeDA' }
  for _, field in ipairs(equipmentFields) do
    local fieldName = field
    probes[#probes + 1] = mk('CrabPS.GetPropertyValue.' .. fieldName, 'equipment', 'equipment-property-read', 'property', function(ctx)
      local crabPs, crabPsErr = getCrabPlayerState(ctx)
      if crabPsErr then return 'lua_error', nil, crabPsErr end
      local v, err = safe.getProperty(crabPs, fieldName)
      ctx.cache[fieldName] = v
      if err then return 'lua_error', nil, err end
      if not v then return 'nil' end
      local summary, summaryErr, identity = summarizeIdentityOrDefault(v, fieldName .. ' via property')
      return 'ok', 'object', summary, summaryErr, identity
    end, {
      symbol = 'CrabPS.' .. fieldName,
      owner = 'CrabPS',
      member = fieldName,
      accessMethod = 'GetPropertyValue',
      accessKind = 'getProperty'
    })
    probes[#probes + 1] = mk('CrabPS.DirectField.' .. fieldName, 'equipment', 'equipment-direct-field-read', 'direct', function(ctx)
      local crabPs, crabPsErr = getCrabPlayerState(ctx)
      if crabPsErr then return 'lua_error', nil, crabPsErr end
      local v, err = safe.getDirectField(crabPs, fieldName)
      if err then return 'lua_error', nil, err end
      if not v then return 'nil' end
      local summary, summaryErr, identity = summarizeIdentityOrDefault(v, fieldName .. ' via direct field')
      return 'ok', 'object', summary, summaryErr, identity
    end, {
      symbol = 'CrabPS.' .. fieldName,
      owner = 'CrabPS',
      member = fieldName,
      accessMethod = 'DirectField',
      accessKind = 'directField'
    })
  end

  probes[#probes + 1] = mk('FindFirstOf.CrabHC', 'health', 'health-baseline-read', 'findFirst', function(ctx)
    local obj, err = safe.findFirst('CrabHC')
    ctx.cache.CrabHC = obj
    if err then return 'lua_error', nil, err end
    if obj == nil then return 'nil' end
    local fullName = safe.getFullName(obj)
    local sourceScope, sourceNote = classifyCrabHCSource(fullName)
    local summary = fullName and ('CrabHC found fullName=' .. tostring(fullName)) or 'CrabHC found'
    return 'ok', 'object', summary, nil, {
      fullName = fullName or '',
      sourceScope = sourceScope,
      localNotes = sourceNote
    }
  end, {
    symbol = 'CrabHC',
    owner = 'Runtime',
    member = 'CrabHC',
    accessMethod = 'FindFirstOf',
    accessKind = 'findFirst',
    sourceScope = 'ambiguous'
  })

  probes[#probes + 1] = mk('CrabHC.IsValid', 'health', 'health-baseline-read', 'isValid', function(ctx)
    local ok = safe.isValidObject(ctx.cache.CrabHC)
    return ok and 'ok' or 'nil', 'boolean', tostring(ok)
  end, {
    symbol = 'CrabHC',
    owner = 'CrabHC',
    member = 'IsValid',
    accessMethod = 'IsValid',
    accessKind = 'isValid',
    sourceScope = 'ambiguous'
  })

  probes[#probes + 1] = mk('CrabHC.GetFullName', 'health', 'health-baseline-read', 'fullname', function(ctx)
    local v, err = safe.getFullName(ctx.cache.CrabHC)
    if err then return 'lua_error', nil, err end
    if not v then return 'nil' end
    local sourceScope, sourceNote = classifyCrabHCSource(v)
    return 'ok', 'string', v, nil, {
      fullName = v,
      sourceScope = sourceScope,
      localNotes = sourceNote
    }
  end, {
    symbol = 'CrabHC',
    owner = 'CrabHC',
    member = 'GetFullName',
    accessMethod = 'GetFullName',
    accessKind = 'getFullName',
    sourceScope = 'ambiguous'
  })

  probes[#probes + 1] = mk('CrabHC.GetPropertyValue.HealthInfo', 'health', 'health-baseline-read', 'healthInfo', function(ctx)
    local v, err = safe.getProperty(ctx.cache.CrabHC, 'HealthInfo')
    ctx.cache.CrabHCHealthInfo = v
    if err then return 'lua_error', nil, err end
    if not v then return 'nil' end
    return 'ok', type(v), 'HealthInfo obtained'
  end, {
    symbol = 'CrabHC.HealthInfo',
    owner = 'CrabHC',
    member = 'HealthInfo',
    accessMethod = 'GetPropertyValue',
    accessKind = 'getProperty',
    sourceScope = 'ambiguous'
  })

  for _, field in ipairs({ 'CurrentHealth', 'CurrentMaxHealth' }) do
    local fieldName = field
    probes[#probes + 1] = mk('CrabHC.HealthInfo.' .. fieldName, 'health', 'health-baseline-read', 'healthInfoScalar', function(ctx)
      local v, err = safe.getStructField(ctx.cache.CrabHCHealthInfo, fieldName)
      if err then return 'lua_error', nil, err end
      return readScalar(v)
    end, {
      symbol = 'CrabHC.HealthInfo.' .. fieldName,
      owner = 'CrabHC.HealthInfo',
      member = fieldName,
      accessMethod = 'HealthInfoStructField',
      accessKind = 'health',
      sourceScope = 'ambiguous'
    })
  end

  probes[#probes + 1] = mk('CrabHC.GetPropertyValue.BaseMaxHealth', 'health', 'health-baseline-read', 'baseMaxHealth', function(ctx)
    local v, err = safe.getProperty(ctx.cache.CrabHC, 'BaseMaxHealth')
    if err then return 'lua_error', nil, err end
    return readScalar(v)
  end, {
    symbol = 'CrabHC.BaseMaxHealth',
    owner = 'CrabHC',
    member = 'BaseMaxHealth',
    accessMethod = 'GetPropertyValue',
    accessKind = 'health',
    sourceScope = 'ambiguous'
  })

  probes[#probes + 1] = mk('CrabPS.GetPropertyValue.HealthInfo', 'health', 'health-baseline-read', 'healthInfo', function(ctx)
    local crabPs, crabPsErr = getCrabPlayerState(ctx)
    if crabPsErr then return 'lua_error', nil, crabPsErr end
    local v, err = safe.getProperty(crabPs, 'HealthInfo')
    ctx.cache.CrabPSHealthInfo = v
    if err then return 'lua_error', nil, err end
    if not v then return 'nil' end
    return 'ok', type(v), 'HealthInfo obtained'
  end, {
    symbol = 'CrabPS.HealthInfo',
    owner = 'CrabPS',
    member = 'HealthInfo',
    accessMethod = 'GetPropertyValue',
    accessKind = 'getProperty',
    sourceScope = 'player_state_scoped'
  })

  for _, field in ipairs({ 'CurrentHealth', 'CurrentMaxHealth' }) do
    local fieldName = field
    probes[#probes + 1] = mk('CrabPS.HealthInfo.' .. fieldName, 'health', 'health-baseline-read', 'healthInfoScalar', function(ctx)
      local v, err = safe.getStructField(ctx.cache.CrabPSHealthInfo, fieldName)
      if err then return 'lua_error', nil, err end
      return readScalar(v)
    end, {
      symbol = 'CrabPS.HealthInfo.' .. fieldName,
      owner = 'CrabPS.HealthInfo',
      member = fieldName,
      accessMethod = 'HealthInfoStructField',
      accessKind = 'health',
      sourceScope = 'player_state_scoped'
    })
  end

  for _, field in ipairs({ 'BaseMaxHealth', 'MaxHealthMultiplier' }) do
    local fieldName = field
    probes[#probes + 1] = mk('CrabPS.GetPropertyValue.' .. fieldName, 'health', 'health-baseline-read', 'healthProperty', function(ctx)
      local crabPs, crabPsErr = getCrabPlayerState(ctx)
      if crabPsErr then return 'lua_error', nil, crabPsErr end
      local v, err = safe.getProperty(crabPs, fieldName)
      if err then return 'lua_error', nil, err end
      return readScalar(v)
    end, {
      symbol = 'CrabPS.' .. fieldName,
      owner = 'CrabPS',
      member = fieldName,
      accessMethod = 'GetPropertyValue',
      accessKind = 'health',
      sourceScope = 'player_state_scoped'
    })
  end

  probes[#probes + 1] = mk('CrabPS.GetPropertyValue.HealthInfo', 'health', 'health-playerstate-read', 'healthInfo', function(ctx)
    local crabPs, crabPsErr = getCrabPlayerState(ctx)
    if crabPsErr then return 'lua_error', nil, crabPsErr end
    local v, err = safe.getProperty(crabPs, 'HealthInfo')
    ctx.cache.CrabPSHealthInfo = v
    if err then return 'lua_error', nil, err end
    if not v then return 'nil' end
    return 'ok', type(v), 'HealthInfo obtained', nil, {
      sourceScope = 'player_state_scoped',
      localNotes = 'CrabPC -> PlayerState -> CrabPS health path'
    }
  end, {
    symbol = 'CrabPS.HealthInfo',
    owner = 'CrabPS',
    member = 'HealthInfo',
    accessMethod = 'GetPropertyValue',
    accessKind = 'getProperty',
    sourceScope = 'player_state_scoped'
  })

  for _, field in ipairs({ 'CurrentHealth', 'CurrentMaxHealth' }) do
    local fieldName = field
    probes[#probes + 1] = mk('CrabPS.HealthInfo.' .. fieldName, 'health', 'health-playerstate-read', 'healthInfoScalar', function(ctx)
      local v, err = safe.getStructField(ctx.cache.CrabPSHealthInfo, fieldName)
      if err then return 'lua_error', nil, err end
      local result, kind, summary = readScalar(v)
      return result, kind, summary, nil, {
        sourceScope = 'player_state_scoped',
        localNotes = 'CrabPC -> PlayerState -> CrabPS health path'
      }
    end, {
      symbol = 'CrabPS.HealthInfo.' .. fieldName,
      owner = 'CrabPS.HealthInfo',
      member = fieldName,
      accessMethod = 'HealthInfoStructField',
      accessKind = 'health',
      sourceScope = 'player_state_scoped'
    })
  end

  for _, field in ipairs({ 'BaseMaxHealth', 'MaxHealthMultiplier' }) do
    local fieldName = field
    probes[#probes + 1] = mk('CrabPS.GetPropertyValue.' .. fieldName, 'health', 'health-playerstate-read', 'healthProperty', function(ctx)
      local crabPs, crabPsErr = getCrabPlayerState(ctx)
      if crabPsErr then return 'lua_error', nil, crabPsErr end
      local v, err = safe.getProperty(crabPs, fieldName)
      if err then return 'lua_error', nil, err end
      local result, kind, summary = readScalar(v)
      return result, kind, summary, nil, {
        sourceScope = 'player_state_scoped',
        localNotes = 'CrabPC -> PlayerState -> CrabPS health path'
      }
    end, {
      symbol = 'CrabPS.' .. fieldName,
      owner = 'CrabPS',
      member = fieldName,
      accessMethod = 'GetPropertyValue',
      accessKind = 'health',
      sourceScope = 'player_state_scoped'
    })
  end

  probes[#probes + 1] = mk('Health.PlayerState.Sample', 'health', 'health-playerstate-watch', 'sample', function(ctx)
    return readPlayerStateHealthSample(ctx)
  end, {
    symbol = 'CrabPS.HealthInfo',
    owner = 'CrabPS',
    member = 'HealthInfo',
    accessMethod = 'PlayerStateHealthSample',
    accessKind = 'health',
    sourceScope = 'player_state_scoped'
  })

  probes[#probes + 1] = mk('Identity.LocalPlayer.Sample', 'identity', 'multiplayer-roster-read', 'localPlayer', function(ctx)
    local playerState, playerStateErr = getLocalPlayerState(ctx)
    if playerStateErr then return 'lua_error', nil, nil, playerStateErr end
    local sample = samplePlayerStateIdentity(playerState, ctx.config or {})
    local summary, display, ids = summarizeIdentitySamples({ sample }, 'localPlayerPresent=' .. tostring(sample.playerStatePresent))
    return sample.playerStatePresent and 'ok' or 'nil', 'identity_sample', summary, nil, {
      sourceScope = 'player_state_scoped',
      sourcePath = 'CrabPC.PlayerState',
      localPlayerPresent = sample.playerStatePresent,
      visiblePlayerCount = sample.playerStatePresent and 1 or 0,
      visiblePlayerCap = 1,
      displayNameFingerprints = display,
      stableIdFingerprints = ids,
      identityRawRedacted = ctx.config.allowRawIdentityEvidence ~= true,
      rawIdentityEvidence = ctx.config.allowRawIdentityEvidence == true,
      rawDisplayNames = ctx.config.allowRawIdentityEvidence == true and { sample.rawDisplayName or '' } or nil,
      rawStableIds = ctx.config.allowRawIdentityEvidence == true and { sample.rawStableId or '' } or nil,
      localNotes = 'read-only local CrabPC -> PlayerState identity sample; raw values redacted unless allowRawIdentityEvidence=true'
    }
  end, {
    symbol = 'CrabPC.PlayerState',
    owner = 'CrabPC',
    member = 'PlayerState',
    accessMethod = 'GetPropertyValue',
    accessKind = 'identity',
    sourceScope = 'player_state_scoped'
  })

  probes[#probes + 1] = mk('Identity.PlayerState.Sample', 'identity', 'multiplayer-roster-read', 'playerState', function(ctx)
    local playerState = ctx.cache.IdentityLocalPlayerState
    if not safe.isValidObject(playerState) then
      local err
      playerState, err = getLocalPlayerState(ctx)
      if err then return 'lua_error', nil, nil, err end
    end
    local sample = samplePlayerStateIdentity(playerState, ctx.config or {})
    local summary, display, ids = summarizeIdentitySamples({ sample }, 'playerStatePresent=' .. tostring(sample.playerStatePresent))
    return sample.playerStatePresent and 'ok' or 'nil', 'identity_sample', summary, nil, {
      sourceScope = 'player_state_scoped',
      sourcePath = 'CrabPC.PlayerState identity fields',
      localPlayerPresent = sample.playerStatePresent,
      visiblePlayerCount = sample.playerStatePresent and 1 or 0,
      visiblePlayerCap = 1,
      displayNameFingerprints = display,
      stableIdFingerprints = ids,
      identityRawRedacted = ctx.config.allowRawIdentityEvidence ~= true,
      rawIdentityEvidence = ctx.config.allowRawIdentityEvidence == true,
      rawDisplayNames = ctx.config.allowRawIdentityEvidence == true and { sample.rawDisplayName or '' } or nil,
      rawStableIds = ctx.config.allowRawIdentityEvidence == true and { sample.rawStableId or '' } or nil,
      localNotes = 'candidate PlayerState display/stable-id fields via GetPropertyValue only; no raw IDs by default'
    }
  end, {
    symbol = 'PlayerState.Identity',
    owner = 'PlayerState',
    member = 'PlayerName UniqueId',
    accessMethod = 'GetPropertyValue',
    accessKind = 'identity',
    sourceScope = 'player_state_scoped'
  })

  probes[#probes + 1] = mk('Identity.GameState.SourceCandidate', 'identity', 'multiplayer-roster-read', 'gameStateSourceCandidate', function(ctx)
    local gameState, sourceClass, err = getGameState()
    ctx.cache.IdentityGameState = gameState
    ctx.cache.IdentityGameStateSourceClass = sourceClass
    if err and not safe.isValidObject(gameState) then return 'lua_error', nil, nil, err end
    return inspectObjectSource(
      gameState,
      tostring(sourceClass),
      tostring(sourceClass),
      'FindFirstOf(GameStateBase) with GameState fallback; GetFullName/GetName/GetClass only; no roster or property traversal performed'
    )
  end, {
    symbol = 'GameStateBase GameState',
    owner = 'Runtime',
    member = 'GameState',
    accessMethod = 'FindFirstOf',
    accessKind = 'identitySourceCandidate',
    sourceScope = 'runtime_roster_candidate'
  })

  probes[#probes + 1] = mk('Identity.CrabGS.SourceCandidate', 'identity', 'multiplayer-roster-read', 'crabGsSourceCandidate', function(ctx)
    local crabGs, err = safe.findFirst('CrabGS')
    ctx.cache.IdentityCrabGS = crabGs
    if err then return 'lua_error', nil, nil, err end
    return inspectObjectSource(
      crabGs,
      'CrabGS',
      'CrabGS',
      'FindFirstOf(CrabGS); GetFullName/GetName/GetClass only; objectdump shows CrabGS extends GameStateBase but no CrabGS-specific PlayerArray property'
    )
  end, {
    symbol = 'CrabGS',
    owner = 'Runtime',
    member = 'CrabGS',
    accessMethod = 'FindFirstOf',
    accessKind = 'identitySourceCandidate',
    sourceScope = 'runtime_roster_candidate'
  })

  probes[#probes + 1] = mk('Identity.PlayerArray.Shape', 'identity', 'multiplayer-roster-read', 'playerArrayShape', function(ctx)
    local cap = 16
    local gameState = ctx.cache.IdentityGameState
    local sourceClass = ctx.cache.IdentityGameStateSourceClass or 'GameStateBase'
    if not safe.isValidObject(gameState) then
      local err
      gameState, sourceClass, err = getGameState()
      if err and not safe.isValidObject(gameState) then return 'lua_error', nil, nil, err end
    end
    if not safe.isValidObject(gameState) then
      return 'nil', 'identity_roster_shape', 'sourcePath=' .. tostring(sourceClass) .. '.PlayerArray valueKind=nil rawIdentityEvidence=false', nil, {
        sourceScope = 'runtime_roster_candidate',
        sourcePath = tostring(sourceClass) .. '.PlayerArray',
        sourceClass = tostring(sourceClass),
        visiblePlayerCount = 0,
        visiblePlayerCap = cap,
        displayNameFingerprints = {},
        stableIdFingerprints = {},
        identityRawRedacted = true,
        rawIdentityEvidence = false,
        playerArrayValueKind = 'nil',
        playerArrayTableSampleCount = 0,
        rosterSourceResolved = false,
        localNotes = 'GameState unavailable; no PlayerArray traversal performed'
      }
    end

    local playerArray, playerArrayErr = safe.getProperty(gameState, 'PlayerArray')
    if playerArrayErr then return 'lua_error', nil, nil, playerArrayErr end
    local kind, tableSampleCount, isTable = arrayShape(playerArray)
    local result = isTable and 'ok' or 'nil'
    local summary = 'sourcePath=' .. tostring(sourceClass) .. '.PlayerArray'
      .. ' valueKind=' .. tostring(kind)
      .. ' tableSampleCount=' .. tostring(tableSampleCount)
      .. ' cap=' .. tostring(cap)
      .. ' rawIdentityEvidence=false'
    return result, 'identity_roster_shape', summary, nil, {
      sourceScope = 'runtime_roster_candidate',
      sourcePath = tostring(sourceClass) .. '.PlayerArray',
      sourceClass = tostring(sourceClass),
      visiblePlayerCount = 0,
      visiblePlayerCap = cap,
      displayNameFingerprints = {},
      stableIdFingerprints = {},
      identityRawRedacted = true,
      rawIdentityEvidence = false,
      playerArrayValueKind = kind,
      playerArrayTableSampleCount = tableSampleCount,
      rosterSourceResolved = false,
      localNotes = 'Shape-only PlayerArray check; records nil/userdata/table/unsupported kind and samples table length up to cap; no recursive traversal'
    }
  end, {
    symbol = 'GameStateBase.PlayerArray',
    owner = 'GameStateBase',
    member = 'PlayerArray',
    accessMethod = 'GetPropertyValueShapeOnly',
    accessKind = 'identityRosterShape',
    sourceScope = 'runtime_roster_candidate'
  })

  probes[#probes + 1] = mk('Identity.FindAll.PlayerStateCandidates', 'identity', 'multiplayer-roster-read', 'findAllPlayerStateCandidates', function(ctx)
    local cap = 16
    local available, availabilityResult, availabilityErr = findAllAvailability()
    if availabilityResult == 'lua_error' then return 'lua_error', nil, nil, availabilityErr end
    if not available then
      return 'nil', 'identity_roster_candidates', 'FindAllOf unavailable; visiblePlayerCount=0 cap=' .. tostring(cap) .. ' rawIdentityEvidence=false', nil, {
        sourceScope = 'runtime_roster_candidate',
        sourcePath = 'FindAllOf(PlayerState,CrabPS)',
        sourceClass = 'PlayerState',
        candidateClasses = { 'PlayerState', 'CrabPS' },
        visiblePlayerCount = 0,
        visiblePlayerCap = cap,
        displayNameFingerprints = {},
        stableIdFingerprints = {},
        identityRawRedacted = ctx.config.allowRawIdentityEvidence ~= true,
        rawIdentityEvidence = false,
        rosterSourceResolved = false,
        localNotes = 'FindAllOf availability check failed; no PlayerState candidates traversed'
      }
    end

    local samples, rawNames, rawIds, count, attempted, err = collectFindAllPlayerStates({ 'PlayerState', 'CrabPS' }, cap, ctx.config or {})
    if err then return 'lua_error', nil, nil, err end
    local summary, display, ids = summarizeIdentitySamples(samples or {}, 'visiblePlayerCount=' .. tostring(count) .. ' cap=' .. tostring(cap) .. ' sourcePath=FindAllOf(' .. tostring(attempted) .. ')')
    return count > 0 and 'ok' or 'nil', 'identity_roster_candidates', summary, nil, {
      sourceScope = 'runtime_roster_candidate',
      sourcePath = 'FindAllOf(' .. tostring(attempted) .. ')',
      sourceClass = 'PlayerState',
      candidateClasses = { 'PlayerState', 'CrabPS' },
      localPlayerPresent = safe.isValidObject(ctx.cache.IdentityLocalPlayerState),
      visiblePlayerCount = count,
      visiblePlayerCap = cap,
      displayNameFingerprints = display,
      stableIdFingerprints = ids,
      identityRawRedacted = ctx.config.allowRawIdentityEvidence ~= true,
      rawIdentityEvidence = ctx.config.allowRawIdentityEvidence == true,
      rawDisplayNames = ctx.config.allowRawIdentityEvidence == true and rawNames or nil,
      rawStableIds = ctx.config.allowRawIdentityEvidence == true and rawIds or nil,
      rosterSourceResolved = count > 1,
      localNotes = 'FindAllOf availability checked before capped PlayerState-like candidate traversal; sampled PlayerState and CrabPS only, cap=16, no raw identity by default'
    }
  end, {
    symbol = 'PlayerState CrabPS',
    owner = 'Runtime',
    member = 'PlayerState',
    accessMethod = 'FindAllOfCapped',
    accessKind = 'identityRosterCandidates',
    sourceScope = 'runtime_roster_candidate'
  })

  probes[#probes + 1] = mk('Identity.PlayerControllerCandidates', 'identity', 'multiplayer-roster-read', 'playerControllerCandidates', function(ctx)
    local cap = 8
    local available, availabilityResult, availabilityErr = findAllAvailability()
    if availabilityResult == 'lua_error' then return 'lua_error', nil, nil, availabilityErr end
    if not available then
      return 'nil', 'identity_controller_candidates', 'FindAllOf unavailable; visiblePlayerCount=0 cap=' .. tostring(cap) .. ' rawIdentityEvidence=false', nil, {
        sourceScope = 'runtime_roster_candidate',
        sourcePath = 'FindAllOf(PlayerController,CrabPC).PlayerState',
        sourceClass = 'PlayerController',
        candidateClasses = { 'PlayerController', 'CrabPC' },
        visiblePlayerCount = 0,
        visiblePlayerCap = cap,
        displayNameFingerprints = {},
        stableIdFingerprints = {},
        identityRawRedacted = ctx.config.allowRawIdentityEvidence ~= true,
        rawIdentityEvidence = false,
        rosterSourceResolved = false,
        localNotes = 'FindAllOf availability check failed; no PlayerController candidates traversed'
      }
    end

    local samples = {}
    local rawNames = {}
    local rawIds = {}
    local count = 0
    local attempted = {}
    for _, className in ipairs({ 'PlayerController', 'CrabPC' }) do
      if count >= cap then break end
      attempted[#attempted + 1] = className
      local controllers, err = safe.findAll(className)
      if err then return 'lua_error', nil, nil, err end
      if type(controllers) == 'table' then
        safe.forEachArrayLimited(controllers, cap - count, function(_, elem)
          local controller = objectFromArrayElement(elem)
          if safe.isValidObject(controller) then
            local playerState = safe.getProperty(controller, 'PlayerState')
            if safe.isValidObject(playerState) then
              local sample = samplePlayerStateIdentity(playerState, ctx.config or {})
              samples[#samples + 1] = sample
              if ctx.config.allowRawIdentityEvidence == true then
                rawNames[#rawNames + 1] = sample.rawDisplayName or ''
                rawIds[#rawIds + 1] = sample.rawStableId or ''
              end
              count = count + 1
            end
          end
        end)
      end
    end
    local summary, display, ids = summarizeIdentitySamples(samples, 'visiblePlayerCount=' .. tostring(count) .. ' cap=' .. tostring(cap) .. ' sourcePath=FindAllOf(' .. table.concat(attempted, ',') .. ').PlayerState')
    return count > 0 and 'ok' or 'nil', 'identity_controller_candidates', summary, nil, {
      sourceScope = 'runtime_roster_candidate',
      sourcePath = 'FindAllOf(' .. table.concat(attempted, ',') .. ').PlayerState',
      sourceClass = 'PlayerController',
      candidateClasses = { 'PlayerController', 'CrabPC' },
      localPlayerPresent = safe.isValidObject(ctx.cache.IdentityLocalPlayerState),
      visiblePlayerCount = count,
      visiblePlayerCap = cap,
      displayNameFingerprints = display,
      stableIdFingerprints = ids,
      identityRawRedacted = ctx.config.allowRawIdentityEvidence ~= true,
      rawIdentityEvidence = ctx.config.allowRawIdentityEvidence == true,
      rawDisplayNames = ctx.config.allowRawIdentityEvidence == true and rawNames or nil,
      rawStableIds = ctx.config.allowRawIdentityEvidence == true and rawIds or nil,
      rosterSourceResolved = count > 1,
      localNotes = 'FindAllOf availability checked before capped PlayerController/CrabPC traversal; only PlayerState property was read from valid controllers, cap=8'
    }
  end, {
    symbol = 'PlayerController CrabPC',
    owner = 'Runtime',
    member = 'PlayerController.PlayerState',
    accessMethod = 'FindAllOfCapped',
    accessKind = 'identityControllerCandidates',
    sourceScope = 'runtime_roster_candidate'
  })

  probes[#probes + 1] = mk('Identity.VisiblePlayers.Sample', 'identity', 'multiplayer-roster-read', 'visiblePlayers', function(ctx)
    local cap = 8
    local gameState, sourceClass, gameStateErr = getGameState()
    if gameStateErr and not safe.isValidObject(gameState) then return 'lua_error', nil, nil, gameStateErr end
    if not safe.isValidObject(gameState) then
      return 'nil', 'identity_roster', 'visiblePlayerCount=0 sourcePath=' .. tostring(sourceClass) .. '.PlayerArray rawIdentityEvidence=false', nil, {
        sourceScope = 'runtime_roster',
        sourcePath = tostring(sourceClass) .. '.PlayerArray',
        sourceClass = tostring(sourceClass),
        localPlayerPresent = safe.isValidObject(ctx.cache.IdentityLocalPlayerState),
        visiblePlayerCount = 0,
        visiblePlayerCap = cap,
        displayNameFingerprints = {},
        stableIdFingerprints = {},
        hostClientRoleConsistent = ctx.role ~= 'unknown',
        identityRawRedacted = ctx.config.allowRawIdentityEvidence ~= true,
        rawIdentityEvidence = ctx.config.allowRawIdentityEvidence == true,
        playerArrayValueKind = 'nil',
        playerArrayTableSampleCount = 0,
        rosterSourceResolved = false,
        localNotes = 'GameState unavailable; no roster traversal performed'
      }
    end

    local playerArray, playerArrayErr = safe.getProperty(gameState, 'PlayerArray')
    if playerArrayErr then return 'lua_error', nil, nil, playerArrayErr end
    local kind, tableSampleCount = arrayShape(playerArray)
    if type(playerArray) ~= 'table' then
      return 'nil', 'identity_roster', 'visiblePlayerCount=0 sourcePath=' .. tostring(sourceClass) .. '.PlayerArray rawIdentityEvidence=false', nil, {
        sourceScope = 'runtime_roster',
        sourcePath = tostring(sourceClass) .. '.PlayerArray',
        sourceClass = tostring(sourceClass),
        localPlayerPresent = safe.isValidObject(ctx.cache.IdentityLocalPlayerState),
        visiblePlayerCount = 0,
        visiblePlayerCap = cap,
        displayNameFingerprints = {},
        stableIdFingerprints = {},
        hostClientRoleConsistent = ctx.role ~= 'unknown',
        identityRawRedacted = ctx.config.allowRawIdentityEvidence ~= true,
        rawIdentityEvidence = ctx.config.allowRawIdentityEvidence == true,
        playerArrayValueKind = kind,
        playerArrayTableSampleCount = tableSampleCount,
        rosterSourceResolved = false,
        localNotes = 'PlayerArray was not exposed as a Lua table; no recursive traversal performed'
      }
    end

    local samples, rawNames, rawIds, count = collectPlayerStateSamplesFromArray(playerArray, cap, ctx.config or {})

    local summary, display, ids = summarizeIdentitySamples(samples, 'visiblePlayerCount=' .. tostring(count) .. ' cap=' .. tostring(cap) .. ' sourcePath=' .. tostring(sourceClass) .. '.PlayerArray')
    return 'ok', 'identity_roster', summary, nil, {
      sourceScope = 'runtime_roster',
      sourcePath = tostring(sourceClass) .. '.PlayerArray',
      sourceClass = tostring(sourceClass),
      localPlayerPresent = safe.isValidObject(ctx.cache.IdentityLocalPlayerState),
      visiblePlayerCount = count,
      visiblePlayerCap = cap,
      displayNameFingerprints = display,
      stableIdFingerprints = ids,
      hostClientRoleConsistent = ctx.role ~= 'unknown',
      identityRawRedacted = ctx.config.allowRawIdentityEvidence ~= true,
      rawIdentityEvidence = ctx.config.allowRawIdentityEvidence == true,
      rawDisplayNames = ctx.config.allowRawIdentityEvidence == true and rawNames or nil,
      rawStableIds = ctx.config.allowRawIdentityEvidence == true and rawIds or nil,
      playerArrayValueKind = kind,
      playerArrayTableSampleCount = tableSampleCount,
      rosterSourceResolved = count > 1,
      localNotes = 'capped read-only GameState.PlayerArray identity sample; no recursive object walking'
    }
  end, {
    symbol = 'GameState.PlayerArray',
    owner = 'GameState',
    member = 'PlayerArray',
    accessMethod = 'GetPropertyValue',
    accessKind = 'identityRoster',
    sourceScope = 'runtime_roster'
  })

  probes[#probes + 1] = mk('Identity.VisiblePlayers.SourceCandidate', 'identity', 'multiplayer-roster-read', 'visiblePlayersSourceCandidate', function(ctx)
    local cap = 16
    local gameState = ctx.cache.IdentityGameState
    local sourceClass = ctx.cache.IdentityGameStateSourceClass or 'GameStateBase'
    if not safe.isValidObject(gameState) then
      local err
      gameState, sourceClass, err = getGameState()
      if err and not safe.isValidObject(gameState) then return 'lua_error', nil, nil, err end
    end
    if not safe.isValidObject(gameState) then
      return 'nil', 'identity_roster_candidate', 'visiblePlayerCount=0 sourcePath=' .. tostring(sourceClass) .. '.PlayerArray rawIdentityEvidence=false', nil, {
        sourceScope = 'runtime_roster_candidate',
        sourcePath = tostring(sourceClass) .. '.PlayerArray',
        sourceClass = tostring(sourceClass),
        localPlayerPresent = safe.isValidObject(ctx.cache.IdentityLocalPlayerState),
        visiblePlayerCount = 0,
        visiblePlayerCap = cap,
        displayNameFingerprints = {},
        stableIdFingerprints = {},
        identityRawRedacted = ctx.config.allowRawIdentityEvidence ~= true,
        rawIdentityEvidence = false,
        playerArrayValueKind = 'nil',
        playerArrayTableSampleCount = 0,
        rosterSourceResolved = false,
        localNotes = 'Visible roster source candidate: GameState unavailable; no PlayerArray traversal performed'
      }
    end

    local playerArray, playerArrayErr = safe.getProperty(gameState, 'PlayerArray')
    if playerArrayErr then return 'lua_error', nil, nil, playerArrayErr end
    local kind, tableSampleCount = arrayShape(playerArray)
    if type(playerArray) ~= 'table' then
      return 'nil', 'identity_roster_candidate', 'visiblePlayerCount=0 sourcePath=' .. tostring(sourceClass) .. '.PlayerArray valueKind=' .. tostring(kind) .. ' rawIdentityEvidence=false', nil, {
        sourceScope = 'runtime_roster_candidate',
        sourcePath = tostring(sourceClass) .. '.PlayerArray',
        sourceClass = tostring(sourceClass),
        localPlayerPresent = safe.isValidObject(ctx.cache.IdentityLocalPlayerState),
        visiblePlayerCount = 0,
        visiblePlayerCap = cap,
        displayNameFingerprints = {},
        stableIdFingerprints = {},
        identityRawRedacted = ctx.config.allowRawIdentityEvidence ~= true,
        rawIdentityEvidence = false,
        playerArrayValueKind = kind,
        playerArrayTableSampleCount = tableSampleCount,
        rosterSourceResolved = false,
        localNotes = 'Visible roster source candidate: PlayerArray was not a Lua table; no recursive traversal performed'
      }
    end

    local samples, rawNames, rawIds, count = collectPlayerStateSamplesFromArray(playerArray, cap, ctx.config or {})
    local summary, display, ids = summarizeIdentitySamples(samples, 'visiblePlayerCount=' .. tostring(count) .. ' cap=' .. tostring(cap) .. ' sourcePath=' .. tostring(sourceClass) .. '.PlayerArray')
    return count > 0 and 'ok' or 'nil', 'identity_roster_candidate', summary, nil, {
      sourceScope = 'runtime_roster_candidate',
      sourcePath = tostring(sourceClass) .. '.PlayerArray',
      sourceClass = tostring(sourceClass),
      localPlayerPresent = safe.isValidObject(ctx.cache.IdentityLocalPlayerState),
      visiblePlayerCount = count,
      visiblePlayerCap = cap,
      displayNameFingerprints = display,
      stableIdFingerprints = ids,
      identityRawRedacted = ctx.config.allowRawIdentityEvidence ~= true,
      rawIdentityEvidence = ctx.config.allowRawIdentityEvidence == true,
      rawDisplayNames = ctx.config.allowRawIdentityEvidence == true and rawNames or nil,
      rawStableIds = ctx.config.allowRawIdentityEvidence == true and rawIds or nil,
      playerArrayValueKind = kind,
      playerArrayTableSampleCount = tableSampleCount,
      rosterSourceResolved = count > 1,
      localNotes = 'Visible roster source candidate: capped read-only GameStateBase.PlayerArray path, cap=16; no recursive object walking'
    }
  end, {
    symbol = 'GameStateBase.PlayerArray',
    owner = 'GameStateBase',
    member = 'PlayerArray',
    accessMethod = 'GetPropertyValueCapped',
    accessKind = 'identityRosterCandidate',
    sourceScope = 'runtime_roster_candidate'
  })

  probes[#probes + 1] = mk('ResourceVisibility.PlayerState.Sample', 'resource-visibility', 'multiplayer-resource-visibility-read', 'playerStateResourceVisibility', function(ctx)
    local stats = buildResourceVisibilityCache(ctx)
    if stats.error then return 'lua_error', nil, nil, stats.error end
    local summary = stats.identitySummary or resourceVisibilitySummary(stats, 'identity')
    return stats.sampledPlayerStateCount > 0 and 'ok' or 'nil', 'resource_visibility_identity', summary, nil,
      resourceVisibilityMeta(stats, 'Capped read-only visible PlayerState/CrabPS candidate identity fingerprints; no raw names or UniqueIds emitted')
  end, {
    symbol = 'PlayerState.Identity',
    owner = 'PlayerState',
    member = 'PlayerName UniqueId',
    accessMethod = 'GetPropertyValue',
    accessKind = 'resourceVisibilityIdentity',
    sourceScope = 'runtime_resource_visibility'
  })

  probes[#probes + 1] = mk('ResourceVisibility.Health.Sample', 'resource-visibility', 'multiplayer-resource-visibility-read', 'healthResourceVisibility', function(ctx)
    local stats = buildResourceVisibilityCache(ctx)
    if stats.error then return 'lua_error', nil, nil, stats.error end
    return stats.readableHealthCount > 0 and 'ok' or 'nil', 'resource_visibility_health',
      resourceVisibilitySummary(stats, 'health'), nil,
      resourceVisibilityMeta(stats, 'Read-only HealthInfo.CurrentHealth/CurrentMaxHealth plus BaseMaxHealth/MaxHealthMultiplier checks from visible PlayerStates; no CrabHC touched')
  end, {
    symbol = 'CrabPS.HealthInfo',
    owner = 'CrabPS',
    member = 'HealthInfo',
    accessMethod = 'RemotePlayerStateHealthSample',
    accessKind = 'health',
    sourceScope = 'runtime_resource_visibility'
  })

  probes[#probes + 1] = mk('ResourceVisibility.Resources.Sample', 'resource-visibility', 'multiplayer-resource-visibility-read', 'resourceScalarVisibility', function(ctx)
    local stats = buildResourceVisibilityCache(ctx)
    if stats.error then return 'lua_error', nil, nil, stats.error end
    return (stats.readableCrystalsCount > 0 or stats.readableKeysCount > 0) and 'ok' or 'nil', 'resource_visibility_resources',
      resourceVisibilitySummary(stats, 'resources'), nil,
      resourceVisibilityMeta(stats, 'Read-only Crystals and optional Keys scalar visibility checks')
  end, {
    symbol = 'CrabPS.Crystals',
    owner = 'CrabPS',
    member = 'Crystals Keys',
    accessMethod = 'GetPropertyValue',
    accessKind = 'getProperty',
    sourceScope = 'runtime_resource_visibility'
  })

  probes[#probes + 1] = mk('ResourceVisibility.Slots.Sample', 'resource-visibility', 'multiplayer-resource-visibility-read', 'slotScalarVisibility', function(ctx)
    local stats = buildResourceVisibilityCache(ctx)
    if stats.error then return 'lua_error', nil, nil, stats.error end
    return stats.readableSlotsCount > 0 and 'ok' or 'nil', 'resource_visibility_slots',
      resourceVisibilitySummary(stats, 'slots'), nil,
      resourceVisibilityMeta(stats, 'Read-only NumWeaponModSlots/NumAbilityModSlots/NumMeleeModSlots/NumPerkSlots visibility checks')
  end, {
    symbol = 'CrabPS.NumWeaponModSlots',
    owner = 'CrabPS',
    member = 'NumWeaponModSlots NumAbilityModSlots NumMeleeModSlots NumPerkSlots',
    accessMethod = 'GetPropertyValue',
    accessKind = 'getProperty',
    sourceScope = 'runtime_resource_visibility'
  })

  probes[#probes + 1] = mk('ResourceVisibility.Equipment.Sample', 'resource-visibility', 'multiplayer-resource-visibility-read', 'equipmentVisibility', function(ctx)
    local stats = buildResourceVisibilityCache(ctx)
    if stats.error then return 'lua_error', nil, nil, stats.error end
    return stats.readableEquipmentCount > 0 and 'ok' or 'nil', 'resource_visibility_equipment',
      resourceVisibilitySummary(stats, 'equipment'), nil,
      resourceVisibilityMeta(stats, 'Read-only WeaponDA/AbilityDA/MeleeDA property visibility checks; object identities are not dereferenced or summarized in this phase')
  end, {
    symbol = 'CrabPS.WeaponDA',
    owner = 'CrabPS',
    member = 'WeaponDA AbilityDA MeleeDA',
    accessMethod = 'GetPropertyValue',
    accessKind = 'getProperty',
    sourceScope = 'runtime_resource_visibility'
  })

  probes[#probes + 1] = mk('ResourceVisibility.InventoryArrays.ShallowSample', 'resource-visibility', 'multiplayer-resource-visibility-read', 'inventoryArrayShallowVisibility', function(ctx)
    local stats = buildResourceVisibilityCache(ctx)
    if stats.error then return 'lua_error', nil, nil, stats.error end
    return stats.readableInventoryArrayCount > 0 and 'ok' or 'nil', 'resource_visibility_inventory_arrays',
      resourceVisibilitySummary(stats, 'inventory-arrays'), nil,
      resourceVisibilityMeta(stats, 'Read-only count-only checks for WeaponMods/AbilityMods/MeleeMods/Perks/Relics; no element dereference, InventoryInfo, or Enhancements')
  end, {
    symbol = 'CrabPS.WeaponMods',
    owner = 'CrabPS',
    member = 'WeaponMods AbilityMods MeleeMods Perks Relics',
    accessMethod = 'GetPropertyValueCountOnly',
    accessKind = 'getPropertyCountOnly',
    sourceScope = 'runtime_resource_visibility'
  })

  probes[#probes + 1] = mk('Inventory.LocalSlots.Sample', 'inventory-local', 'local-inventory-array-shallow-read', 'localSlotScalars', function(ctx)
    local stats = buildLocalInventoryArrayCache(ctx)
    if stats.error then return 'lua_error', nil, nil, stats.error end
    local hasSlot = false
    for _, value in pairs(stats.slotScalarValues or {}) do
      if value ~= nil then hasSlot = true end
    end
    return hasSlot and 'ok' or 'nil', 'local_inventory_slots',
      localInventorySummary(stats, 'slots'), nil,
      localInventoryMeta(stats, 'Read-only local CrabPC -> PlayerState slot scalar sample for inventory array correlation')
  end, {
    symbol = 'CrabPS.NumWeaponModSlots',
    owner = 'CrabPS',
    member = 'NumWeaponModSlots NumAbilityModSlots NumMeleeModSlots NumPerkSlots',
    accessMethod = 'GetPropertyValue',
    accessKind = 'localSlotScalars',
    sourceScope = 'local_player_state_inventory_arrays'
  })

  probes[#probes + 1] = mk('Inventory.LocalArrays.Shape', 'inventory-local', 'local-inventory-array-shallow-read', 'localInventoryArrayShape', function(ctx)
    local stats = buildLocalInventoryArrayCache(ctx)
    if stats.error then return 'lua_error', nil, nil, stats.error end
    return (#(stats.fieldsReadable or {}) > 0) and 'ok' or 'nil', 'local_inventory_array_shape',
      localInventorySummary(stats, 'array-shape'), nil,
      localInventoryMeta(stats, 'Read-only local CrabPC -> PlayerState -> CrabPS array shape check; no element dereference, InventoryInfo, Enhancements, writes, or RPCs')
  end, {
    symbol = 'CrabPS.WeaponMods',
    owner = 'CrabPS',
    member = 'WeaponMods AbilityMods MeleeMods Perks Relics',
    accessMethod = 'GetPropertyValueShapeOnly',
    accessKind = 'localInventoryArrayShape',
    sourceScope = 'local_player_state_inventory_arrays'
  })

  probes[#probes + 1] = mk('Inventory.LocalArrays.CountOnly', 'inventory-local', 'local-inventory-array-shallow-read', 'localInventoryArrayCountOnly', function(ctx)
    local stats = buildLocalInventoryArrayCache(ctx)
    if stats.error then return 'lua_error', nil, nil, stats.error end
    local hasCount = false
    for _, count in pairs(stats.arrayCounts or {}) do
      if type(count) == 'number' then hasCount = true end
    end
    return (hasCount or #(stats.fieldsReadable or {}) > 0) and 'ok' or 'nil', 'local_inventory_array_count_only',
      localInventorySummary(stats, 'array-count-only'), nil,
      localInventoryMeta(stats, 'Count-only local inventory array check; table counts are capped and elements are never dereferenced')
  end, {
    symbol = 'CrabPS.WeaponMods',
    owner = 'CrabPS',
    member = 'WeaponMods AbilityMods MeleeMods Perks Relics',
    accessMethod = 'GetPropertyValueCountOnly',
    accessKind = 'localInventoryArrayCountOnly',
    sourceScope = 'local_player_state_inventory_arrays'
  })

  probes[#probes + 1] = mk('Inventory.LocalArrays.ShapeConfirm', 'inventory-local-shape-confirm', 'local-inventory-array-shape-confirm', 'localInventoryArrayShapeConfirm', function(ctx)
    local stats = buildLocalInventoryShapeConfirmCache(ctx)
    if stats.error then return 'lua_error', nil, nil, stats.error end
    return (#(stats.fieldsReadable or {}) > 0) and 'ok' or 'nil', 'local_inventory_array_shape_confirm',
      localInventoryShapeConfirmSummary(stats), nil,
      localInventoryShapeConfirmMeta(stats, 'Read-only local CrabPC -> PlayerState -> CrabPS property shape confirm; no count, traversal, element dereference, InventoryInfo, Enhancements, writes, or RPCs')
  end, {
    symbol = 'CrabPS.WeaponMods',
    owner = 'CrabPS',
    member = 'WeaponMods AbilityMods MeleeMods Perks Relics',
    accessMethod = 'GetPropertyValueShapeConfirm',
    accessKind = 'localInventoryArrayShapeConfirm',
    sourceScope = 'local_player_state_inventory_shape_confirm'
  })

  probes[#probes + 1] = mk('Inventory.LocalArrays.UserdataIntrospection', 'inventory-local-userdata-introspection', 'local-inventory-userdata-introspection', 'localInventoryUserdataIntrospection', function(ctx)
    local stats = buildLocalInventoryUserdataIntrospectionCache(ctx)
    if stats.error then return 'lua_error', nil, nil, stats.error end
    return (#(stats.fieldsReadable or {}) > 0) and 'ok' or 'nil', 'local_inventory_userdata_introspection',
      localInventoryUserdataIntrospectionSummary(stats), nil,
      localInventoryUserdataIntrospectionMeta(stats, 'Read-only local CrabPC -> PlayerState -> CrabPS userdata wrapper metadata; no traversal, element dereference, InventoryInfo, Enhancements, writes, RPCs, HUD, or deep arrays')
  end, {
    symbol = 'CrabPS.WeaponMods',
    owner = 'CrabPS',
    member = 'WeaponMods AbilityMods MeleeMods Perks Relics',
    accessMethod = 'GetPropertyValueUserdataMetadata',
    accessKind = 'localInventoryUserdataIntrospection',
    sourceScope = 'local_player_state_inventory_userdata_introspection'
  })

  probes[#probes + 1] = mk('Inventory.LocalArrays.CountRead', 'inventory-array-count-read', 'inventory-array-count-read', 'inventoryArrayCountRead', function(ctx)
    local stats = buildInventoryArrayCountReadCache(ctx)
    if stats.error then return 'lua_error', nil, nil, stats.error end
    local hasEvidence = stats.localPlayerStatePresent == true and (
      #(stats.fieldsReadable or {}) > 0 or #(stats.fieldsNilOrUnsupported or {}) > 0
    )
    return hasEvidence and 'ok' or 'nil', 'inventory_array_count_read',
      inventoryArrayCountReadSummary(stats), nil,
      inventoryArrayCountReadMeta(stats, 'Read-only local CrabPC -> PlayerState -> CrabPS array wrapper count metadata using only pcall(#value); no traversal, element dereference, item DataAsset reads, InventoryInfo, Enhancements, writes, RPCs, HUD, or deep arrays')
  end, {
    symbol = 'CrabPS.WeaponMods',
    owner = 'CrabPS',
    member = 'WeaponMods AbilityMods MeleeMods Perks Relics',
    accessMethod = 'GetPropertyValueLuaLenPcall',
    accessKind = 'inventoryArrayCountRead',
    sourceScope = 'local_player_state_inventory_array_count_read'
  })

  probes[#probes + 1] = mk('Inventory.LocalArrays.ElementDARead', 'inventory-element-da-read', 'inventory-element-da-read', 'inventoryElementDARead', function(ctx)
    local stats = buildInventoryElementDAReadCache(ctx)
    if stats.error then return 'lua_error', nil, nil, stats.error end
    local hasEvidence = stats.localPlayerStatePresent == true and (
      #(stats.fieldsReadable or {}) > 0 or #(stats.fieldsNilOrUnsupported or {}) > 0 or #(stats.nonEmptyArrayFields or {}) > 0
    )
    return hasEvidence and 'ok' or 'nil', 'inventory_element_da_read',
      inventoryElementDAReadSummary(stats), nil,
      inventoryElementDAReadMeta(stats, 'Read-only local CrabPC -> PlayerState -> CrabPS capped first-element DA identity proof phase. Current runtime path records count metadata and returns unsupported when no safe first-element helper exists; it does not traverse arrays, iterate arrays, dereference elements, read InventoryInfo, Enhancements, Level, AccumulatedBuff, mutate DataAssets, call functions, write, RPC, HUD, or broad deep arrays.')
  end, {
    symbol = 'CrabPS.WeaponMods',
    owner = 'CrabPS',
    member = 'WeaponMods AbilityMods MeleeMods Perks Relics',
    accessMethod = 'GetPropertyValueCountThenCappedFirstElementIfSupported',
    accessKind = 'inventoryElementDARead',
    sourceScope = 'local_player_state_inventory_element_da_read'
  })

  probes[#probes + 1] = mk('Resource.Crystals.Read', 'resource-crystals', 'crystals-read', 'localCrystalsRead', function(ctx)
    local stats = buildCrystalsReadCache(ctx)
    if stats.error then return 'lua_error', nil, nil, stats.error, crystalsReadMeta(stats, 'Read-only local CrabPC -> PlayerState -> CrabPS Crystals scalar read; UInt32 range documented only, with no writes, RPCs, HUD, inventory arrays, InventoryInfo, Enhancements, or deep arrays') end
    return stats.crystalsPresent and 'ok' or 'nil', 'crystals_read',
      crystalsReadSummary(stats), nil,
      crystalsReadMeta(stats, 'Read-only local CrabPC -> PlayerState -> CrabPS Crystals scalar read; UInt32 range documented only, with no writes, RPCs, HUD, inventory arrays, InventoryInfo, Enhancements, or deep arrays')
  end, {
    symbol = 'CrabPS.Crystals',
    owner = 'CrabPS',
    member = 'Crystals',
    accessMethod = 'GetPropertyValue',
    accessKind = 'localCrystalsRead',
    sourceScope = 'local_player_state_crystals'
  })

  probes[#probes + 1] = mk('Resource.Slots.Read', 'resource-slots', 'slots-read', 'localSlotsRead', function(ctx)
    local stats = buildSlotsReadCache(ctx)
    if stats.error then return 'lua_error', nil, nil, stats.error, slotsReadMeta(stats, 'Read-only local CrabPC -> PlayerState -> CrabPS candidate slot scalar reads; ByteProperty range 0..255 documented only, locked/max slot model unresolved, with no writes, RPCs, HUD, inventory arrays, InventoryInfo, Enhancements, or deep arrays') end
    return (#(stats.fieldsReadable or {}) > 0) and 'ok' or 'nil', 'slots_read',
      slotsReadSummary(stats), nil,
      slotsReadMeta(stats, 'Read-only local CrabPC -> PlayerState -> CrabPS candidate slot scalar reads; ByteProperty range 0..255 documented only, locked/max slot model unresolved, with no writes, RPCs, HUD, inventory arrays, InventoryInfo, Enhancements, or deep arrays')
  end, {
    symbol = 'CrabPS.NumWeaponModSlots',
    owner = 'CrabPS',
    member = 'NumWeaponModSlots NumAbilityModSlots NumMeleeModSlots NumPerkSlots',
    accessMethod = 'GetPropertyValue',
    accessKind = 'localSlotsRead',
    sourceScope = 'local_player_state_slots'
  })

  probes[#probes + 1] = mk('SafeWatch.Scalar.Sample', 'safe-scalar-watch', 'safe-scalar-watch', 'sample', function(ctx)
    return readSafeScalarWatchSample(ctx)
  end, {
    symbol = 'CrabPS.SafeScalarWatch',
    owner = 'CrabPS',
    member = 'WeaponDA AbilityDA MeleeDA Crystals Num*Slots HealthInfo',
    accessMethod = 'SafeScalarWatchSample',
    accessKind = 'safeScalarWatch',
    sourceScope = 'local_safe_scalar_watch'
  })

  probes[#probes + 1] = mk('DataAsset.Perks.CatalogRead', 'perk-da-catalog-read', 'perk-da-catalog-read', 'catalogRead', function(ctx)
    return collectPerkDataAssetCatalog(ctx)
  end, {
    symbol = 'CrabPerkDA',
    owner = 'DataAsset',
    member = 'Perk DataAsset curated fields',
    accessMethod = 'FindAllOfCappedCuratedClasses',
    accessKind = 'perkDataAssetCatalogRead',
    sourceScope = 'perk_data_asset_catalog'
  })

  probes[#probes + 1] = mk('MaxSafePlay.Scalar.Sample', 'max-safe-play-recorder', 'max-safe-play-recorder', 'scalarSample', function(ctx)
    return readMaxSafePlayScalarSample(ctx)
  end, {
    symbol = 'CrabPS.MaxSafePlayScalar',
    owner = 'CrabPS',
    member = 'WeaponDA AbilityDA MeleeDA Crystals Num*Slots HealthInfo',
    accessMethod = 'MaxSafePlayScalarSample',
    accessKind = 'maxSafePlayScalar',
    sourceScope = 'max_safe_play_recorder_scalar'
  })

  probes[#probes + 1] = mk('MaxSafePlay.PerkDataAsset.CatalogSnapshot', 'max-safe-play-recorder', 'max-safe-play-recorder', 'perkCatalogSnapshot', function(ctx)
    return readMaxSafePlayPerkCatalogSnapshot(ctx)
  end, {
    symbol = 'CrabPerkDA',
    owner = 'DataAsset',
    member = 'Perk DataAsset curated fields',
    accessMethod = 'FindAllOfCappedCuratedClasses',
    accessKind = 'maxSafePlayPerkDataAssetCatalogSnapshot',
    sourceScope = 'max_safe_play_recorder_perk_catalog'
  })

  probes[#probes + 1] = mk('MaxSafePlay.Session.Heartbeat', 'max-safe-play-recorder', 'max-safe-play-recorder', 'sessionHeartbeat', function(ctx)
    return readMaxSafePlaySessionHeartbeat(ctx)
  end, {
    symbol = 'Runtime.MaxSafePlaySession',
    owner = 'Runtime',
    member = 'RecorderHeartbeat',
    accessMethod = 'MaxSafePlaySessionHeartbeat',
    accessKind = 'maxSafePlaySession',
    sourceScope = 'max_safe_play_recorder_session'
  })

  probes[#probes + 1] = mk('MaxSafePlay.Session.Summary', 'max-safe-play-recorder', 'max-safe-play-recorder', 'sessionSummary', function(ctx)
    return readMaxSafePlaySessionSummary(ctx)
  end, {
    symbol = 'Runtime.MaxSafePlaySession',
    owner = 'Runtime',
    member = 'RecorderSummary',
    accessMethod = 'MaxSafePlaySessionSummary',
    accessKind = 'maxSafePlaySession',
    sourceScope = 'max_safe_play_recorder_session'
  })

  probes[#probes + 1] = mk('FindAllOf.CrabHC.Availability', 'health', 'health-hc-discovery-read', 'findAllAvailability', function()
    local ok, value = pcall(function() return type(FindAllOf) end)
    if not ok then return 'lua_error', nil, tostring(value) end
    if value ~= 'function' then
      return 'nil', 'string', 'FindAllOf unavailable; candidate traversal deferred', nil, {
        sourceScope = 'ambiguous',
        localNotes = 'availability check only; no CrabHC candidates traversed'
      }
    end
    return 'ok', 'string', 'FindAllOf available; CrabHC candidate traversal intentionally deferred until capped ownership probes are reviewed', nil, {
      sourceScope = 'ambiguous',
      localNotes = 'availability check only; no CrabHC candidates traversed'
    }
  end, {
    symbol = 'CrabHC',
    owner = 'Runtime',
    member = 'CrabHC',
    accessMethod = 'FindAllOfAvailability',
    accessKind = 'findAll',
    sourceScope = 'ambiguous'
  })

  return probes
end

return registry

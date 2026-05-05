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

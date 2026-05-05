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

  local function objectFromArrayElement(elem)
    local obj, err = safe.getArrayElement(elem)
    if err == nil and safe.isValidObject(obj) then return obj, nil end
    if safe.isValidObject(elem) then return elem, nil end
    return nil, err
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

  probes[#probes + 1] = mk('Identity.VisiblePlayers.Sample', 'identity', 'multiplayer-roster-read', 'visiblePlayers', function(ctx)
    local cap = 8
    local gameState, sourceClass, gameStateErr = getGameState()
    if gameStateErr and not safe.isValidObject(gameState) then return 'lua_error', nil, nil, gameStateErr end
    if not safe.isValidObject(gameState) then
      return 'nil', 'identity_roster', 'visiblePlayerCount=0 sourcePath=' .. tostring(sourceClass) .. '.PlayerArray rawIdentityEvidence=false', nil, {
        sourceScope = 'runtime_roster',
        sourcePath = tostring(sourceClass) .. '.PlayerArray',
        localPlayerPresent = safe.isValidObject(ctx.cache.IdentityLocalPlayerState),
        visiblePlayerCount = 0,
        visiblePlayerCap = cap,
        displayNameFingerprints = {},
        stableIdFingerprints = {},
        hostClientRoleConsistent = ctx.role ~= 'unknown',
        identityRawRedacted = ctx.config.allowRawIdentityEvidence ~= true,
        rawIdentityEvidence = ctx.config.allowRawIdentityEvidence == true,
        localNotes = 'GameState unavailable; no roster traversal performed'
      }
    end

    local playerArray, playerArrayErr = safe.getProperty(gameState, 'PlayerArray')
    if playerArrayErr then return 'lua_error', nil, nil, playerArrayErr end
    if type(playerArray) ~= 'table' then
      return 'nil', 'identity_roster', 'visiblePlayerCount=0 sourcePath=' .. tostring(sourceClass) .. '.PlayerArray rawIdentityEvidence=false', nil, {
        sourceScope = 'runtime_roster',
        sourcePath = tostring(sourceClass) .. '.PlayerArray',
        localPlayerPresent = safe.isValidObject(ctx.cache.IdentityLocalPlayerState),
        visiblePlayerCount = 0,
        visiblePlayerCap = cap,
        displayNameFingerprints = {},
        stableIdFingerprints = {},
        hostClientRoleConsistent = ctx.role ~= 'unknown',
        identityRawRedacted = ctx.config.allowRawIdentityEvidence ~= true,
        rawIdentityEvidence = ctx.config.allowRawIdentityEvidence == true,
        localNotes = 'PlayerArray was not exposed as a Lua table; no recursive traversal performed'
      }
    end

    local samples = {}
    local rawNames = {}
    local rawIds = {}
    local count = 0
    safe.forEachArrayLimited(playerArray, cap, function(_, elem)
      local playerState = objectFromArrayElement(elem)
      if safe.isValidObject(playerState) then
        local sample = samplePlayerStateIdentity(playerState, ctx.config or {})
        samples[#samples + 1] = sample
        if ctx.config.allowRawIdentityEvidence == true then
          rawNames[#rawNames + 1] = sample.rawDisplayName or ''
          rawIds[#rawIds + 1] = sample.rawStableId or ''
        end
        count = count + 1
      end
    end)

    local summary, display, ids = summarizeIdentitySamples(samples, 'visiblePlayerCount=' .. tostring(count) .. ' cap=' .. tostring(cap) .. ' sourcePath=' .. tostring(sourceClass) .. '.PlayerArray')
    return 'ok', 'identity_roster', summary, nil, {
      sourceScope = 'runtime_roster',
      sourcePath = tostring(sourceClass) .. '.PlayerArray',
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

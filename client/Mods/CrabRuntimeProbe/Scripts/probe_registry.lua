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

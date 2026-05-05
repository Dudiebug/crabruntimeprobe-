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
    accessKind = opts.accessKind or step
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

  local function summarizeIdentityOrDefault(obj, fallback)
    local summary, summaryErr, identity = safe.summarizeObjectIdentity(obj)
    return summary or fallback, summaryErr, identity
  end

  local function readScalar(value)
    if value == nil then return 'nil' end
    return 'ok', type(value), tostring(value)
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
    return 'ok', 'object', 'CrabHC found'
  end, {
    symbol = 'CrabHC',
    owner = 'Runtime',
    member = 'CrabHC',
    accessMethod = 'FindFirstOf',
    accessKind = 'findFirst'
  })

  probes[#probes + 1] = mk('CrabHC.IsValid', 'health', 'health-baseline-read', 'isValid', function(ctx)
    local ok = safe.isValidObject(ctx.cache.CrabHC)
    return ok and 'ok' or 'nil', 'boolean', tostring(ok)
  end, {
    symbol = 'CrabHC',
    owner = 'CrabHC',
    member = 'IsValid',
    accessMethod = 'IsValid',
    accessKind = 'isValid'
  })

  probes[#probes + 1] = mk('CrabHC.GetFullName', 'health', 'health-baseline-read', 'fullname', function(ctx)
    local v, err = safe.getFullName(ctx.cache.CrabHC)
    if err then return 'lua_error', nil, err end
    if not v then return 'nil' end
    return 'ok', 'string', v
  end, {
    symbol = 'CrabHC',
    owner = 'CrabHC',
    member = 'GetFullName',
    accessMethod = 'GetFullName',
    accessKind = 'getFullName'
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
    accessKind = 'getProperty'
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
      accessKind = 'health'
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
    accessKind = 'health'
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
    accessKind = 'getProperty'
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
      accessKind = 'health'
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
      accessKind = 'health'
    })
  end

  return probes
end

return registry

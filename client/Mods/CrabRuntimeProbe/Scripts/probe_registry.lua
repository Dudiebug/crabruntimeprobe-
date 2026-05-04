local registry = {}

local function mk(id, category, setName, step, fn, opts)
  return {
    id = id,
    category = category,
    set = setName,
    step = step,
    run = fn,
    requires = opts or {}
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

  probes[#probes + 1] = mk('FindFirstOf.CrabPC', 'core', 'shallow-core', 'findFirst', function(ctx)
    local obj, err = safe.findFirst('CrabPC')
    ctx.cache.CrabPC = obj
    if err then return 'lua_error', nil, err end
    if obj == nil then return 'nil' end
    return 'ok', 'object', 'CrabPC found'
  end)

  probes[#probes + 1] = mk('CrabPC.IsValid', 'core', 'shallow-core', 'isValid', function(ctx)
    local ok = safe.isValidObject(ctx.cache.CrabPC)
    return ok and 'ok' or 'nil', 'boolean', tostring(ok)
  end)

  probes[#probes + 1] = mk('CrabPC.GetFullName', 'core', 'shallow-core', 'fullname', function(ctx)
    local v, err = safe.getFullName(ctx.cache.CrabPC)
    if err then return 'lua_error', nil, err end
    if not v then return 'nil' end
    return 'ok', 'string', v
  end)

  probes[#probes + 1] = mk('CrabPC.GetPropertyValue.PlayerState', 'core', 'shallow-core', 'playerstate', function(ctx)
    local v, err = safe.getProperty(ctx.cache.CrabPC, 'PlayerState')
    ctx.cache.CrabPS = v
    if err then return 'lua_error', nil, err end
    if not v then return 'nil' end
    return 'ok', 'object', 'PlayerState obtained'
  end)

  probes[#probes + 1] = mk('CrabPS.IsValid', 'core', 'shallow-core', 'isValid', function(ctx)
    local ok = safe.isValidObject(ctx.cache.CrabPS)
    return ok and 'ok' or 'nil', 'boolean', tostring(ok)
  end)

  probes[#probes + 1] = mk('CrabPS.GetFullName', 'core', 'shallow-core', 'fullname', function(ctx)
    local v, err = safe.getFullName(ctx.cache.CrabPS)
    if err then return 'lua_error', nil, err end
    if not v then return 'nil' end
    return 'ok', 'string', v
  end)

  local equipmentFields = { 'WeaponDA', 'AbilityDA', 'MeleeDA' }
  for _, field in ipairs(equipmentFields) do
    probes[#probes + 1] = mk('CrabPS.GetPropertyValue.' .. field, 'equipment', 'equipment-property-read', 'property', function(ctx)
      local crabPs, crabPsErr = getCrabPlayerState(ctx)
      if crabPsErr then return 'lua_error', nil, crabPsErr end
      local v, err = safe.getProperty(crabPs, field)
      ctx.cache[field] = v
      if err then return 'lua_error', nil, err end
      if not v then return 'nil' end
      local summary, summaryErr = safe.summarizeObjectIdentity(v)
      return 'ok', 'object', summary or (field .. ' via property'), summaryErr
    end)
    probes[#probes + 1] = mk('CrabPS.DirectField.' .. field, 'equipment', 'equipment-direct-field-read', 'direct', function(ctx)
      local crabPs, crabPsErr = getCrabPlayerState(ctx)
      if crabPsErr then return 'lua_error', nil, crabPsErr end
      local v, err = safe.getDirectField(crabPs, field)
      if err then return 'lua_error', nil, err end
      if not v then return 'nil' end
      local summary, summaryErr = safe.summarizeObjectIdentity(v)
      return 'ok', 'object', summary or (field .. ' via direct field'), summaryErr
    end)
  end

  return probes
end

return registry

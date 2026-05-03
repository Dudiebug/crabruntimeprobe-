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

  local da = { WeaponDA = 'equipment-read', AbilityDA = 'equipment-read', MeleeDA = 'equipment-read' }
  for field, setName in pairs(da) do
    probes[#probes + 1] = mk('CrabPS.GetPropertyValue.' .. field, 'equipment', setName, 'property', function(ctx)
      local v, err = safe.getProperty(ctx.cache.CrabPS, field)
      ctx.cache[field] = v
      if err then return 'lua_error', nil, err end
      if not v then return 'nil' end
      return 'ok', 'object', field .. ' via property'
    end)
    probes[#probes + 1] = mk('CrabPS.DirectField.' .. field, 'equipment', setName, 'direct', function(ctx)
      local v, err = safe.getDirectField(ctx.cache.CrabPS, field)
      if err then return 'lua_error', nil, err end
      if not v then return 'nil' end
      return 'ok', 'object', field .. ' via direct field'
    end)
  end

  return probes
end

return registry

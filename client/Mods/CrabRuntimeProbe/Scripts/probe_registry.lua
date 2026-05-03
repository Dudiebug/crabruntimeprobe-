local registry = {}

local function mk(id, set, category, gate)
  return { id = id, set = set, category = category, gate = gate }
end

registry.probes = {
  mk('FindFirstOf.CrabPC', 'shallow-core', 'core'),
  mk('CrabPC.IsValid', 'shallow-core', 'core'),
  mk('CrabPC.GetFullName', 'shallow-core', 'core'),
  mk('CrabPC.GetPropertyValue.PlayerState', 'shallow-core', 'core'),
  mk('CrabPS.IsValid', 'shallow-core', 'core'),
  mk('CrabPS.GetFullName', 'shallow-core', 'core'),

  mk('CrabPS.GetPropertyValue.WeaponDA', 'equipment-read', 'equipment'),
  mk('CrabPS.DirectField.WeaponDA', 'equipment-read', 'equipment'),
  mk('CrabPS.GetPropertyValue.AbilityDA', 'equipment-read', 'equipment'),
  mk('CrabPS.DirectField.AbilityDA', 'equipment-read', 'equipment'),
  mk('CrabPS.GetPropertyValue.MeleeDA', 'equipment-read', 'equipment'),
  mk('CrabPS.DirectField.MeleeDA', 'equipment-read', 'equipment'),
  mk('WeaponDA.GetName', 'equipment-read', 'equipment'),
  mk('WeaponDA.GetFullName', 'equipment-read', 'equipment'),

  mk('InventoryArray.Deep', 'inventory-array-deep', 'inventory', 'allowDeepArrayProbes'),
  mk('InventoryInfo.Deep', 'inventory-info', 'inventory', 'allowInventoryInfoProbes'),
  mk('Health.Read', 'health-read', 'health', 'allowHealthProbes'),
  mk('RPC.DryRun.Stub', 'rpc-dryrun', 'rpc', 'allowRpcProbes'),
}

function registry.forSet(set)
  local out = {}
  for _, p in ipairs(registry.probes) do
    if p.set == set or set == 'all-readonly' then out[#out + 1] = p end
  end
  return out
end

return registry

local registry = {}

registry.sets = {
  ['shallow-core'] = {
    'FindFirstOf.CrabPC', 'CrabPC.IsValid', 'CrabPC.GetFullName', 'CrabPC.GetPropertyValue.PlayerState', 'CrabPS.IsValid', 'CrabPS.GetFullName'
  },
  ['equipment-read'] = {
    'CrabPS.GetPropertyValue.WeaponDA','CrabPS.DirectField.WeaponDA','CrabPS.GetPropertyValue.AbilityDA','CrabPS.DirectField.AbilityDA','CrabPS.GetPropertyValue.MeleeDA','CrabPS.DirectField.MeleeDA','WeaponDA.GetName','WeaponDA.GetFullName'
  },
  ['inventory-array-shallow'] = {},
  ['inventory-array-deep'] = {},
  ['inventory-info'] = {},
  ['health-read'] = {},
  ['rpc-dryrun'] = {},
  ['all-readonly'] = {}
}

local arrays = {
  {'WeaponMods','WeaponModDA'}, {'AbilityMods','AbilityModDA'}, {'MeleeMods','MeleeModDA'}, {'Perks','PerkDA'}, {'Relics','RelicDA'}
}
for _, a in ipairs(arrays) do
  local n = a[1]
  registry.sets['inventory-array-shallow'][#registry.sets['inventory-array-shallow']+1] = 'CrabPS.GetPropertyValue.' .. n
  registry.sets['inventory-array-shallow'][#registry.sets['inventory-array-shallow']+1] = n .. '.ForEach.CountOnly'
  registry.sets['inventory-array-shallow'][#registry.sets['inventory-array-shallow']+1] = n .. '.ForEach.FirstElementSeen'
  registry.sets['inventory-array-deep'][#registry.sets['inventory-array-deep']+1] = n .. '.FirstElement.Get'
end

registry.sets['all-readonly'] = {}
for _, setName in ipairs({'shallow-core','equipment-read','inventory-array-shallow'}) do
  for _, id in ipairs(registry.sets[setName]) do table.insert(registry.sets['all-readonly'], id) end
end

registry.rpcDryRun = {'ServerEquipInventory','ServerSetWeaponDA','ServerSetAbilityDA','ServerSetMeleeDA','ServerIncrementNumInventorySlots','OnRep_Inventory','OnRep_Crystals'}

return registry

# Inventory Runtime Notes

Use this file to track validated safe/unsafe inventory access operations by context.

## Local Inventory Array Phases

- `local-inventory-array-shape-confirm` proves only local `CrabPS.WeaponMods`, `AbilityMods`, `MeleeMods`, `Perks`, and `Relics` property visibility and value shape. Latest evidence showed userdata wrappers and did not count, traverse, or dereference elements.
- `local-inventory-userdata-introspection` is the next read-only metadata phase for those userdata wrappers. It may record `type`, safe redacted `tostring`, guarded `getmetatable` metadata, and a guarded length-operator result if available.
- Any length-operator result is metadata-only. It is not proof of count traversal, element traversal, item contents, or item sync.
- Item data asset fields, slot contents, `InventoryInfo`, and Enhancements remain untested. Writes, RPCs, HUD hooks, and deep arrays remain disabled for these phases.

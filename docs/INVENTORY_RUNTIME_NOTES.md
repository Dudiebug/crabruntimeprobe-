# Inventory Runtime Notes

Use this file to track validated safe/unsafe inventory access operations by context.

## Local Inventory Array Phases

- `local-inventory-array-shape-confirm` proves only local `CrabPS.WeaponMods`, `AbilityMods`, `MeleeMods`, `Perks`, and `Relics` property visibility and value shape. Latest evidence showed userdata wrappers and did not count, traverse, or dereference elements.
- `local-inventory-userdata-introspection` is the next read-only metadata phase for those userdata wrappers. It may record `type`, safe redacted `tostring`, guarded `getmetatable` metadata, and a guarded length-operator result if available.
- `inventory-array-count-read` is the next smallest proof phase. It reads only the five local PlayerState inventory properties with `GetPropertyValue` and attempts only protected wrapper count metadata. It must not call array getters, traverse arrays, dereference elements, read item DataAssets, read `InventoryInfo`, or read Enhancements.
- Any count or length-operator result is metadata-only. It is not proof of traversal, element traversal, item contents, item sync, item DataAsset safety, `InventoryInfo`, or Enhancements.
- Item data asset fields, slot contents, `InventoryInfo`, and Enhancements remain untested. Writes, RPCs, HUD hooks, and deep arrays remain disabled for these phases.

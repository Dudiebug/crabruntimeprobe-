local registry = {}

local function p(id, category, fn, opts)
  opts = opts or {}
  return {
    id = id,
    name = id,
    category = category,
    fn = fn,
    requires = opts.requires,
    set = opts.set,
  }
end

registry.sets = {
  ["shallow-core"] = true,
  ["equipment-read"] = true,
  ["inventory-array-shallow"] = true,
  ["inventory-array-deep"] = true,
  ["inventory-info"] = true,
  ["health-read"] = true,
  ["rpc-dryrun"] = true,
  ["all-readonly"] = true,
}

function registry.build(safe)
  local probes = {
    p("FindFirstOf.CrabPC", "core", function(ctx) return safe.findFirst("CrabPC") end, {set="shallow-core"}),
    p("CrabPC.IsValid", "core", function(ctx) return safe.isValidObject(ctx.crabPc) end, {set="shallow-core"}),
    p("CrabPC.GetFullName", "core", function(ctx) return safe.getFullName(ctx.crabPc) end, {set="shallow-core"}),
    p("CrabPC.GetPropertyValue.PlayerState", "core", function(ctx) return safe.getProperty(ctx.crabPc, "PlayerState") end, {set="shallow-core"}),
    p("CrabPS.IsValid", "core", function(ctx) return safe.isValidObject(ctx.crabPs) end, {set="shallow-core"}),
    p("CrabPS.GetFullName", "core", function(ctx) return safe.getFullName(ctx.crabPs) end, {set="shallow-core"}),
    p("CrabPS.GetPropertyValue.WeaponDA", "equipment", function(ctx) return safe.getProperty(ctx.crabPs, "WeaponDA") end, {set="equipment-read"}),
    p("CrabPS.DirectField.WeaponDA", "equipment", function(ctx) return safe.getDirectField(ctx.crabPs, "WeaponDA") end, {set="equipment-read"}),
    p("CrabPS.GetPropertyValue.AbilityDA", "equipment", function(ctx) return safe.getProperty(ctx.crabPs, "AbilityDA") end, {set="equipment-read"}),
    p("CrabPS.DirectField.AbilityDA", "equipment", function(ctx) return safe.getDirectField(ctx.crabPs, "AbilityDA") end, {set="equipment-read"}),
  }
  return probes
end

return registry

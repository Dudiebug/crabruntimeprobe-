local M = {}

function M.detect(safe, state)
  local ctx = 'unknown'
  local role = 'unknown'
  if state.traveling then ctx = 'traveling' end
  local pc = safe.findFirst('CrabPC')
  if not safe.isValidObject(pc) then
    if state.tick < 120 then ctx = 'menu' end
    return ctx, role
  end
  local ps = safe.getProperty(pc, 'PlayerState')
  if safe.isValidObject(ps) then
    ctx = 'lobby'
    role = 'maybe-player'
  end
  if state.dead then ctx = 'dead-or-respawning' end
  return ctx, role
end

return M

local M = {}

function M.detect(safe, state)
  local context = "unknown"
  local role = "unknown"

  local crabPc = safe.findFirst("CrabPC")
  local hasPc = safe.isValidObject(crabPc)
  local playerState = nil
  local hasPs = false

  if hasPc then
    playerState = safe.getProperty(crabPc, "PlayerState")
    hasPs = safe.isValidObject(playerState)
  end

  if not hasPc and (state.tick or 0) < 120 then
    context = "menu"
  elseif hasPc and not hasPs then
    context = "lobby"
  elseif hasPc and hasPs then
    context = "solo"
    role = "solo-or-host"
  else
    context = "unknown"
  end

  if state.traveling then context = "traveling" end
  if state.deadOrRespawning then context = "dead-or-respawning" end

  return {
    context = context,
    role = role,
    hasPc = hasPc,
    hasPs = hasPs,
  }
end

return M

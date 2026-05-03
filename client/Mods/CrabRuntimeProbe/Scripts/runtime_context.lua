local M = { last = 'unknown', stableTicks = 0 }

function M.detect(state)
  local ctx = 'unknown'
  if state.traveling then ctx = 'traveling'
  elseif state.inMenu then ctx = 'menu'
  elseif state.inLobby then ctx = 'lobby'
  elseif state.isSolo then ctx = 'solo'
  elseif state.isHost then ctx = 'host'
  elseif state.isJoined then ctx = 'joined-client'
  elseif state.dead then ctx = 'dead-or-respawning'
  end
  if ctx == M.last then M.stableTicks = M.stableTicks + 1 else M.stableTicks = 0 end
  M.last = ctx
  if ctx == 'unknown' then return 'unknown', M.stableTicks end
  if M.stableTicks < (state.contextStableTicksRequired or 10) then return 'unstable', M.stableTicks end
  return ctx, M.stableTicks
end

return M

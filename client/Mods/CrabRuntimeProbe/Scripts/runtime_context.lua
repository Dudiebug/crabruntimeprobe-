local context = {}

function context.detect(safe, state)
  if state.traveling then return 'traveling' end
  if state.unstableTicks and state.unstableTicks > 0 then return 'unstable' end
  if state.deadOrRespawning then return 'dead-or-respawning' end
  if state.inMenu then return 'menu' end
  if state.inLobby then return 'lobby' end
  if state.inSolo then return 'solo' end
  if state.isHost then return 'host' end
  if state.isJoinedClient then return 'joined-client' end
  return 'unknown'
end

function context.detectRole(state)
  if state.isHost then return 'host' end
  if state.isJoinedClient then return 'joined-client' end
  if state.inSolo then return 'solo' end
  return 'unknown'
end

return context

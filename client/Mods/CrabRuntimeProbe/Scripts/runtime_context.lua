local context = {}

local function addError(errors, err)
  if err and err ~= '' then
    errors[#errors + 1] = err
  end
end

function context.snapshot(safe, state)
  local facts = {
    crabPcExists = false,
    crabPcValid = false,
    playerStateExists = false,
    playerStateValid = false,
    context = 'unknown',
    role = 'unknown',
    result = 'unknown',
    error = ''
  }
  local errors = {}

  local crabPc, findErr = safe.findFirst('CrabPC')
  addError(errors, findErr)
  facts.crabPcExists = crabPc ~= nil
  facts.crabPcValid = safe.isValidObject(crabPc)

  if facts.crabPcValid then
    local playerState, psErr = safe.getProperty(crabPc, 'PlayerState')
    addError(errors, psErr)
    facts.playerStateExists = playerState ~= nil
    facts.playerStateValid = safe.isValidObject(playerState)
  end

  if state.traveling then
    facts.context = 'traveling'
  elseif state.unstableTicks and state.unstableTicks > 0 then
    facts.context = 'unstable'
  elseif state.deadOrRespawning then
    facts.context = 'dead-or-respawning'
  elseif facts.crabPcValid and facts.playerStateValid then
    facts.context = 'solo'
    facts.role = 'solo-or-host'
  elseif facts.crabPcValid then
    facts.context = 'lobby'
  elseif (state.tick or 0) < 120 then
    facts.context = 'menu'
  else
    facts.context = 'unknown'
  end

  if #errors > 0 then
    facts.result = 'lua_error'
    facts.error = table.concat(errors, ' | ')
  elseif facts.crabPcExists or facts.playerStateExists then
    facts.result = 'ok'
  elseif facts.context == 'unknown' then
    facts.result = 'unknown'
  else
    facts.result = 'nil'
  end

  return facts
end

function context.detect(safe, state)
  return context.snapshot(safe, state).context
end

function context.detectRole(state)
  if state.isHost then return 'host' end
  if state.isJoinedClient then return 'joined-client' end
  if state.inSolo then return 'solo' end
  return 'unknown'
end

return context

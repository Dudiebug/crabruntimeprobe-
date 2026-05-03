local M = {}

function M.shouldRunProbe(config, probeId, context)
  if probeId:find('FirstElement.Get') and not config.allowDeepArrayProbes then return false, 'unsafe_disabled' end
  if context == 'joined-client' and not config.allowJoinedClientDeepProbes then return false, 'skipped_context' end
  return true, 'ok'
end

return M

local crpLog = require('crp_log')
local json = require('json')

local evidenceWriter = {}

local function utcNow()
  return os.date('!%Y-%m-%dT%H:%M:%SZ')
end

local function appendLine(path, line)
  local f = io.open(path, 'a')
  if f then
    f:write(line .. '\n')
    f:close()
    return true
  end
  return false
end

local function writeFile(path, text)
  local f = io.open(path, 'w')
  if f then
    f:write(text)
    f:close()
    return true
  end
  return false
end

local function touchFile(path)
  local f = io.open(path, 'a')
  if f then
    f:close()
    return true
  end
  return false
end

local function tryCreateDirectory(path)
  if type(os.execute) ~= 'function' then return end
  pcall(function()
    os.execute('if not exist "' .. path .. '" mkdir "' .. path .. '"')
  end)
end

local function safetyGates(config)
  return {
    allowHudTickHook = config.allowHudTickHook == true,
    allowDeepArrayProbes = config.allowDeepArrayProbes == true,
    allowInventoryInfoProbes = config.allowInventoryInfoProbes == true,
    allowHealthProbes = config.allowHealthProbes == true,
    allowIdentityProbes = config.allowIdentityProbes == true,
    allowRawIdentityEvidence = config.allowRawIdentityEvidence == true,
    allowResourceVisibilityProbes = config.allowResourceVisibilityProbes == true,
    allowCrystalsReadProbes = config.allowCrystalsReadProbes == true,
    allowInventoryArrayShallowProbes = config.allowInventoryArrayShallowProbes == true,
    allowInventoryArrayShapeConfirmProbes = config.allowInventoryArrayShapeConfirmProbes == true,
    allowInventoryUserdataIntrospectionProbes = config.allowInventoryUserdataIntrospectionProbes == true,
    allowWriteProbes = config.allowWriteProbes == true,
    allowRpcProbes = config.allowRpcProbes == true,
    allowJoinedClientDeepProbes = config.allowJoinedClientDeepProbes == true,
    allowUnknownRoleProbes = config.allowUnknownRoleProbes == true
  }
end

local function hasUnsafeGate(config)
  local gates = safetyGates(config)
  for _, value in pairs(gates) do
    if value == true then return true end
  end
  return false
end

local function activeResearchGates(config)
  local gates = safetyGates(config)
  local active = {}
  for _, key in ipairs({
    'allowHudTickHook',
    'allowDeepArrayProbes',
    'allowInventoryInfoProbes',
    'allowHealthProbes',
    'allowIdentityProbes',
    'allowRawIdentityEvidence',
    'allowResourceVisibilityProbes',
    'allowCrystalsReadProbes',
    'allowInventoryArrayShallowProbes',
    'allowInventoryArrayShapeConfirmProbes',
    'allowInventoryUserdataIntrospectionProbes',
    'allowWriteProbes',
    'allowRpcProbes',
    'allowJoinedClientDeepProbes',
    'allowUnknownRoleProbes'
  }) do
    if gates[key] == true then
      active[#active + 1] = key
    end
  end
  return active
end

local function parseBuildInfo(lines)
  local info = {}
  for _, line in ipairs(lines or {}) do
    local k, v = tostring(line):match('^%s*([%w_]+)%s*=%s*(.-)%s*$')
    if k and k ~= 'source_repo_path' then
      info[k] = v
    end
  end
  return info
end

local function configSnapshot(config)
  local snapshot = {}
  for k, v in pairs(config) do
    if type(v) == 'string' or type(v) == 'number' or type(v) == 'boolean' then
      snapshot[k] = v
    end
  end
  return snapshot
end

local function withDefaults(record, sessionId, config)
  record.timestamp = record.timestamp or utcNow()
  record.sessionId = sessionId
  record.game = 'Crab Champions'
  record.mod = 'CrabRuntimeProbe'
  record.schemaVersion = 1
  record.mode = record.mode or tostring(config.mode)
  record.tickDriver = record.tickDriver or tostring(config.tickDriver)
  record.safetyGates = record.safetyGates or safetyGates(config)
  return record
end

function evidenceWriter.new(sessionId, config)
  local o = {
    sessionId = sessionId,
    config = config,
    resultDir = 'Mods/CrabRuntimeProbe/Scripts/results',
    evidencePath = 'Mods/CrabRuntimeProbe/Scripts/results/access_evidence_' .. sessionId .. '.jsonl',
    fallbackEvidencePath = 'Mods/CrabRuntimeProbe/Scripts/access_evidence_' .. sessionId .. '.jsonl',
    manifestPath = 'Mods/CrabRuntimeProbe/Scripts/results/session_manifest_' .. sessionId .. '.json',
    fallbackManifestPath = 'Mods/CrabRuntimeProbe/Scripts/session_manifest_' .. sessionId .. '.json',
    triedCreateResultDir = false,
    warnedFallback = false,
    warnedFailure = false
  }

  function o:ensureResultDir()
    if not self.triedCreateResultDir then
      tryCreateDirectory(self.resultDir)
      self.triedCreateResultDir = true
    end
  end

  function o:writeEvidence(record)
    if self.config.writeJsonlResults == false then return true end
    self:ensureResultDir()
    local line = json.encode(withDefaults(record, self.sessionId, self.config))
    if not appendLine(self.evidencePath, line) then
      if appendLine(self.fallbackEvidencePath, line) then
        if not self.warnedFallback then
          crpLog.line('[CrabRuntimeProbe] primary evidence path unavailable; using fallback')
          self.warnedFallback = true
        end
        return true
      end
      if not self.warnedFailure then
        crpLog.line('[CrabRuntimeProbe] ERROR: evidence write failed for primary and fallback')
        self.warnedFailure = true
      end
      return false
    end
    return true
  end

  function o:writeSessionManifest(buildInfoLines)
    self:ensureResultDir()
    if self.config.writeJsonlResults ~= false and not touchFile(self.evidencePath) then
      touchFile(self.fallbackEvidencePath)
    end
    local manifest = {
      sessionId = self.sessionId,
      startedAt = utcNow(),
      game = 'Crab Champions',
      mod = 'CrabRuntimeProbe',
      schemaVersion = 1,
      runtimeProbeVersion = 'unknown',
      buildInfo = parseBuildInfo(buildInfoLines),
      config = configSnapshot(self.config),
      probeSet = tostring(self.config.probeSet),
      tickDriver = tostring(self.config.tickDriver),
      safetyGates = safetyGates(self.config),
      activeResearchGates = activeResearchGates(self.config),
      warning = hasUnsafeGate(self.config) and ('research gates enabled: ' .. table.concat(activeResearchGates(self.config), ', ')) or ''
    }
    local text = json.encode(manifest)
    if writeFile(self.manifestPath, text) then return true end
    return writeFile(self.fallbackManifestPath, text)
  end

  return o
end

return evidenceWriter

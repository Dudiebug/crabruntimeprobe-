local json = require("json")
local writer = {}

local function nowIso()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

function writer.new(sessionId, config)
  local path = "Mods/CrabRuntimeProbe/Scripts/results/probe_results_" .. sessionId .. ".jsonl"
  local fallback = "Mods/CrabRuntimeProbe/Scripts/probe_results_" .. sessionId .. ".jsonl"
  return {
    sessionId = sessionId,
    path = path,
    fallback = fallback,
    config = config,
  }
end

function writer.append(w, row)
  row.timestamp = row.timestamp or nowIso()
  row.sessionId = row.sessionId or w.sessionId
  local line = json.encode(row)
  local ok = pcall(function() io.writefile(w.path, line .. "\n", true) end)
  if not ok then pcall(function() io.writefile(w.fallback, line .. "\n", true) end) end
end

return writer

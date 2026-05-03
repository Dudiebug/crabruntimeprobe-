local runtime_context = require("runtime_context")

local runner = {}

local function breadcrumb(config, msg)
  if config.debugBreadcrumbs then
    print("[CrabRuntimeProbe] breadcrumb: " .. msg)
  end
end

function runner.new(config, safe, registry, writer)
  return {
    config = config,
    safe = safe,
    probes = registry.build(safe),
    writer = writer,
    tick = 0,
    completed = 0,
    stableTicks = 0,
  }
end

local function classify(v)
  if v == nil then return "nil", "nil" end
  local t = type(v)
  if t == "boolean" or t == "number" or t == "string" then return "ok", t end
  return "ok", "object"
end

function runner.step(r)
  r.tick = r.tick + 1
  if r.tick < r.config.startupWarmupTicks then return end

  local contextInfo = runtime_context.detect(r.safe, { tick = r.tick })
  if contextInfo.context == "unstable" then
    r.stableTicks = 0
  else
    r.stableTicks = r.stableTicks + 1
  end

  if r.stableTicks < r.config.contextStableTicksRequired then return end
  if r.tick % r.config.probeIntervalTicks ~= 0 then return end
  if r.completed >= r.config.maxProbesPerSession then return end

  local index = r.completed + 1
  local probe = r.probes[index]
  if not probe then return end

  local ctx = {
    crabPc = r.safe.findFirst("CrabPC"),
    crabPs = nil,
  }
  ctx.crabPs = r.safe.getProperty(ctx.crabPc, "PlayerState")

  breadcrumb(r.config, probe.id .. " enter")
  local start = os.clock()
  local ok, val = pcall(function() return probe.fn(ctx) end)
  local dur = math.floor((os.clock() - start) * 1000)

  local result, kind, err = "unknown", "unknown", ""
  if ok then
    result, kind = classify(val)
  else
    result = "lua_error"
    err = tostring(val)
  end

  writer.append(r.writer, {
    tick = r.tick,
    mode = r.config.mode,
    probeId = probe.id,
    probeName = probe.name,
    category = probe.category,
    context = contextInfo.context,
    role = contextInfo.role,
    lifecycleState = (r.stableTicks >= r.config.contextStableTicksRequired) and "stable" or "unstable",
    step = "run",
    result = result,
    valueKind = kind,
    valueSummary = tostring(val),
    error = err,
    durationMs = dur,
  })
  breadcrumb(r.config, probe.id .. " exit")
  r.completed = r.completed + 1
end

return runner

local json = {}

local function esc(s)
  s = s:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t')
  return '"' .. s .. '"'
end

local function encode(v)
  local t = type(v)
  if t == "nil" then return "null" end
  if t == "boolean" then return v and "true" or "false" end
  if t == "number" then return tostring(v) end
  if t == "string" then return esc(v) end
  if t == "table" then
    local isArray = true
    local max = 0
    for k, _ in pairs(v) do
      if type(k) ~= "number" then isArray = false break end
      if k > max then max = k end
    end
    local out = {}
    if isArray then
      for i = 1, max do out[#out + 1] = encode(v[i]) end
      return "[" .. table.concat(out, ",") .. "]"
    end
    for k, val in pairs(v) do out[#out + 1] = esc(tostring(k)) .. ":" .. encode(val) end
    return "{" .. table.concat(out, ",") .. "}"
  end
  return esc("<unsupported>")
end

function json.encode(v)
  return encode(v)
end

return json

local json = {}

local function esc(s)
  s = tostring(s)
  s = s:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r')
  return '"' .. s .. '"'
end

local function encode(v)
  local t = type(v)
  if t == 'nil' then return 'null' end
  if t == 'boolean' or t == 'number' then return tostring(v) end
  if t == 'string' then return esc(v) end
  if t == 'table' then
    local isArr = true
    local n = 0
    for k, _ in pairs(v) do
      if type(k) ~= 'number' then isArr = false break end
      if k > n then n = k end
    end
    local out = {}
    if isArr then
      for i = 1, n do out[#out + 1] = encode(v[i]) end
      return '[' .. table.concat(out, ',') .. ']'
    end
    for k, val in pairs(v) do
      out[#out + 1] = esc(k) .. ':' .. encode(val)
    end
    return '{' .. table.concat(out, ',') .. '}'
  end
  return esc('<' .. t .. '>')
end

function json.encode(v) return encode(v) end
return json

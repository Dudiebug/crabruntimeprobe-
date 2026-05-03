local json = {}

local function esc(s)
  s = tostring(s)
  s = s:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t')
  return '"' .. s .. '"'
end

local function encode(v)
  local t = type(v)
  if t == 'nil' then return 'null' end
  if t == 'boolean' or t == 'number' then return tostring(v) end
  if t == 'string' then return esc(v) end
  if t == 'table' then
    local isArray = (#v > 0)
    local out = {}
    if isArray then
      for i = 1, #v do out[#out + 1] = encode(v[i]) end
      return '[' .. table.concat(out, ',') .. ']'
    else
      for k, vv in pairs(v) do out[#out + 1] = esc(k) .. ':' .. encode(vv) end
      return '{' .. table.concat(out, ',') .. '}'
    end
  end
  return esc('<' .. t .. '>')
end

function json.encode(v) return encode(v) end
return json

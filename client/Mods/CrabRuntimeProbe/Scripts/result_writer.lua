local json = require('json')
local M = {}

local function append(path, line)
  local f = io.open(path, 'a')
  if not f then return false end
  f:write(line .. '\n')
  f:close()
  return true
end

function M.writeResult(path, obj)
  return append(path, json.encode(obj))
end

function M.breadcrumb(path, text)
  local ts = os.date('!%Y-%m-%dT%H:%M:%SZ')
  return append(path, ts .. ' | ' .. text)
end

return M

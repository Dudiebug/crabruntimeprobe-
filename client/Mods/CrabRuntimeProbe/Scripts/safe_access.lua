local safe = {}

local function try(fn)
  local ok, res = pcall(fn)
  if ok then return true, res end
  return false, res
end

function safe.isValidObject(obj)
  if obj == nil then return false end
  local ok, res = try(function() return obj:IsValid() end)
  return ok and res == true
end

function safe.findFirst(className)
  local ok, res = try(function() return FindFirstOf(className) end)
  if ok then return res end
  return nil
end

function safe.findAll(className)
  local ok, res = try(function() return FindAllOf(className) end)
  if ok then return res end
  return nil
end

function safe.getProperty(obj, propName)
  if not safe.isValidObject(obj) then return nil end
  local ok, res = try(function() return obj:GetPropertyValue(propName) end)
  if ok then return res end
  return nil
end

function safe.getDirectField(obj, fieldName)
  if not safe.isValidObject(obj) then return nil end
  local ok, res = try(function() return obj[fieldName] end)
  if ok then return res end
  return nil
end

function safe.getFullName(obj)
  if not safe.isValidObject(obj) then return nil end
  local ok, res = try(function() return obj:GetFullName() end)
  return ok and res or nil
end

function safe.getName(obj)
  if not safe.isValidObject(obj) then return nil end
  local ok, res = try(function() return obj:GetName() end)
  return ok and res or nil
end

function safe.getArray(obj, propName)
  return safe.getProperty(obj, propName)
end

function safe.forEachArrayLimited(arr, maxElements, callback)
  if arr == nil then return 0 end
  local n = 0
  for i, v in ipairs(arr) do
    n = n + 1
    callback(i, v)
    if n >= maxElements then break end
  end
  return n
end

function safe.getArrayElement(elem)
  local ok, res = try(function() return elem:get() end)
  return ok and res or nil
end

return safe

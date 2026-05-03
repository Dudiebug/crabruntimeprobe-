local safe = {}

local function try(fn)
  local ok, res = pcall(fn)
  if ok then return true, res end
  return false, res
end

function safe.isValidObject(obj)
  if obj == nil then return false end
  local ok, v = try(function() return obj:IsValid() end)
  return ok and v == true
end

function safe.findFirst(className)
  local ok, v = try(function() return FindFirstOf(className) end)
  if not ok then return nil, v end
  return v, nil
end

function safe.findAll(className)
  local ok, v = try(function() return FindAllOf(className) end)
  if not ok then return nil, v end
  return v, nil
end

function safe.getProperty(obj, propName)
  return try(function() return obj:GetPropertyValue(propName) end)
end

function safe.getDirectField(obj, fieldName)
  return try(function() return obj[fieldName] end)
end

function safe.getFullName(obj)
  return try(function() return obj:GetFullName() end)
end

function safe.getName(obj)
  return try(function() return obj:GetName() end)
end

function safe.getArray(obj, propName)
  return safe.getProperty(obj, propName)
end

function safe.forEachArrayLimited(arr, maxElements, callback)
  if arr == nil then return 0 end
  local count = 0
  for _, elem in pairs(arr) do
    count = count + 1
    callback(elem, count)
    if count >= maxElements then break end
  end
  return count
end

function safe.getArrayElement(elem)
  return try(function() return elem:get() end)
end

return safe

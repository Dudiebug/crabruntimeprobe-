local safe = {}

function safe.isValidObject(obj)
  if obj == nil then return false end
  if obj.IsValid == nil then return true end
  local ok, v = pcall(function() return obj:IsValid() end)
  return ok and v == true
end

function safe.findFirst(className)
  local ok, v = pcall(function() return FindFirstOf(className) end)
  if ok then return v end
  return nil
end

function safe.findAll(className)
  local ok, v = pcall(function() return FindAllOf(className) end)
  if ok then return v end
  return nil
end

function safe.getProperty(obj, propName)
  if not obj then return nil end
  local ok, v = pcall(function() return obj:GetPropertyValue(propName) end)
  if ok then return v end
  return nil
end

function safe.getDirectField(obj, fieldName)
  if not obj then return nil end
  local ok, v = pcall(function() return obj[fieldName] end)
  if ok then return v end
  return nil
end

function safe.getFullName(obj)
  if not obj then return nil end
  local ok, v = pcall(function() return obj:GetFullName() end)
  if ok then return v end
  return nil
end

function safe.getName(obj)
  if not obj then return nil end
  local ok, v = pcall(function() return obj:GetName() end)
  if ok then return v end
  return nil
end

function safe.getArray(obj, propName)
  return safe.getProperty(obj, propName)
end

function safe.getArrayElement(elem)
  if elem == nil then return nil end
  local ok, v = pcall(function() return elem:get() end)
  if ok then return v end
  return nil
end

function safe.forEachArrayLimited(arr, maxElements, callback)
  if arr == nil then return 0 end
  local n = 0
  for i, elem in pairs(arr) do
    n = n + 1
    callback(i, elem)
    if n >= maxElements then break end
  end
  return n
end

return safe

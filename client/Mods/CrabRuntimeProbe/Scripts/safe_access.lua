local safe = {}

local function try(fn)
  local ok, val = pcall(fn)
  if not ok then return nil, tostring(val) end
  return val, nil
end

function safe.isValidObject(obj)
  if obj == nil then return false end
  local isValid, err = try(function() return obj:IsValid() end)
  if err then return false end
  return isValid == true
end

function safe.findFirst(className)
  return try(function() return FindFirstOf(className) end)
end

function safe.findAll(className)
  return try(function() return FindAllOf(className) end)
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

function safe.getArrayElement(elem)
  return try(function() return elem:get() end)
end

function safe.forEachArrayLimited(arr, maxElements, callback)
  if type(arr) ~= 'table' then return 0, 'not_array' end
  local count = 0
  for i, elem in ipairs(arr) do
    if i > maxElements then break end
    count = count + 1
    callback(i, elem)
  end
  return count, nil
end

return safe

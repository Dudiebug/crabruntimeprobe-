local safe = {}

local function try(fn)
  local ok, val = pcall(fn)
  if not ok then return nil, tostring(val) end
  return val, nil
end

function safe.isValidObject(obj)
  if obj == nil then return false end
  local method, methodErr = try(function() return obj.IsValid end)
  if methodErr or type(method) ~= 'function' then return false end
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
  if not safe.isValidObject(obj) then return nil, 'invalid_object' end
  return try(function() return obj:GetPropertyValue(propName) end)
end

function safe.getDirectField(obj, fieldName)
  if not safe.isValidObject(obj) then return nil, 'invalid_object' end
  return try(function() return obj[fieldName] end)
end

function safe.getFullName(obj)
  if not safe.isValidObject(obj) then return nil, 'invalid_object' end
  return try(function() return obj:GetFullName() end)
end

function safe.getName(obj)
  if not safe.isValidObject(obj) then return nil, 'invalid_object' end
  return try(function() return obj:GetName() end)
end

function safe.summarizeObjectIdentity(obj)
  if obj == nil then return 'exists=false', nil end

  local parts = { 'exists=true' }
  local errors = {}

  local isValid, isValidErr = try(function()
    if type(obj.IsValid) ~= 'function' then return false end
    return obj:IsValid()
  end)
  if isValidErr then
    parts[#parts + 1] = 'isValid=error'
    errors[#errors + 1] = 'IsValid: ' .. tostring(isValidErr)
    return table.concat(parts, ' '), table.concat(errors, '; ')
  end

  parts[#parts + 1] = 'isValid=' .. tostring(isValid == true)
  if isValid ~= true then
    return table.concat(parts, ' '), nil
  end

  local fullName, fullNameErr = safe.getFullName(obj)
  if fullNameErr then
    parts[#parts + 1] = 'fullName=error'
    errors[#errors + 1] = 'GetFullName: ' .. tostring(fullNameErr)
  elseif fullName ~= nil then
    parts[#parts + 1] = 'fullName=' .. tostring(fullName)
  end

  local name, nameErr = safe.getName(obj)
  if nameErr then
    parts[#parts + 1] = 'name=error'
    errors[#errors + 1] = 'GetName: ' .. tostring(nameErr)
  elseif name ~= nil then
    parts[#parts + 1] = 'name=' .. tostring(name)
  end

  local err = nil
  if #errors > 0 then err = table.concat(errors, '; ') end
  return table.concat(parts, ' '), err
end

function safe.getArray(obj, propName)
  return safe.getProperty(obj, propName)
end

function safe.getArrayElement(elem)
  -- Risky: only use from gated active probes with strict limits.
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

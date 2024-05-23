_utils = {}


_utils.sendError = function (err,target)
  ao.send({Target=target,Action="Error",Error=Dump(err),Data="400"})
end

_utils.getRandomNumber = function (seed,len)
  local crypto  = crypto or require(".crypto")
  local numbers = ""
  for i = 1, len or 3 do
    local r = crypto.cipher.issac.getRandom()
    local n = crypto.cipher.issac.random(0, 9, tostring(i)..seed..tostring(r))
    numbers = numbers .. n
  end
  return numbers
end


_utils.convertCommandToNumbers = function(str)
  local result = {}
  for part in string.gmatch(str, "[^,]+") do
      local startNum, endNum = string.match(part, "^(%d+)-(%d+)$")
      if startNum and endNum then
          startNum, endNum = tonumber(startNum), tonumber(endNum)
          local step = startNum <= endNum and 1 or -1         
          for i = startNum, endNum, step do
              local numStr = string.format("%03d", i)
              if string.len(numStr) <= 3 then
                  table.insert(result, numStr)
              end
          end
      elseif string.match(part, "^%d+$") then
          if string.len(part) <= 3 then
              table.insert(result, string.format("%03d", tonumber(part)))
          end
      else
          return {}
      end
  end
  return result
end


_utils.countBets = function(ntb, lmt)
  local countTable = {}
  for _, value in ipairs(ntb) do
      countTable[value] = (countTable[value] or 0) + 1
  end
  local result = {}
  local remainingLmt = lmt
  local processedValues = {}
  for _, value in ipairs(ntb) do
      if not processedValues[value] then
          local count = countTable[value]
          if count <= remainingLmt then
              result[#result + 1] = {value, count}
              remainingLmt = remainingLmt - count
          else
              result[#result + 1] = {value, remainingLmt}
              remainingLmt = 0
          end
          processedValues[value] = true
      end
  end

  if remainingLmt >= 1 and #result > 0 then
      result[#result][2] = result[#result][2] + remainingLmt
  end

  local filtered = {}
  for _, item in ipairs(result) do
    if item[2] ~= 0 then
      filtered[#filtered + 1] = item
    end
  end
  return filtered
end
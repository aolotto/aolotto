local utils = require(".utils")
local crypto = require(".crypto")

utils.parseNumberStringToBets = function(str,len)
  local bets = {}
  local total = 0
  
  for item in string.gmatch(str, "[^,]+") do
    local start, finish, multiplier = string.match(item, "(%d+)-?(%d*)%*?(%d*)")
    
    if start and string.len(start) <= len then
      multiplier = tonumber(multiplier) or 1
      
      if finish == "" then
        -- Single number or number with multiplier
        local num = string.format("%0"..len.."d", tonumber(start))  -- 补零
        bets[num] = (bets[num] or 0) + multiplier
        total = total + multiplier
      else
        -- Number range
        local startNum, finishNum = tonumber(start), tonumber(finish)
        if startNum and finishNum and startNum <= finishNum and string.len(finish) <= len then
          for i = startNum, finishNum do
            local num = string.format("%0"..len.."d", i)
            bets[num] = (bets[num] or 0) + multiplier
            total = total + multiplier
          end
        end
      end
    end
    -- Skip illegal input
  end
  
  return bets, total
end

utils.getRandomNumber = function(len,seed)
  local numbers = ""
  for i = 1, len or 3 do
    local r = crypto.cipher.issac.getRandom()
    local n = crypto.cipher.issac.random(0, 9, tostring(i)..seed..tostring(r))
    numbers = numbers .. n
  end
  return numbers
end

utils.getDrawNumber = function(seed,len)
  local numbers = ""
  for i = 1, len or 3 do
    local n = crypto.cipher.issac.random(0, 9, tostring(i)..seed..numbers)
    numbers = numbers .. n
  end
  return numbers
end

utils.increase = function(targetTable, fields)
  assert(targetTable~=nil and type(targetTable) == "table", "The target not a table or non exists")
  for key, value in pairs(fields) do
      if type(value) == "table" then
          if not targetTable[key] then
              targetTable[key] = {} 
          end
          increase(targetTable[key], value)
      else
          targetTable[key] = tonumber(targetTable[key] or 0) + tonumber(value)
      end
  end
end

utils.decrease = function(targetTable, fields)
  assert(targetTable~=nil and type(targetTable) == "table", "The target not a table or non exists")
  for key, value in pairs(fields) do
      if type(value) == "table" then
          if not targetTable[key] then
              targetTable[key] = {} 
          end
          decrease(targetTable[key], value)
      else
          targetTable[key] = tonumber(targetTable[key] or 0) - tonumber(value)
      end
  end
end

utils.update = function(targetTable,fields)
  assert(targetTable~=nil and type(targetTable) == "table", "The target not a table or non exists")
  for key, value in pairs(fields) do
    targetTable[key] = value
  end
end

utils.deepCopy = function(original)
  if type(original) ~= "table" then
      return original
  end
  local copy = {} 
  for k, v in pairs(original) do
      copy[k] = utils.deepCopy(v) 
  end
  return copy
end

utils.parseSting = function(str,symbol)
  local result = {}
  for item in string.gmatch(str, string.format("[^%s]+",symbol or ",")) do
    table.insert(result, item)
  end
  return result
end

utils.query = function(self,limit,offset,sort)
  local temp = {}
  table.move(self, 1, #self, 1, temp)
  if(sort) then
    table.sort(temp,function(a,b) 
      if sort[2] == "desc" then
        return a[sort[1]] > b[sort[1]]
      else
        return a[sort[1]] < b[sort[1]]
      end
    end)
  end
  local result = {}
  table.move(temp, offset or 1, math.min((limit or #temp) + (offset or 0)-1, #temp),1, result)
  return result
end

utils.getMd4Digests = function(str)
  local str = crypto.utils.stream.fromString(str or "aototto")
  return crypto.digest.md4(str).asHex()
end



return utils

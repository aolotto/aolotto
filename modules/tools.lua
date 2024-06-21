local json = json or require("json")
local utils = utils or require(".utils")
local crypto  = crypto or require(".crypto")
local const = require("modules.const")

local tools = {}

local errorCode = {
  default = "400",
  transfer_error = "Transfer-Error"
}

function tools:sendError (err,target,code)
  local red = "\027[31m"
  local reset = "\027[0m"
  ao.send({
    Target=target,
    Action="Error",
    Error = code or errorCode.default,
    Data=red..tostring(err)..reset
  })
end

function tools:getRandomNumber(seed,len)
  local numbers = ""
  for i = 1, len or 3 do
    local r = crypto.cipher.issac.getRandom()
    local n = crypto.cipher.issac.random(0, 9, tostring(i)..seed..tostring(r))
    numbers = numbers .. n
  end
  return numbers
end

function tools:parseStringToBets(str, limit)
  local char = string.match(str, "[%p%s]")
  -- 判断字符串是否为数值
  local function isNumeric(str)
    return string.match(str, "^%d+$") ~= nil
  end

  -- 过滤表达式中的值
  local function filterValue(str,char)
    local vals = {}
    for v in string.gmatch(str, "([^" .. char .. "]+)") do
      if isNumeric(v) and string.len(v) == 3  then
        table.insert(vals,v)
      end
    end
    return vals
  end

  -- 生成序列数值
  local function generateSequence(min, max)
    local sequence = {}
    for i = min, max do
        local v = string.format("%03d", i)
        table.insert(sequence, v)
    end
    return sequence
  end

  -- 数量计算
  local function counter(tbl,limit)
    local lens = math.min(limit,#tbl)
    local base = limit//lens
    local reamin = limit%lens
    local result = {}
    for i = 1, lens do
        result[tbl[i]] = result[tbl[i]] and result[tbl[i]] + base or base
    end
    result[tbl[lens]] = result[tbl[lens]] + reamin
    return result
  end

  local num_tbl = nil

  if char then
    local s_arr = filterValue(str,char)
    if char == "," then
      num_tbl = #s_arr>0 and s_arr or nil
    elseif char == "-" and #s_arr>1  then
      
      local n = {}
      for _, v in ipairs(s_arr) do
          table.insert(n, tonumber(v))
      end
      local min = math.min(table.unpack(n))
      local max = math.max(table.unpack(n))
      num_tbl = generateSequence(min,max)
    end
  elseif string.len(str) == 3 and isNumeric(str) then
    num_tbl = {}
    table.insert(num_tbl,str)
  else
    num_tbl = nil
  end

  local result = nil
  if num_tbl and #num_tbl>0  then
    result = counter(num_tbl,limit)
  end
  return result
end

function tools:getParticipationRoundStr (str)
  local tbl = str and json.decode(str) or {}
  if not utils.includes(ROUNDS.current,tbl) then
    table.insert(tbl,ROUNDS.current)
  end
  return json.encode(tbl)
end


function tools:timestampToDate (timestamp, format)
  local seconds = math.floor(timestamp / 1000)
  local milliseconds = timestamp % 1000

  local date = os.date("*t", seconds)
  date.ms = milliseconds

  if format then
      return os.date(format, seconds)
          :gsub("%%MS", string.format("%03d", milliseconds))
  else
      return os.date("%Y-%m-%d %H:%M:%S", seconds)
          .. string.format(".%03d", milliseconds)
  end
end


function tools:toBalanceValue(v)
  local precision = TOKEN.Denomination or 3
  return string.format("%." .. precision .. "f", v / 10^precision)
end

function tools:messageToBets(msg)
  local numbers_str = msg.Tags[const.Actions.x_numbers] or self:getRandomNumber(msg.Id..tostring(msg.Timestamp),3)
  print(numbers_str)
  local bet_num_tbl = self:parseStringToBets(numbers_str,tonumber(msg.Quantity))
  if not bet_num_tbl then
    local key = self:getRandomNumber(msg.Id,3)
    bet_num_tbl = {}
    bet_num_tbl[key] = tonumber(msg.Quantity)
  end
  local bets = {}
  for key, value in pairs(bet_num_tbl) do
    table.insert(bets,{key,value})
  end
  return bets
end

return tools
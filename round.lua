ROUND = 1
AOLOTTO = "wqwklmuSqSPGaeMR7dHuciyvBDtt1UjmziAoWu-pKuI"
_STATE  = {
  ended = nil,
  base_amount = 0,
  current_amount = 0,
  start_time = 1716283202884,
  participants = 0
}
_CONST = {
  dur = 86400000
}

Bets = {}
Bet_logs = {}

local crypto = require(".crypto")
local bint = require('.bint')(256)
local json = json or require("json")
local utils = require(".utils")



_utils = nil

saveBets = function(bets,msg)
  Bets = Bets or {}
  local bet_uid = msg.Donee or msg.User
  local user_bets_table = {}
  if Bets[bet_uid] then
    user_bets_table = Bets[bet_uid]
    local participants = _STATE.participants or 0
    _STATE.participants = participants + 1
  end
  local numbers = user_bets_table.numbers or {}
  local count = user_bets_table.count or 0
  for i, v in ipairs(bets) do
    local num = v[1]
    local qty = v[2]
    local cur_qty = numbers[v[1]] or 0
    numbers[num] = cur_qty + qty
  end
  user_bets_table['numbers'] = numbers
  user_bets_table['count'] = msg.Donee and count or count + 1
  Bets[bet_uid] = user_bets_table
end

pushBetLogs = function (bets,msg)
  local log = {
    ['Timestamp'] = msg.Timestamp,
    ['User'] = msg.User,
    ['Bets'] = bets,
    ['Donee'] = msg.Donee or nil,
    ['Quantity'] = msg.Quantity,
    ['Id'] = msg.Id
  }
  table.insert(Bet_logs,log)
end


saveDonees = function (bets,msg)
  if not msg.Donee then return end
  local user_bets_table = Bets[msg.User] or {}
  local count = user_bets_table.count or 0
  local donees = user_bets_table.donees or {}
  table.insert(donees,{msg.Donee,bets})
  user_bets_table['donees'] = donees
  user_bets_table['count'] = count + 1
  Bets[msg.User] = user_bets_table
end

endedThisRound = function (msg)
  ao.send({Target=AOLOTTO,Action="Ended",Round=tostring(ROUND),Amount=tostring(_STATE.base_amount + _STATE.current_amount)})
  _STATE.ended = 1
  _STATE.end_time = msg.Timestamp
end


getRandomNumber = function (seed,len)
  local crypto  = crypto or require(".crypto")
  local numbers = ""
  for i = 1, len or 3 do
    local r = crypto.cipher.issac.getRandom()
    local n = crypto.cipher.issac.random(0, 9, tostring(i)..seed..tostring(r))
    numbers = numbers .. n
  end
  return numbers
end

countWinners = function (win_nums)
  local result = {}
  local sum = 0
  local per_reward = nil
  for key, value in pairs(Bets) do
      if value.numbers[win_nums] then
          table.insert(result, {key, value.numbers[win_nums]})
      end
  end
  if #result > 0 then
    for i, v in ipairs(result) do
      sum = sum + v[2]
    end
    per_reward = (_STATE.base_amount + _STATE.current_amount) * 0.5 / sum
    for i, v in ipairs(result) do
      v[3] = v[2] / sum
      v[4] = v[2] * per_reward
      v[5] = win_nums
    end
  end
  return result, sum, per_reward
end

saveWinnersToAgent = function (winners,drawInfo)
  local json = json or require("json")
  local message = {
    Target = AOLOTTO,
    Action = "SaveWinners",
    Data = json.encode({
      round_no = ROUND,
      winners = winners,
      drawInfo = drawInfo
    })
  }
  ao.send(message)
end

sendRewardNotice = function (winner)
  local data_str = string.format("Congrats! Your %d bets with number '%d' in aolotto Round %d have won %s CRED. Use ' Send({Target=AOLOTTO, Action='Claim'}) ' to claim the prize.",winner[2],winner[5],ROUND,tostring(winner[4]/100) )
  local message = {
    Target = winner[1],
    Action = "Reward-Notice",
    Round = tostring(ROUND),
    Name = "aolotto",
    Data = data_str
  }
  ao.send(message)
end


sendDrawedNotice = function (participants)
  local message = {
    Target = ao.id,
    Data = "aolotto Round ".. tostring(ROUND).. " is ended, and the Round "..tostring(ROUND+1).." is alive ,just keep on!",
    Assignments = participants
  } -- 备注：无法发送消息
  ao.send(message)
end


timestampToDate = function (timestamp, format)
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

--[[ 接口 ]]--

Handlers.add(
  'saveNumbers',
  function (msg)
    local AOLOTTO = AOLOTTO or "wqwklmuSqSPGaeMR7dHuciyvBDtt1UjmziAoWu-pKuI"
    if msg.From == AOLOTTO and msg.Tags.Action == "SaveNumbers" and msg.Tags["User"] then
      return true
    else
      return false
    end
  end,
  function (msg)
    xpcall(function (msg)
      if not msg.Quantity then return end
      local json = json or require("json")
      local bets = json.decode(msg.Data)
      -- 保存用户的bets
      saveBets(bets,msg)
      -- 保存用户参与记录
      pushBetLogs(bets,msg)
      -- 保存受益人
      if msg.Donee then
        saveDonees(bets,msg)
      end
      -- 保存总金额
      _STATE.current_amount = _STATE.current_amount + tonumber(msg.Quantity)
      -- 下发消息
      local data_str = ""
      if msg.Donee then
        data_str = string.format("Placed %d bet%s for '%s' on aolotto Round %d , with the numbers: %s",
          msg.Quantity, tonumber(msg.Quantity)>1 and "s" or "" , msg.Donee , ROUND or msg.Round , msg.Data )
      else
        data_str = string.format("Placed %d bet%s on aolotto Round %d , with the numbers: %s",
          msg.Quantity , tonumber(msg.Quantity)>1 and "s" or "", ROUND or msg.Round , msg.Data )
      end

      local message = {
        Target = msg.User,
        Action = "Lotto-Notice",
        Data = data_str,
        Quantity = msg.Quantity,
        Round = tostring(ROUND) or msg.Round,
        AOLOTTO = AOLOTTO,
        ["Pushed-For"] = msg.Tags["Pushed-For"],
        ["X-Numbers"] = msg.Tags["X-Numbers"]
      }
      if msg.Donee then
        message['Donee'] = msg.Donee
      end
      ao.send(message)
    end,function (err) print(err) end, msg)
  end
)

Handlers.add(
  'autoStop',
  function (msg)
    local SHOOTER = SHOOTER or "7tiIWi2kR_H9hkDQHxy2ZqbOFVb58G4SgQ8wfZGKe9g"
    if not _STATE.ended and msg.From == SHOOTER and msg.Tags.Action == "1m_shoot" then
      return true
    else
      return false
    end
  end,
  function (msg)
    if msg.Timestamp < _STATE.start_time + _CONST.dur then 
      return 
    end -- 不到时间不开奖
    if _STATE.current_amount < _STATE.base_amount then 
      return 
    end -- 参与金额小于基础金额不开奖
    endedThisRound(msg)
  end
)

Handlers.add(
  'manualStop',
  function (msg)
    if not _STATE.ended and msg.Tags.Action == "ManualStop" and ao.isTrusted(msg) then
      return true
    else
      return false
    end
  end,
  function (msg)
    if msg.Timestamp < _STATE.start_time + _CONST.dur then 
      ao.send({Target=msg.From,Data="不到开奖时间"})
      return 
    end -- 不到时间不开奖
    if _STATE.current_amount < _STATE.base_amount then 
      ao.send({Target=msg.From,Data="参与金额小于基础金额"})
      return 
    end -- 参与金额小于基础金额不开奖
    print("手工检查是否开奖")
    endedThisRound(msg)
  end
)

Handlers.add(
  'draw',
  function (msg)
    if _STATE.ended and msg.Tags.Action == "Draw" and ao.isTrusted(msg) then
      return true
    else
      return false
    end
  end,
  function (msg)
    local seed = msg.Id..tostring(_STATE.current_amount) -- 基于msgId和当前参与者金额生成随机种子
    local win_nums = getRandomNumber(seed,3) -- 生成3位随机数
    _STATE["win_nums"] = win_nums --保存获奖号码
    local winners, total_qty, per_reward = countWinners(win_nums) -- 统计中奖者和中奖注数
    Winners = winners --保存为全局状态
    DrawInfo = {
      round_no = ROUND,
      process = ao.id,
      total_winners = #winners,
      total_win_bets = total_qty,
      per_bet_reward_amount = per_reward,
      draw_time = msg.Timestamp
    }
    saveWinnersToAgent(winners,DrawInfo) -- 通知agent保存获奖信息
    local utils = utils or require("utils")
    
    if #winners > 0 then
      utils.map(function (winner) sendRewardNotice(winner) end, winners)
    end -- 向winner下发中奖通知
   
    local participants = utils.keys(Bets)
    sendDrawedNotice(participants)
    -- utils.map(function (val, uid)
    --   if not utils.includes(uid, winners or Winners) then
    --     sendDrawedNotice(uid)
    --   end
    -- end,Bets)
    -- 向未中奖参与者下发开奖通知
  end
)

Handlers.add(
  'fetchBets',
  Handlers.utils.hasMatchingTag("Action","FetchBets"),
  function (msg)
    local json = json or require("json")
    local user_bets = Bets[msg.User or msg.From]
    local message = {
      Target = msg.User or msg.From,
      Action = "ReplyUserBets",
    }
    if user_bets.numbers and table.pack(user_bets.numbers).n > 0 then
      message.Data = string.format("You've placed %d bets into this Round: %s",table.pack(user_bets.numbers).n,json.encode(user_bets.numbers))
    else
      message.Data = string.format("You don't have any bets in aolotto Round %d.",ROUND)
    end
    ao.send(message)
  end
)

Handlers.add(
  'fetchInfo',
  Handlers.utils.hasMatchingTag("Action","Info"),
  function (msg)

    local state_str = _STATE.ended and "Ended" or "Ongoing"
    local start_date_str = timestampToDate(_STATE.start_time,"%Y/%m/%d %H:%M")
    local end_date_str = timestampToDate(_STATE.start_time+_CONST.dur,"%Y/%m/%d %H:%M")
    local total_prize_str = tostring(_STATE.base_amount + _STATE.current_amount)
    local participants_str = tostring(_STATE.participants)
    local base_str = tostring(_STATE.base_amount)
    local bets_str = tostring(_STATE.current_amount)
    local tips_str = _STATE.ended and string.format("Draw on %s, $d winners.",end_date_str,#Winners) or string.format("Draw on %s if bets >= %s",end_date_str,base_str)

    local str=  string.format([[

    ------------------------------------      
    aolotto Round %d - %s
    ------------------------------------ 
    * Current Prize: %s CRED
    * Participants: %s
    * Bets: %s
    * Start: %s
    ------------------------------------ 
    %s

    ]],ROUND,state_str,total_prize_str,participants_str,bets_str,start_date_str,tips_str)
    local message = {
      Target = msg.User or msg.From,
      Data = str,
      Action = "ReplyInfo",
    }
    ao.send(message)
  end
)

Handlers.add(
  'fetchWinners',
  Handlers.utils.hasMatchingTag("Action","Winners"),
  function (msg)
    if Winners and #Winners > 0 then
      local json = json or require("json")
      local data_str = json.encode(Winners)
      ao.send({
        Target = msg.User or msg.From,
        Action = "ReplyWinners",
        Data = data_str
      })
    end
  end
)




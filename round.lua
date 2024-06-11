if not ROUND then ROUND = ao.env.Process.Tags["Round"] end
if not AOLOTTO then AOLOTTO = ao.env.Process.Tags["Agent"] end
if not SHOOTER then SHOOTER = ao.env.Process.Tags["Shooter"] end
if not OPERATOR then OPERATOR = ao.env.Process.Tags["Operator"] or "-_hz5V_I73bHVHqKSJF_B6cDBBSn8z8nPEUGcViTYko" end
if not _CONST then _CONST = {
  dur = tonumber(ao.env.Process.Tags["Duration"]),
  base_rewards = tonumber(ao.env.Process.Tags["BaseRewards"]),
  start_time = tonumber(ao.env.Process.Tags["StartTime"])
} end
ao.authorities = {AOLOTTO,SHOOTER,OPERATOR}

crypto = require(".crypto")
json = require("json")
utils = require(".utils")

if not Bets then Bets = {} end
if not Bet_logs then Bet_logs = {} end
if not _STATE then _STATE = {} end
if not Winners then Winners = {} end


saveBets = function(bets,msg)
  local bet_uid = msg.Donee or msg.User
  local user_bets_table = {}
  if Bets[bet_uid] then
    user_bets_table = Bets[bet_uid]
  else
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

endThisRound = function (msg)
  ao.send({Target=AOLOTTO,Action="Ended",Round=tostring(ROUND),Amount=tostring(_CONST.base_rewards + (_STATE.current_amount or 0))})
  _STATE.ended = true
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

countWinners = function (win_nums,reserve)
  local result = {}
  local per_reward = 0
  local totalBetsAmount = 0
  for key, value in pairs(Bets) do
      if value.numbers[win_nums] then
          table.insert(result, {
            id = key,
            amount = value.numbers[win_nums]
          })
      end
  end
  if #result > 0 then
    local utils = utils or require(".utils")
    totalBetsAmount = utils.reduce(function (acc, v) return acc + v end)(0)(utils.map(function (val) return val.amount end)(result))

    per_reward = (_CONST.base_rewards + (_STATE.current_amount or 0) - tonumber(reserve)) / totalBetsAmount

    utils.map(function (v, key)
      v["percent"] = v.amount / totalBetsAmount
      v["rewards"] = math.floor(v.amount * per_reward)
      v["matched"] = win_nums
    end,result)
  end
  return result, totalBetsAmount,per_reward
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


sendWinnersToAgent =  function (winners,drawInfo,reserve)
  local json = json or require("json")
  local message = {
    Target = AOLOTTO,
    Action = "SaveWinners",
    ["Winners"] = tostring(drawInfo.total_winners),
    ["Winbets"] = tostring(drawInfo.total_win_bets),
    ["Rewards"] = tostring(_CONST.base_rewards+(_STATE.current_amount or 0)-reserve),
    Data=json.encode(winners)
  }
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
      _STATE.current_amount = (_STATE.current_amount or 0) + tonumber(msg.Quantity)

      -- 检查是否可以结束轮次
      if msg.Timestamp >= (_CONST.start_time + _CONST.dur) and _STATE.current_amount >= _CONST.base_rewards then 
        endThisRound(msg)
      end

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
    SHOOTER = SHOOTER or "7tiIWi2kR_H9hkDQHxy2ZqbOFVb58G4SgQ8wfZGKe9g"
    if not _STATE.ended and msg.From == SHOOTER and msg.Tags.Action == "1m_shoot" then
      return true
    else
      return false
    end
  end,
  function (msg)
    if msg.Timestamp < _CONST.start_time + _CONST.dur then 
      return 
    end -- 不到时间不开奖
    if (_STATE.current_amount or 0) < _CONST.base_rewards then 
      return 
    end -- 参与金额小于基础金额不开奖
    endThisRound(msg)
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
    if msg.Timestamp < _CONST.start_time + _CONST.dur then 
      ao.send({Target=msg.From,Data="不到开奖时间"})
      return 
    end -- 不到时间不开奖
    if (_STATE.current_amount or 0) < _CONST.base_rewards then 
      ao.send({Target=msg.From,Data="参与金额小于基础金额"})
      return 
    end -- 参与金额小于基础金额不开奖
    endThisRound(msg)
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
    assert(type(msg.ReserveToNextRound) == 'string', 'ReserveToNextRound is required!')
    local reserve = tonumber(msg.ReserveToNextRound)
    local seed = msg.Id..tostring(_STATE.current_amount or 0) -- 基于msgId和当前参与者金额生成随机种子
    local win_nums = getRandomNumber(seed,3) -- 生成3位随机数
    _STATE["win_nums"] = win_nums --保存获奖号码
    print("Draw")
    local winners, total_qty, per_reward = countWinners(win_nums,reserve) -- 统计中奖者和中奖注数
    Winners = winners --保存为全局状态
    DrawInfo = {
      round_no = ROUND,
      total_winners = #winners,
      total_win_bets = total_qty,
      per_bet_reward_amount = per_reward,
      available_rewards = _CONST.base_rewards+(_STATE.current_amount or 0)-reserve,
      rewards_reserve = reserve,
      total_rewards = _CONST.base_rewards+(_STATE.current_amount or 0),
      draw_time = msg.Timestamp
    }
    sendWinnersToAgent(Winners,DrawInfo,reserve) -- 通知agent保存获奖信息
    if #Winners > 0 then
      for i, winner in ipairs(Winners) do
        sendRewardNotice(winner)
      end
    end
  end
)

Handlers.add(
  'fetchBets',
  Handlers.utils.hasMatchingTag("Action","Bets"),
  function (msg)
    local json = json or require("json")
    local user_bets = Bets[msg.User or msg.From]
    local request_type = msg.RequestType or ""
    local data_str = ""
    if user_bets and user_bets.numbers then
      local total_numbers = 0
      local total_bets = 0
      local bets_str = "\n"..string.rep("-", 58).."\n"
      for key, value in pairs(user_bets.numbers) do
        total_numbers = total_numbers +1
        total_bets = total_bets +value
        bets_str = bets_str .. string.format(" %03d *%5d ",key,value) .. (total_numbers % 4 == 0 and "\n"..string.rep("-", 58).."\n" or " | ")
      end
      data_str = string.format([[You've placed %d bets that cover %d numbers on Round %d : ]],total_bets,total_numbers,ROUND)..bets_str
    else
      data_str = string.format("You don't have any bets on aolotto Round %d.",ROUND)
    end
    
    local message = {
      Target = msg.User or msg.From,
      Action = "Reply-UserBets",
      Data = (request_type == "json") and json.encode(user_bets.numbers) or data_str
    }
    ao.send(message)
  end
)

Handlers.add(
  'fetchInfo',
  Handlers.utils.hasMatchingTag("Action","Info"),
  function (msg)
    local request_type = msg.RequestType or ""
    local str = ""
    if request_type == "json" then
      local json = json or require("json")
      str = json.encode(_STATE)
    else
      local state_str = _STATE.ended and "Ended" or "Ongoing"
      local start_date_str = timestampToDate(_CONST.start_time,"%Y/%m/%d %H:%M")
      local end_date_str = timestampToDate(_CONST.start_time+_CONST.dur,"%Y/%m/%d %H:%M")
      local total_prize = (_CONST.base_rewards + (_STATE.current_amount or 0))/1000
      local participants_str = tostring(_STATE.participants or 0)
      local base_str = tostring(_CONST.base_rewards)
      local bets_str = tostring(_STATE.current_amount or 0)
      local winners_str = _STATE.ended and tostring(#Winners or 0) or tostring(0)
      local tips_str = _STATE.ended and string.format("Drawn on %s UTC, %s winners.",end_date_str,winners_str) or string.format("draw on %s UTC if bets >= %s",end_date_str,base_str)

      str=  string.format([[

    -----------------------------------------      
    aolotto Round %d - %s
    ----------------------------------------- 
    * Total Prize:       %.3f CRED
    * Participants:      %s
    * Bets Amount:       %s
    * Start at:          %s UTC
    ----------------------------------------- 
    %s

      ]],ROUND,state_str,total_prize,participants_str,bets_str,start_date_str,tips_str)
    end
    local message = {
      Target = msg.User or msg.From,
      Data = str,
      Action = "Reply-RoundInfo",
    }
    ao.send(message)
  end
)

Handlers.add(
  'fetchWinners',
  Handlers.utils.hasMatchingTag("Action","Winners"),
  function (msg)
    if Winners and #Winners > 0 then
      local data_str = ""
      local request_type = msg.RequestType or ""
      if request_type and request_type == "json"  then
        local json = json or require("json")
        data_str = json.encode(Winners)
      else
        table.sort(Winners, function (a,b)
          return a.rewards < b.rewards
        end)
        local list_str = ""

        for i, v in ipairs(Winners) do
          list_str = list_str..string.format(" * %s   %10d   %6.3f CRED",v.id,v.amount,v.rewards/1000).."\n"
        end
        local before_str = string.format(" %d winners of aolotto Round %d \n",#Winners, ROUND)
        local line_str = string.rep("-", 74).."\n"
        local td_str = " winner                                                bets       rewards\n"
        data_str = before_str..line_str..td_str..line_str..list_str..line_str.."\n"
      end  

      local message = {
        Target = msg.User or msg.From,
        Action = "Reply-Winners",
        Winners = tostring(#Winners),
        Data = data_str
      }
      
      ao.send(message)
    end
  end
)

Handlers.add(
  "fetchBetLogs",
  Handlers.utils.hasMatchingTag("Action","BetLogs"),
  function (msg)
    xpcall(function (msg)
      if msg.From == AOLOTTO then
        assert(msg.User and Bets[msg.User], 'User is not exist!')
      else
        assert(Bets[msg.From], 'User is not exist!')
      end
      local utils =  utils or require(".utils")
      local user_bet_logs = utils.filter(function (val)
        return val.User == msg.User or msg.From
      end,Bet_logs)
      local json = json or require("json")
      local message = {
        Target = msg.User or msg.From,
        Action = "Reply-BetLogs",
        Data = json.encode(user_bet_logs)
      }
      ao.send(message)
    end,function (err)
      print(err)
    end,msg)
  end
)
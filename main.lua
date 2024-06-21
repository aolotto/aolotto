--[[
  *******************
  Global constants and module imports
  *******************
]]--
local _config = require("_config")
local const = require("modules.const")
local utils = require(".utils")
local crypto = require(".crypto")
local json = require("json")
local bint = require('.bint')(256)


if not NAME then NAME = ao.env.Process.Tags.Name or "aolotto" end
if not VERSION then VERSION = "dev" end
if not TOKEN then TOKEN = {
  Ticker="ALT",
  Process="zQ0DmjTbCEGNoJRcjdwdZTHt0UBorTeWbb_dnc6g41E",
  Denomination=3,
  Name="AolottoToken"
} end
if not SHOOTER then SHOOTER = _config.SHOOTER or "7tiIWi2kR_H9hkDQHxy2ZqbOFVb58G4SgQ8wfZGKe9g" end
if not OPERATOR then OPERATOR = _config.OPERATOR or "-_hz5V_I73bHVHqKSJF_B6cDBBSn8z8nPEUGcViTYko" end
if not ARCHIVER then ARCHIVER = _config.ARCHIVER or "MmIMz7OK893PDr5tYQyHPBEWZxQiyNwUBPBRLWQib1I" end

--[[
  *******************
  Initialize the database to store user information。
  *******************
]]--
if not db then 
  db = require("modules.database")
  db:exec[[
  CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    bets_count INTEGER,
    bets_amount INTEGER,
    rewards_balance INTEGER,
    total_rewards_amount INTEGER,
    total_rewards_count INTEGER,
    total_shared_count INTEGER,
    participation_rounds TEXT,
    create_at INTEGER,
    update_at INTEGER
  );
]]
end

--[[
  全局状态对象
]] --
if not STATE then STATE = {
  run = 1,
  pool_balance = 0,
  total_pool_balance = 0,
  operator_balance = 0,
  total_pool_balance = 0,
  tax_rete = 0.1,
  total_withdraw = {},
  total_claim_paid = 0
} end
setmetatable(STATE,{__index=require("modules.state")})
--[[
  投注统计
]] --
if not BET then BET = {bets={},logs={}} end
setmetatable(BET,{__index=require("modules.bet")})

--[[
  轮次
]]
if not ROUNDS then ROUNDS = {repo={},current=1,duration = 86400000} end
setmetatable(ROUNDS,{__index=require("modules.rounds")})

--[[
  工具
]]
if not TOOLS then TOOLS = {} end
setmetatable(TOOLS,{__index=require("modules.tools")})

--[[
  用户
]]
if not USERS then USERS = { db_name ="users" } end
setmetatable(USERS,{__index=require("modules.users")})

--[[
  归档暂存
]]
if not ARCHIVES then ARCHIVES = {archiver = ARCHIVER} end
setmetatable(ARCHIVES,{__index=require("modules.archives")})


--[[
  退款记录
]]
if not REFUNDS then REFUNDS = {logs={}} end
setmetatable(REFUNDS,{__index=require("modules.refund")})


--[[ 投注接口 ]]



Handlers.add(
  '_credit_bet',
  function (msg)
    local TOKEN_PROCESS = TOKEN.Process or "Sa0iBLPNyJQrwpTTG-tWLQU-1QeUAJA73DdxGGiKoJc"
    if msg.From == TOKEN_PROCESS and msg.Tags.Action == "Credit-Notice" and msg.Tags.Sender ~= TOKEN_PROCESS then
      return true
    else
      return false
    end
  end,
  function (msg)
    xpcall(function (msg)
      assert(type(msg.Quantity) == 'string', 'Quantity is required!')
      if STATE.run ~= 1 then ROUNDS:refundToken(msg) end
      assert(STATE.run  == 1, string.format("Aolotto is not accepting bets %s.",STATE.run == 0 and "now" or "forever"))
      assert(msg.Sender ~= OPERATOR, "Operator is not available on betting")
      if not ROUNDS:get("1") then ROUNDS:create("1",msg.Timestamp) end

      -- 判断是否为当前轮次的新参与者
      local participated = BET:isParticipated(msg)
      -- 消息转换为投注
      local bets = TOOLS:messageToBets(msg)

      -- 保存投注记录
      BET:save(bets,msg)

      -- 更新用户数据
      local user = USERS:queryUserInfo(msg.Sender) or {}
      local userInfo = {
        id = msg.Sender,
        bets_count = user.bets_count and user.bets_count + 1 or 1,
        bets_amount = user.bets_amount and (user.bets_amount+tonumber(msg.Quantity)) or tonumber(msg.Quantity),
        rewards_balance = user.rewards_balance or 0,
        total_rewards_count = user.total_rewards_count or 0,
        total_rewards_amount = user.total_rewards_amount or 0,
        create_at = user.create_at or msg.Timestamp,
        update_at = msg.Timestamp,
        participation_rounds = TOOLS:getParticipationRoundStr(user.participation_rounds)
      }
      USERS:replaceUserInfo(userInfo)

      -- 更新轮次信息
      local target_round = ROUNDS:get(ROUNDS.current)
      if target_round then
        target_round.bets_count = target_round.bets_count + 1
        target_round.bets_amount = target_round.bets_amount + tonumber(msg.Quantity)
        target_round.participants = (target_round.participants or 0) + (participated and 0 or 1)
        ROUNDS:set(ROUNDS.current,target_round)
      end

      -- 增加奖池总额
      STATE:increasePoolBalance(msg.Quantity)
      STATE:increaseOperatorBalance(msg.Quantity)
      

      -- 下发消息
      local data_str = ""
      if msg.Donee then
        data_str = string.format("Placed %d bet%s for '%s' on aolotto Round %d , with the numbers: %s",
          msg.Quantity, tonumber(msg.Quantity)>1 and "s" or "" , msg.Donee , ROUNDS.current , json.encode(bets) )
      else
        data_str = string.format("Placed %d bet%s on aolotto Round %d , with the numbers: %s",
          msg.Quantity , tonumber(msg.Quantity)>1 and "s" or "", ROUNDS.current , json.encode(bets) )
      end


      local message = {
        Target = msg.Sender,
        Action = const.Actions.lotto_notice,
        Data = data_str,
        Quantity = msg.Quantity,
        Round = tostring(ROUNDS.current),
        Token = msg.From,
        ["Pushed-For"] = msg.Tags["Pushed-For"],
        [const.Actions.x_numbers] = msg.Tags[const.Actions.x_numbers]
      }
      if msg.Donee then
        message['Donee'] = msg.Donee
      end
      ao.send(message)

      -- 触发轮次结束
     
      if target_round.bets_amount >= target_round.base_rewards and msg.Timestamp >= (target_round.start_time + target_round.duration or ROUNDS.duration) then
        print("Time to ended "..tostring(target_round.no))
        Send({Target=ao.id,Action=const.Actions.finish,Round=tostring(target_round.no)})
      end

    end,function(err)
      print(err)
      TOOLS:sendError(err,msg.Tags.Sender)
    end, msg)
  end
)

--[[ 结束轮次 ]]


Handlers.add(
  "_finish",
  function (msg)
    local is_operator = msg.From == OPERATOR or msg.From == ao.id
    if is_operator and msg.Tags.Action == const.Actions.finish then return true else return false end
  end,
  function (msg)
    xpcall(function (msg)
      
      local no = msg.Round and tonumber(msg.Round) or ROUNDS.current
      local round = ROUNDS:get(no)
      local expired = (round.start_time or 0) + (round.duration*7)

      assert(round.drawn == nil or round.drawn == false,"The round has been drawn.")
      assert(round.status == 0,"The round has been finished.")
      assert(msg.Timestamp >= round.start_time+round.duration and msg.Timestamp < expired,"Time has not yet reached.")
      assert(round.bets_amount>=round.base_rewards and msg.Timestamp < expired, "The betting amount has not reached.")
      -- 归档
      ROUNDS:create(tostring(no+1),msg.Timestamp)
      local archive = BET:archive(no)

      if not expired then
        -- 开奖
        local draw_info, rewards = ROUNDS:draw(archive,msg.Timestamp)
        archive.draw_info = draw_info
        -- 处理抽奖结果
        if draw_info.winners and #draw_info.winners>0 then
          USERS:shareRewardsToWinners(draw_info.winners,msg.Timestamp)
        else
          USERS:shareRewardsToAll(rewards,msg.Timestamp)
        end
      else
        REFUNDS:refundToParticipantInBets(archive.bets,TOKEN.process)
      end
      
      -- 把轮次归档发送给归档程序
      ARCHIVES:add(no,archive)

    end,function (err)
      print(err)
      TOOLS:sendError(err,msg.From)
    end,msg)
  end
)



--[[ 更新轮次归档器 ]]

Handlers.add(
  "_round_archived",
  function (msg)
    if msg.From == ARCHIVER and msg.Tags.Action == const.Actions.round_archived and msg.Tags.Round then return true else return false end
  end,
  function (msg)
    ROUNDS.repo[msg.Tags.Round].process = msg.From
    ARCHIVES:remove(msg.Tags.Round)
  end
)



--[[ 查询当前或指定轮次的信息 ]]

Handlers.add(
  "getRoundInfo",
  Handlers.utils.hasMatchingTag("Action","GetRoundInfo"),
  function (msg)
    xpcall(function (msg)
      local request_type = msg.RequestType or ""
      local key = msg.Round or tostring(ROUNDS.current)
      local round = ROUNDS:get(key)
      assert(round ~= nil,"The round did not exists")
      local str = ""
      if request_type == "json" then
        str = json.encode(round)
      else
      local state_str = const.RoundStatus[round.status]
      local start_date_str = TOOLS:timestampToDate(round.start_time,"%Y/%m/%d %H:%M")
      local end_date_str = TOOLS:timestampToDate(round.end_time or round.start_time+round.duration,"%Y/%m/%d %H:%M")
      local total_prize = TOOLS:toBalanceValue(round.base_rewards + (round.bets_amount or 0))
      local participants_str = tostring(round.participants or 0)
      local base_str = tostring(round.base_rewards)
      local bets_str = tostring(round.bets_amount or 0)
      local winners_str = tostring(round.winners_count or 0)
      local tips_str = round.status ~= 0 and string.format("Drawn on %s UTC, %s winners.",end_date_str,winners_str) or string.format("draw on %s UTC if bets >= %s",end_date_str,base_str)

      str=  string.format([[

    -----------------------------------------      
    aolotto Round %d - %s
    ----------------------------------------- 
    * Total Prize:       %s %s
    * Participants:      %s
    * Bets:              %s
    * Start at:          %s UTC
    ----------------------------------------- 
    %s

        ]],tonumber(key),state_str,total_prize,TOKEN.Ticker or "AO",participants_str,bets_str,start_date_str,tips_str)
      end
      local message = {
        Target = msg.From,
        Data = str,
        Action = "Reply-RoundInfo",
      }
      ao.send(message)
        
    end,function (err)
      print(err)
      TOOLS:sendError(err,msg.From)
    end,msg)
  end
)

--[[ 用户查询当前或指定轮次的下注信息 ]]

Handlers.add(
  'fetchBets',
  Handlers.utils.hasMatchingTag("Action",const.Actions.bets),
  function (msg)
    xpcall(function (msg)
      local key = msg.Round or tostring(ROUNDS.current)
      local is_current_round = key == tostring(ROUNDS.current) 
      local round = ROUNDS:get(key)
      assert(round ~= nil, "The round is not exists")
      assert(is_current_round == false and round.process ~= nil,"The round you target has not been ready for query, please wait for minutes.")
      
      if is_current_round then
        local user_bets = BET.bets[msg.From]
        local request_type = msg.RequestType or ""
        local data_str = ""
        if user_bets and user_bets.count > 0 then
          local total_numbers = 0
          local total_bets = 0
          local bets_str = "\n"..string.rep("-", 58).."\n"
          for key, value in pairs(user_bets.numbers) do
            total_numbers = total_numbers +1
            total_bets = total_bets +value
            bets_str = bets_str .. string.format(" %03d *%5d ",key,value) .. (total_numbers % 4 == 0 and "\n"..string.rep("-", 58).."\n" or " | ")
          end
          data_str = string.format([[You've placed %d bets that cover %d numbers on Round %d : ]],total_bets,total_numbers,ROUNDS.current)..bets_str
        else
          data_str = string.format("You don't have any bets on aolotto Round %d.",ROUNDS.current)
        end
        local message = {
          Target = msg.From,
          Action = const.Actions.reply_user_bets,
          Data = (request_type == "json") and json.encode(user_bets.numbers) or data_str
        }
        ao.send(message)
      else
        local message = {
          Target = round.process,
          Action = const.Actions.bets,
          User = msg.From
        }
        if msg.RequestType then
          message[const.Actions.request_type] = msg[const.Actions.request_type]
        end
        ao.send(message)
      end
      
    end,function (err)
      print(err)
      TOOLS:sendError(err,msg.From)
    end,msg)
  end
)

-- [[ 查询用户的信息 ]]

Handlers.add(
  "getUserInfo",
  Handlers.utils.hasMatchingTag("Action", const.Actions.user_info),
  function (msg)
    xpcall(function (msg)
      local user = USERS:queryUserInfo(msg.From)
      assert(user ~= nil, "User not exists.")
      local request_type = msg[const.Actions.request_type] or ""
      local data_str = ""
      if user then
        if request_type == "json" then
          local json = json or require("json")
          data_str = json.encode(user)
        else
          data_str = string.format([==[
  %s
  -------------------------------------------
  * Number of Wins :   %d
  * Rewards Balance :  %s %s
  * Total Rewards :    %s %s
  * Bets Amount :      %d
  * Bets Placed :      %d
  -------------------------------------------
  First bet on %d
          ]==],user.id, user.total_rewards_count, TOOLS:toBalanceValue(user.rewards_balance),TOKEN.Ticker, TOOLS:toBalanceValue(user.total_rewards_amount),TOKEN.Ticker, user.bets_amount,user.bets_count,user.create_at)
        end  
      end
      local msssage = {
        Target = msg.From,
        Action = const.Actions.reply_user_info,
        Data = data_str
      }
      ao.send(msssage)
    end,function (err)
      TOOLS:sendError(err,msg.From)
    end,msg)
  end
)


-- [[ 领取奖金 ]]

Handlers.add(
  "claim",
  Handlers.utils.hasMatchingTag("Action", const.Actions.claim),
  function (msg)
    xpcall(function (msg)
      local user = USERS:queryUserInfo(msg.From)
      assert(user ~= nil,"User not exists")
      local err_str = string.format("Rewards balance is below the claim threshold of %s %s.",TOOLS:toBalanceValue(100),TOKEN.Ticker)
      assert(user.rewards_balance and user.rewards_balance >= 100,err_str)
      local TOKEN_PROCESS = TOKEN.Process or "Sa0iBLPNyJQrwpTTG-tWLQU-1QeUAJA73DdxGGiKoJc"
      local qty =  math.floor(user.rewards_balance * ((1-TAX_RATE) or 0.9))
      local message = {
        Target = TOKEN_PROCESS,
        Action = "Transfer",
        Recipient = msg.From,
        Quantity = tostring(qty),
        [const.Actions.x_transfer_type] = const.Actions.claim,
        [const.Actions.x_amount] = tostring(user.rewards_balance),
        [const.Actions.x_tax] = tostring(TAX_RATE),
        [const.Actions.x_pushed_for] = msg["Pushed-For"]
      }
      ao.send(message)
    end,function (err)
      print(err)
      TOOLS:sendError(err,msg.From) 
    end,msg)
  end
)


-- [[ 奖金下发后更新奖金余额 ]]

Handlers.add(
  "_debit_claim",
  function (msg)
    local triggered = msg.From == TOKEN.Process and msg.Tags.Action == "Debit-Notice" and msg.Tags[const.Actions.x_transfer_type] == const.Actions.claim
    if triggered then return true else return false end
  end,
  function (msg)
    xpcall(function (msg)
      local user = USERS:queryUserInfo(msg.Recipient)
      assert(user~=nil,"User is not exists")
      user.rewards_balance = math.max(user.rewards_balance - tonumber(msg.Quantity),0)
      user.update_at = msg.Timestamp
      USERS:replaceUserInfo(user)
      -- 减少奖池总额
      STATE:decreasePoolBalance(msg.Quantity)
      -- 增加奖励总额
      STATE:increaseClaimPaid(msg.Quantity)
    end,function (err)
      print(err)
      TOOLS:sendError(err,OPERATOR)
    end,msg)
  end
)

-- [[ 运营方提现 ]]
Handlers.add(
  "OP.withdraw",
  function(msg) 
    if msg.From == OPERATOR and msg.Action == const.Actions.OP_withdraw then return true else return false end
  end,
  function (msg)
    xpcall(function (msg)
      local TOKEN_PROCESS = msg.Tags.Token or TOKEN.Process
      local is_rewards_token = TOKEN_PROCESS == TOKEN.Process
      if is_rewards_token then
        assert(math.floor(STATE.operator_balance) >= 1, "Insufficient withdrawal amount")
        local message = {
          Target = TOKEN_PROCESS,
          Quantity = tostring(math.floor(STATE.operator_balance)),
          Recipient = msg.From,
          Action = "Transfer",
          [const.Actions.x_transfer_type] = const.Actions.OP_withdraw,
          [const.Actions.x_pushed_for] = msg["Pushed-For"]
        }
        ao.send(message)
      else
        local message = {
          Target = TOKEN_PROCESS,
          Quantity = msg.Tags.Quantity or "",
          Recipient = msg.From,
          Action = "Transfer"
        }
        ao.send(message)
      end
      
    end,function (err)
      print(err)
      TOOLS:sendError(err,msg.From)
    end,msg)
  end
)
Handlers.add(
  "OP._debit_op_withdraw",
  function (msg)
    local triggered = msg.From == TOKEN.Process and msg.Tags.Action == "Debit-Notice" and msg.Tags[const.Actions.x_transfer_type] == const.Actions.OP_withdraw
    if triggered then return true else return false end
  end,
  function (msg)
    xpcall(function (msg)
      STATE:decreaseOperatorBalance(msg.Quantity)
      STATE:decreasePoolBalance(msg.Quantity)
      STATE:increaseWithdraw(msg.Quantity)
    end,function (err)
      print(err)
      TOOLS:sendError(err,OPERATOR)
    end,msg)
  end
)

--[[ 运营方管理 ]]
Handlers.add(
  "OP.changeShooter",
  function(msg)
    if msg.From == OPERATOR and msg.Tags.Action == const.Actions.change_shooter then return true else return false end
  end,
  function(msg)
    xpcall(
      function(msg)
        print("改变触发器")
        assert(msg.Shooter ~= nil ,"Missed shooter tag." )
        SHOOTER = msg.Shooter
      end,
      function(err)
        print(err)
        TOOLS:sendError(err,msg.From)
      end,
      msg
    )
  end
)

Handlers.add(
  "OP.changeArchiver",
  function(msg)
    if msg.From == OPERATOR and msg.Tags.Action == const.Actions.change_archiver then return true else return false end
  end,
  function(msg)
    xpcall(
      function(msg)
        assert(msg.Archiver ~= nil ,"Missed Archiver tag." )
        ARCHIVER = msg.Archiver
      end,
      function(err)
        print(err)
        TOOLS:sendError(err,msg.From)
      end,
      msg
    )
  end
)

Handlers.add(
  "OP.pause",
  function(msg)
    if msg.From == OPERATOR and msg.Tags.Action == const.Actions.pause_round then return true else return false end
  end,
  function(msg)
    xpcall(
      function(msg)
        STATE:set("run",0)
        STATE:set("pause_start",msg.Timestamp)
      end,
      function(err)
        print(err)
        TOOLS:sendError(err,msg.From)
      end,
      msg
    )
  end
)

Handlers.add(
  "OP.restart",
  function(msg)
    if msg.From == OPERATOR and msg.Tags.Action == const.Actions.round_restart then return true else return false end
  end,
  function(msg)
    xpcall(
      function(msg)
        STATE:set("run",1)
        STATE:set("pause_end",msg.Timestamp)
      end,
      function(err)
        print(err)
        TOOLS:sendError(err,msg.From)
      end,
      msg
    )
  end
)


-- [[ 开奖触发器 ]]

Handlers.add(
  "_shoot",
  function (msg)
    if msg.From == SHOOTER and msg.Action == const.Actions.shoot then return true else return false end
  end,
  function (msg)
    local round = ROUNDS:get()
    assert(msg.Timestamp >= round.start_time + round.duration, "Time not reached." )
    local expired = (round.start_time or 0) + (round.duration*7)
    if expired or round.bets_amount >= round.base_rewards then
      Send({
        Target=ao.id,
        Action=const.Actions.finish
      })
    end  
  end
)


--[[ 查询历史轮次 ]]

Handlers.add(
  "fetchRounds",
  Handlers.utils.hasMatchingTag("Action",const.Actions.rounds),
  function (msg)
    local data_str = ""
    local request_type = msg[const.Actions.request_type] or ""
    if request_type == "json" then
      data_str = json.encode(ROUNDS.repo)
    else
      table.sort(ROUNDS.repo,function (a,b) return a.no > b.no end)
      for i, v in ipairs(ROUNDS.repo) do
        data_str = data_str..string.format("%4d : %s \n",v.no, v.process)
      end
    end
    local msssage = {
      Target = msg.From,
      Action = const.Actions.reply_rounds,
      Data = data_str
    }
    ao.send(msssage)
  end
)



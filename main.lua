--[[
  *******************
  Global constants and module imports
  *******************
]]--
local _config = require("_config")
local const = require("modules.const")
local messenger = require("modules.messenger")
local utils = require(".utils")
local crypto = require(".crypto")
local json = require("json")
local bint = require('.bint')(256)


if not NAME then NAME = "aolotto" end
if not VERSION then VERSION = "dev" end
if not TOKEN then TOKEN = {
  Ticker="ALT",
  Process="zQ0DmjTbCEGNoJRcjdwdZTHt0UBorTeWbb_dnc6g41E",
  Denomination=3,
  Name="AolottoToken"
} end
if not SHOOTER then SHOOTER = _config.SHOOTER end
if not OPERATOR then OPERATOR = _config.OPERATOR end
if not ARCHIVER then ARCHIVER = _config.ARCHIVER end

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


--[[
  轮次
]]
if not CURRENT then CURRENT = {
  bets={},
  logs={},
  statistics={},
  no="1",
  duration = 86400000,
  start_time = Inbox[1].Timestamp,
  base_rewards = 0,
  bets_count=0,
  status = 0,
  bets_amount = 0,
  participants = 0,
  end_time = nil,
} end
setmetatable(CURRENT,{__index=require("modules.current")})

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
if not ARCHIVES then ARCHIVES = {archiver = ARCHIVER,repo={}} end
setmetatable(ARCHIVES,{__index=require("modules.archives")})

--[[
  退款记录
]]
if not REFUNDS then REFUNDS = {logs={}} end
setmetatable(REFUNDS,{__index=require("modules.refund")})


--[[ 
  投注接口 
]]

Handlers.add(
  '_credit_bet',
  function (msg)
    if msg.From == TOKEN.Process and msg.Tags.Action == "Credit-Notice" then
      return true
    else
      return false
    end
  end,
  function (msg)

    xpcall(function (msg)
      
      assert(type(msg.Quantity) == 'string', 'Quantity is required!')
      assert(msg.Sender ~= OPERATOR, "Operator is not available on betting")

      -- 如过当前不在运行状态，突患用户款项
      if STATE.run ~= 1 then REFUNDS:rejectToken(msg) return end

      -- 判断是否为当前轮次的新参与者
      local participated = CURRENT:isParticipated(msg)
      -- 消息转换为投注
      local bets = TOOLS:messageToBets(msg)
      -- 保存投注
      CURRENT:saveBets(bets,msg)
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
        participation_rounds = TOOLS:getParticipationRoundStr(user.participation_rounds,CURRENT.no)
      }
      USERS:replaceUserInfo(userInfo)

      -- -- 增加奖池总额
      STATE:increasePoolBalance(msg.Quantity)
      STATE:increaseOperatorBalance(msg.Quantity)
      

      -- 下发消息
      local data_str = ""
      if msg.Donee then
        data_str = string.format("Placed %d bet%s for '%s' on aolotto Round %s , with the numbers: %s",
          msg.Quantity, tonumber(msg.Quantity)>1 and "s" or "" , msg.Donee , CURRENT.no , json.encode(bets) )
      else
        data_str = string.format("Placed %d bet%s on aolotto Round %s , with the numbers: %s",
          msg.Quantity , tonumber(msg.Quantity)>1 and "s" or "", CURRENT.no , json.encode(bets) )
      end
      local message = {
        Target = msg.Sender,
        Action = const.Actions.lotto_notice,
        Data = data_str,
        Quantity = msg.Quantity,
        Round = tostring(CURRENT.no),
        Token = msg.From,
        ["Pushed-For"] = msg.Tags["Pushed-For"],
        [const.Actions.x_numbers] = msg.Tags[const.Actions.x_numbers]
      }
      if msg.Donee then
        message['Donee'] = msg.Donee
      end
      ao.send(message)

      -- 触发轮次结束
      local amount_reached = CURRENT.bets_amount >= CURRENT.base_rewards
      local time_reached = msg.Timestamp >= (CURRENT.start_time + CURRENT.duration)
      if amount_reached and time_reached then
        ao.send({Target=ao.id,Action=const.Actions.finish,Round=tostring(CURRENT.no)})
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
      assert(CURRENT.bets_amount >= CURRENT.base_rewards, "amount not reached")
      assert(msg.Timestamp >= (CURRENT.start_time + CURRENT.duration), "amount not reached")
      local archive = CURRENT:archive(msg.Timestamp)
      ARCHIVES:add(archive)
      -- 重置轮次信息
      CURRENT:new(msg.Timestamp)
      -- 触发抽奖
      ao.send({Target=ao.id, Action="Draw",Round=tostring(archive.no)})
    end,function (err)
      print(err)
    end,msg)
  end
)

-- [[ 开奖 ]]

Handlers.add(
  "_draw",
  function (msg)
    local is_operator = msg.From == OPERATOR or msg.From == ao.id
    if is_operator and msg.Tags.Action == "Draw" then return true else return false end
  end,
  function(msg)
    xpcall(function (msg)
      assert(msg.Tags.Round~=nil,"missd Round tag")
      local bets_amount = ARCHIVES.repo[msg.Tags.Round] and ARCHIVES.repo[msg.Tags.Round].bets_amount or 0
      local bets = {}
      if ARCHIVES.repo[msg.Tags.Round] then
        bets_amount = ARCHIVES.repo[msg.Tags.Round].bets_amount
        bets = ARCHIVES.repo[msg.Tags.Round].bets
      end
      local win_num = TOOLS:getRandomNumber( string.format("%s_%d_%d",msg.Tags.Round, msg.Timestamp, bets_amount ),3)
      local winners, rewards = ARCHIVES:draw(msg.Tags.Round, win_num)
      if rewards > 0 then
        if #winners > 0 then
          USERS:increaseWinnersRewardBalance(winners, msg.Timestamp)
          for key, winner in pairs(winners) do
            TOOLS:sendWinNotice(msg.Tags.Round,winner,TOKEN)
          end
        else
          USERS:increaseAllRewardBalance(rewards, msg.Timestamp)
        end
      else
        REFUNDS:refundToParticipantInBets( bets,TOKEN.process)
      end
    end,function (err)
      print(err)
    end,msg)
  end
)



--[[ 更新归档 ]]

Handlers.add(
  "op.archive_round",
  function (msg)
    if msg.Tags.Action == const.Actions.archive_round then
      return msg.From == OPERATOR or msg.From == ao.id
    else
      return false
    end  
  end,
  function (msg)
    xpcall(function (msg)
      print("archive start")
      assert(msg.Tags.Round ~= nil, "missed round tag.")
      assert(msg.Tags.Archiver ~= nil, "missed archiver tag.")
      local archive = ARCHIVES.repo[tostring(msg.Tags.Round)]
      if archive then
        assert(archive.archived == nil or  archive.archived == false,"already archived.")
        ao.send({
          Target = msg.Tags.Archiver,
          Action = const.Actions.archive_round,
          Round = msg.Tags.Round,
          Data = json.encode(archive)
        })
        ARCHIVES.repo[msg.Tags.Round].archiver = msg.Tags.Archiver
      end
    end,function (err)
      print(err)
    end,msg)
  end
)


Handlers.add(
  "_round_archived",
  function (msg)
    if msg.Tags.Action == const.Actions.round_archived and msg.Tags.Round then return true else return false end
  end,
  function (msg)
    xpcall(function (msg)
      assert(ARCHIVES.repo[tostring(msg.Tags.Round)].archiver == msg.From,"archiver are not martched.")
      ARCHIVES:removeRawData(msg.Tags.Round)
    end,function (err)
      print(err)
    end,msg)
  end
)



-- --[[ 查询当前或指定轮次的信息 ]]

-- Handlers.add(
--   "getRoundInfo",
--   Handlers.utils.hasMatchingTag("Action",const.Actions.get_round_info),
--   function (msg)
--     xpcall(function (msg)
--       local request_type = msg.Tags[const.Actions.request_type] or ""
--       local key = msg.Round or tostring(ROUNDS.current)
--       local round = ROUNDS:get(key)
--       assert(round ~= nil,"The round did not exists")
--       local str = ""
--       if request_type == "json" then
--         str = json.encode(round)
--       else
--       local state_str = const.RoundStatus[round.status]
--       local start_date_str = TOOLS:timestampToDate(round.start_time,"%Y/%m/%d %H:%M")
--       local end_date_str = TOOLS:timestampToDate(round.end_time or round.start_time+round.duration,"%Y/%m/%d %H:%M")
--       local total_prize = TOOLS:toBalanceValue(round.base_rewards + (round.bets_amount or 0))
--       local participants_str = tostring(round.participants or 0)
--       local base_str = tostring(round.base_rewards)
--       local bets_str = tostring(round.bets_amount or 0)
--       local winners_str = tostring(round.winners_count or 0)
--       local tips_str = round.status ~= 0 and string.format("Drawn on %s UTC, %s winners.",end_date_str,winners_str) or string.format("draw on %s UTC if bets >= %s",end_date_str,base_str)

--       str=  string.format([[

--     -----------------------------------------      
--     aolotto Round %d - %s
--     ----------------------------------------- 
--     * Total Prize:       %s %s
--     * Participants:      %s
--     * Bets:              %s
--     * Start at:          %s UTC
--     ----------------------------------------- 
--     %s

--         ]],tonumber(key),state_str,total_prize,TOKEN.Ticker or "AO",participants_str,bets_str,start_date_str,tips_str)
--       end
--       local message = {
--         Target = msg.From,
--         Data = str,
--         Action = "Reply-RoundInfo",
--       }
--       ao.send(message)
        
--     end,function (err)
--       print(err)
--       TOOLS:sendError(err,msg.From)
--     end,msg)
--   end
-- )

--[[ 用户查询当前或指定轮次的下注信息 ]]

Handlers.add(
  'fetchBets',
  Handlers.utils.hasMatchingTag("Action",const.Actions.bets),
  function (msg)
    xpcall(function (msg)

      local target_round = nil
      if msg.Round == nil or msg.Round == CURRENT.no then
        target_round = CURRENT
      else
        target_round = ARCHIVES.repo[msg.Round]
      end
      assert(target_round~=nil,"The round is not exists")
      
      if target_round.archived then
        print("归档转发--> "..target_round.archiver)
        assert(target_round.archiver~=nil,"no archiver process for your query.")
        ao.assign({
          Processes = { target_round.archiver },
          Message = msg.Id
        })
      else
        local user_bets = target_round.bets[msg.From]
        assert(user_bets~=nil, "no bets you pleaced in this round.")
        messenger:replyUserBets(msg.From,{
          user_bets = user_bets,
          request_type = msg.RequestType or "",
          no = target_round.no
        })
      end

    end,function (err)
      print(err)
      TOOLS:sendError(err,msg.From)
    end,msg)
  end
)

-- -- [[ 查询用户的信息 ]]

-- Handlers.add(
--   "getUserInfo",
--   Handlers.utils.hasMatchingTag("Action", const.Actions.user_info),
--   function (msg)
--     xpcall(function (msg)
--       local user = USERS:queryUserInfo(msg.From)
--       assert(user ~= nil, "User not exists.")
--       local request_type = msg[const.Actions.request_type] or ""
--       local data_str = ""
--       if user then
--         if request_type == "json" then
--           local json = json or require("json")
--           data_str = json.encode(user)
--         else
--           data_str = string.format([==[
--   %s
--   -------------------------------------------
--   * Number of Wins :   %d
--   * Rewards Balance :  %s %s
--   * Total Rewards :    %s %s
--   * Bets Amount :      %d
--   * Bets Placed :      %d
--   -------------------------------------------
--   First bet on %d
--           ]==],user.id, user.total_rewards_count, TOOLS:toBalanceValue(user.rewards_balance),TOKEN.Ticker, TOOLS:toBalanceValue(user.total_rewards_amount),TOKEN.Ticker, user.bets_amount,user.bets_count,user.create_at)
--         end  
--       end
--       local msssage = {
--         Target = msg.From,
--         Action = const.Actions.reply_user_info,
--         Data = data_str
--       }
--       ao.send(msssage)
--     end,function (err)
--       TOOLS:sendError(err,msg.From)
--     end,msg)
--   end
-- )


-- -- [[ 领取奖金 ]]

-- Handlers.add(
--   "claim",
--   Handlers.utils.hasMatchingTag("Action", const.Actions.claim),
--   function (msg)
--     xpcall(function (msg)
--       local user = USERS:queryUserInfo(msg.From)
--       assert(user ~= nil,"User not exists")
--       local err_str = string.format("Rewards balance is below the claim threshold of %s %s.",TOOLS:toBalanceValue(100),TOKEN.Ticker)
--       assert(user.rewards_balance and user.rewards_balance >= 100,err_str)
--       local TOKEN_PROCESS = TOKEN.Process or "Sa0iBLPNyJQrwpTTG-tWLQU-1QeUAJA73DdxGGiKoJc"
--       local qty =  math.floor(user.rewards_balance * ((1-TAX_RATE) or 0.9))
--       local message = {
--         Target = TOKEN_PROCESS,
--         Action = "Transfer",
--         Recipient = msg.From,
--         Quantity = tostring(qty),
--         [const.Actions.x_transfer_type] = const.Actions.claim,
--         [const.Actions.x_amount] = tostring(user.rewards_balance),
--         [const.Actions.x_tax] = tostring(TAX_RATE),
--         [const.Actions.x_pushed_for] = msg["Pushed-For"]
--       }
--       ao.send(message)
--     end,function (err)
--       print(err)
--       TOOLS:sendError(err,msg.From) 
--     end,msg)
--   end
-- )


-- -- [[ 奖金下发后更新奖金余额 ]]

-- Handlers.add(
--   "_debit_claim",
--   function (msg)
--     local triggered = msg.From == TOKEN.Process and msg.Tags.Action == "Debit-Notice" and msg.Tags[const.Actions.x_transfer_type] == const.Actions.claim
--     if triggered then return true else return false end
--   end,
--   function (msg)
--     xpcall(function (msg)
--       local user = USERS:queryUserInfo(msg.Recipient)
--       assert(user~=nil,"User is not exists")
--       user.rewards_balance = math.max(user.rewards_balance - tonumber(msg.Quantity),0)
--       user.update_at = msg.Timestamp
--       USERS:replaceUserInfo(user)
--       -- 减少奖池总额
--       STATE:decreasePoolBalance(msg.Quantity)
--       -- 增加奖励总额
--       STATE:increaseClaimPaid(msg.Quantity)
--     end,function (err)
--       print(err)
--       TOOLS:sendError(err,OPERATOR)
--     end,msg)
--   end
-- )

-- -- [[ 运营方提现 ]]
-- Handlers.add(
--   "OP.withdraw",
--   function(msg) 
--     if msg.From == OPERATOR and msg.Action == const.Actions.OP_withdraw then return true else return false end
--   end,
--   function (msg)
--     xpcall(function (msg)
--       local TOKEN_PROCESS = msg.Tags.Token or TOKEN.Process
--       local is_rewards_token = TOKEN_PROCESS == TOKEN.Process
--       if is_rewards_token then
--         assert(math.floor(STATE.operator_balance) >= 1, "Insufficient withdrawal amount")
--         local message = {
--           Target = TOKEN_PROCESS,
--           Quantity = tostring(math.floor(STATE.operator_balance)),
--           Recipient = msg.From,
--           Action = "Transfer",
--           [const.Actions.x_transfer_type] = const.Actions.OP_withdraw,
--           [const.Actions.x_pushed_for] = msg["Pushed-For"]
--         }
--         ao.send(message)
--       else
--         local message = {
--           Target = TOKEN_PROCESS,
--           Quantity = msg.Tags.Quantity or "",
--           Recipient = msg.From,
--           Action = "Transfer"
--         }
--         ao.send(message)
--       end
      
--     end,function (err)
--       print(err)
--       TOOLS:sendError(err,msg.From)
--     end,msg)
--   end
-- )
-- Handlers.add(
--   "OP._debit_op_withdraw",
--   function (msg)
--     local triggered = msg.From == TOKEN.Process and msg.Tags.Action == "Debit-Notice" and msg.Tags[const.Actions.x_transfer_type] == const.Actions.OP_withdraw
--     if triggered then return true else return false end
--   end,
--   function (msg)
--     xpcall(function (msg)
--       STATE:decreaseOperatorBalance(msg.Quantity)
--       STATE:decreasePoolBalance(msg.Quantity)
--       STATE:increaseWithdraw(msg.Quantity)
--     end,function (err)
--       print(err)
--       TOOLS:sendError(err,OPERATOR)
--     end,msg)
--   end
-- )

-- --[[ 运营方管理 ]]
-- Handlers.add(
--   "OP.changeShooter",
--   function(msg)
--     if msg.From == OPERATOR and msg.Tags.Action == const.Actions.change_shooter then return true else return false end
--   end,
--   function(msg)
--     xpcall(
--       function(msg)
--         print("改变触发器")
--         assert(msg.Shooter ~= nil ,"Missed shooter tag." )
--         SHOOTER = msg.Shooter
--       end,
--       function(err)
--         print(err)
--         TOOLS:sendError(err,msg.From)
--       end,
--       msg
--     )
--   end
-- )

-- Handlers.add(
--   "OP.changeArchiver",
--   function(msg)
--     if msg.From == OPERATOR and msg.Tags.Action == const.Actions.change_archiver then return true else return false end
--   end,
--   function(msg)
--     xpcall(
--       function(msg)
--         assert(msg.Archiver ~= nil ,"Missed Archiver tag." )
--         ARCHIVER = msg.Archiver
--       end,
--       function(err)
--         print(err)
--         TOOLS:sendError(err,msg.From)
--       end,
--       msg
--     )
--   end
-- )

-- Handlers.add(
--   "OP.pause",
--   function(msg)
--     if msg.From == OPERATOR and msg.Tags.Action == const.Actions.pause_round then return true else return false end
--   end,
--   function(msg)
--     xpcall(
--       function(msg)
--         STATE:set("run",0)
--         STATE:set("pause_start",msg.Timestamp)
--       end,
--       function(err)
--         print(err)
--         TOOLS:sendError(err,msg.From)
--       end,
--       msg
--     )
--   end
-- )

-- Handlers.add(
--   "OP.restart",
--   function(msg)
--     if msg.From == OPERATOR and msg.Tags.Action == const.Actions.round_restart then return true else return false end
--   end,
--   function(msg)
--     xpcall(
--       function(msg)
--         STATE:set("run",1)
--         STATE:set("pause_end",msg.Timestamp)
--       end,
--       function(err)
--         print(err)
--         TOOLS:sendError(err,msg.From)
--       end,
--       msg
--     )
--   end
-- )


-- [[ 开奖触发器 ]]

Handlers.add(
  "_shoot",
  function (msg)
    if msg.From == SHOOTER and msg.Action == const.Actions.shoot then return true else return false end
  end,
  function (msg)
    assert(msg.Timestamp >= CURRENT.start_time + CURRENT.duration, "Time not reached." )
    local expired = (CURRENT.start_time or 0) + (CURRENT.duration*7)
    if expired or CURRENT.bets_amount >= CURRENT.base_rewards then
      Send({
        Target=ao.id,
        Action=const.Actions.finish
      })
    end  
  end
)


-- --[[ 查询历史轮次 ]]

-- Handlers.add(
--   "fetchRounds",
--   Handlers.utils.hasMatchingTag("Action",const.Actions.rounds),
--   function (msg)
--     local data_str = ""
--     local request_type = msg[const.Actions.request_type] or ""
--     if request_type == "json" then
--       data_str = json.encode(ROUNDS.repo)
--     else
--       table.sort(ROUNDS.repo,function (a,b) return a.no > b.no end)
--       for i, v in ipairs(ROUNDS.repo) do
--         data_str = data_str..string.format("%4d : %s \n",v.no, v.process)
--       end
--     end
--     local msssage = {
--       Target = msg.From,
--       Action = const.Actions.reply_rounds,
--       Data = data_str
--     }
--     ao.send(msssage)
--   end
-- )



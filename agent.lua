--[[
  *******************
  Global constants and module imports
  *******************
]]--
if not NAME then NAME = ao.env.Process.Tags.Name or "aolotto" end
if not VERSION then VERSION = ao.env.Process.Tags.Version or "dev" end
if not TOKEN then TOKEN = {Ticker="ALT",Process="zQ0DmjTbCEGNoJRcjdwdZTHt0UBorTeWbb_dnc6g41E",Denomination=3,Name="AolottoToken"} end
if not SHOOTER then SHOOTER = ao.env.Process.Tags.Shooter or "7tiIWi2kR_H9hkDQHxy2ZqbOFVb58G4SgQ8wfZGKe9g" end
if not OPERATOR then OPERATOR = ao.env.Process.Tags.Operator or "-_hz5V_I73bHVHqKSJF_B6cDBBSn8z8nPEUGcViTYko" end
if not ROUND_DUR then ROUND_DUR = tonumber(ao.env.Process.Tags.Duration) or 86400000 end
if not CURRENT_ROUND then CURRENT_ROUND = 1 end
if not RUN then RUN = 1 end 
if not POOL_BALANCE then POOL_BALANCE = 0 end
if not TOTAL_POOL_BALANCE then TOTAL_POOL_BALANCE = 0 end
if not OPERATOR_BALANCE then OPERATOR_BALANCE = 0 end
if not TOTAL_OPERATOR_BALANCE then TOTAL_OPERATOR_BALANCE = 0 end
if not TAX_RATE then TAX_RATE = 0.05 end
if not TOTAL_WITHDRAW then TOTAL_WITHDRAW = {} end
if not TOTAL_CLAIM_PAID then TOTAL_CLAIM_PAID = 0 end
if not CONST then CONST = {} end


CONST.Actions = {
  lotto_notice = "Lotto-Notice",
  finish = "Finish",
  archive_round = "Archive-Round",
  round_spawned = "Round-Spawned",
  reply_rounds ="Reply-Rounds",
  bets = "Bets",
  reply_user_bets = "Reply-UserBets",
  reply_user_info = "Reply-UserInfo",
  user_info = "UserInfo",
  claim = "Claim",
  OP_withdraw = "OP_withdraw",
  x_transfer_type = "X-Transfer-Type"
}

CONST.RoundStatus = {
  [-1] = "Canceled",
  [0] = "Ongoing",
  [1] = "Ended"
}
CONST.ErrorCode = {
  default = "400",
  transfer_error = "Transfer-Error"
}

ao.authorities = {OPERATOR,SHOOTER,ao.id}

sqlite3 = require("lsqlite3")
crypto = require(".crypto")
utils = require(".utils")
json = require("json")
bint = require('.bint')(256)

--[[
  *******************
  Initialize the database to store user information。
  *******************
]]--

if not db then db = sqlite3.open_memory() end
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

--[[
  全局状态
]] --
if not STATE then STATE = {} end

--[[
  投注统计
]] --

if not BET then BET = {} end
setmetatable(BET,{__index=require("modules.bet")})



--[[
  轮次
]]
if not ROUNDS then ROUNDS = {} end

function ROUNDS:create(no,timestamp)
  if not self[no] then
    local pre = tonumber(no) > 1 and self[tostring(tonumber(no)-1)] or nil
    local base_rewards = pre and math.floor((pre.base_rewards + pre.bets_amount)*0.5) or 0
    self[no] = {
      no = no,
      base_rewards = base_rewards,
      bets_amount = 0,
      bets_count = 0,
      start_time = timestamp,
      status = 0,
      duration = ROUND_DUR
    }
    if pre then
      pre.end_time = timestamp
      pre.status = timestamp <= pre.start_time+(pre.duration*7) and 1 or -1
    end
  end
  return self[no]
end

function ROUNDS:set(no,data)
  self[no] = data
end

function ROUNDS:get(no)
  return self[no]
end

function ROUNDS:draw(archive,timestamp)
  local no = tostring(archive.round.no)
  local round = archive.round
  local rewards = math.floor((round.base_rewards + round.bets_amount)*0.5)
  -- 构建抽奖结果表
  local draw_info = {}
  draw_info.round = no
  draw_info.raw_round_data = round
  draw_info.timestamp = timestamp
  draw_info.rewards = rewards
  -- 获取随机抽奖号
  local seed = string.format("seed_%s_%d_%d_%d",no,timestamp,round.bets_amount,round.bets_count)
  local win_num = TOOLS:getRandomNumber(seed,3)
  draw_info.win_num = win_num
  -- 统计获奖者
  local winners = {}
  for key, value in pairs(archive.bets) do
    if value.numbers[win_num] then
        table.insert(winners, {
          id = key,
          amount = value.numbers[win_num]
        })
    end
  end
  draw_info.winners = winners
  -- 统计获奖者的奖金比例
  if #winners > 0 then
    local utils = utils or require(".utils")
    local total = utils.reduce(function (acc, v) return acc + v end)(0)(utils.map(function (val) return val.amount end)(winners))
    local per = math.floor(rewards/total)
    draw_info.total_win_bets = total
    draw_info.per_reward = per
    utils.map(function (v, key)
      v["percent"] = v.amount / total
      v["rewards"] = math.floor(v.amount * per)
      v["matched"] = win_num
    end,winners)
  else
    draw_info.total_win_bets = 0
  end
  -- 更改轮次状态
  self[no].drawn = true
  self[no].winners_count = #winners
  self[no].total_win_bets = draw_info.total_win_bets or 0
  self[no].win_num = win_num
  self[no].status = 1
  -- 增加奖金锁定
  return draw_info, rewards
end


function ROUNDS:refundToken(msg)
  assert(msg.Sender ~= nil, "Missed Sender.")
  assert(msg.Quantity ~= nil and tonumber(msg.Quantity) > 0, "Missed Quantity.")
  local message = {
    Target = msg.From,
    Action = "Transfer",
    Recipient = msg.Sender,
    Quantity = msg.Quantity,
    [CONST.Actions.x_transfer_type] = "Refund"
  }
  ao.send(message)
end


--[[
  工具
]]
if not TOOLS then TOOLS = {} end

function TOOLS:sendError (err,target,code)
  local red = "\027[31m"
  local reset = "\027[0m"
  ao.send({
    Target=target,
    Action="Error",
    Error = code or CONST.ErrorCode.default,
    Data=red..tostring(err)..reset
  })
end

function TOOLS:getRandomNumber(seed,len)
  local crypto  = crypto or require(".crypto")
  local numbers = ""
  for i = 1, len or 3 do
    local r = crypto.cipher.issac.getRandom()
    local n = crypto.cipher.issac.random(0, 9, tostring(i)..seed..tostring(r))
    numbers = numbers .. n
  end
  return numbers
end

function TOOLS:parseStringToBets(str, limit)
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

function TOOLS:getParticipationRoundStr (str)
  local json = json or require("json")
  local tbl = str and json.decode(str) or {}
  local utils = utils or require(".utils")
  if not utils.includes(CURRENT_ROUND,tbl) then
    table.insert(tbl,CURRENT_ROUND)
  end
  return json.encode(tbl)
end


function TOOLS:timestampToDate (timestamp, format)
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


function TOOLS:toBalanceValue(v)
  local precision = TOKEN.Denomination or 3
  return string.format("%." .. precision .. "f", v / 10^precision)
end


--[[
  用户
]]

if not USERS then USERS = { db_name ="users" } end

function USERS:checkUserExist(id)
  local select_str = string.format("SELECT 1 FROM %s WHERE id = '%s'",self.db_name, id)
  local rows = {}
  for row in db:nrows(select_str) do table.insert(rows,row) end
  return #rows > 0
end

function USERS:queryUserRewardsBalance(id)
  if not id then return end
  local sql = string.format("SELECT rewards_balance FROM %s WHERE id = '%s'",self.db_name, id)
  local rows = {}
  for row in db:nrows(sql) do
    table.insert(rows,row[1] or 0)
  end
  local result = 0
  if #rows > 0 then
    result = rows[1]
  end
  return result
end

function USERS:queryUserInfo(id)
  if not id then return end
  local sql = string.format("SELECT * FROM %s WHERE id = '%s'",self.db_name, id)
  local rows = {}
  for row in db:nrows(sql) do
    table.insert(rows,row)
  end
  if #rows > 0 then return rows[1] else return nil end
end


function USERS:replaceUserInfo(user)
  local sql = string.format([[ 
    REPLACE INTO users (id, bets_count, bets_amount, rewards_balance, total_rewards_count, total_rewards_amount, participation_rounds, create_at, update_at)
    VALUES ('%s',%d,%d,%f,%d,%f,'%s',%d,%d)
  ]],
  user.id, user.bets_count, user.bets_amount, user.rewards_balance, user.total_rewards_count, user.total_rewards_amount, user.participation_rounds, user.create_at, user.update_at
  )
  db:exec(sql)
end

function USERS:countUserTotalBetsAmount ()
  local sql = string.format("SELECT SUM(bets_amount) FROM users")
  local stmt = db:prepare(sql)
  stmt:step()
  local total = stmt:get_value(0)
  stmt:finalize()
  return total
end

function USERS:queryAllUsers()
  local sql = string.format("SELECT * FROM users")
  local rows = {}
  for row in db:nrows(sql) do
    table.insert(rows,row)
  end
  return rows
end

function USERS:shareRewardsToAll (rewards,timestamp)
  local all = self:countUserTotalBetsAmount()
  local per_share = rewards/all
  local sql = string.format("UPDATE %s SET rewards_balance = rewards_balance + bets_amount * %.3f,total_rewards_amount = total_rewards_amount + bets_amount * %.3f, total_shared_count=total_shared_count+1, update_at = %d",self.db_name,per_share,per_share,timestamp)
  db:exec(sql)
end


function USERS:shareRewardsToWinners (winners,timestamp)
  local utils =  utils or require(".utils")
  utils.map(function (val, key)
    local sql = string.format("UPDATE %s SET rewards_balance = rewards_balance + %.3f , total_rewards_amount = total_rewards_amount + %.3f, total_rewards_count = total_rewards_count + 1, update_at = %d WHERE id == '%s'",self.db_name,val.rewards,val.rewards,timestamp,val.id)
    db:exec(sql)
  end,winners)
end


--[[ 投注 ]]

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
      if RUN ~= 1 then ROUNDS:refundToken(msg) end
      assert(RUN == 1, string.format("Aolotto is not accepting bets %s.",RUN == 0 and "now" or "forever"))
      assert(msg.Sender ~= OPERATOR, "Operator is not available on betting")
      if not ROUNDS[tostring(CURRENT_ROUND or 1)] then
        ROUNDS:create(tostring(CURRENT_ROUND or 1),msg.Timestamp)
      end
      CURRENT_ROUND = CURRENT_ROUND or 1
      local numbers_str = msg.Tags["X-Numbers"] or TOOLS:getRandomNumber(msg.Id,3)
     
      local bet_tbl = TOOLS:parseStringToBets(numbers_str,tonumber(msg.Quantity))
      if not bet_tbl then
        local key = TOOLS:getRandomNumber(msg.Id,3)
        bet_tbl = {}
        bet_tbl[key] = tonumber(msg.Quantity)
      end
      local bets = {}
      for key, value in pairs(bet_tbl) do
        table.insert(bets,{key,value})
      end

      -- 保存投注记录
      BET:save(bets,msg)
      BET:log(bets,msg)
      -- BET_LOGS:push(bets,msg)
      
      -- 更新用户数据
      local user = USERS:queryUserInfo(msg.Sender)
      if not user then
        -- 添加Sender到信任列表
        table.insert(ao.authorities,msg.Sender)
        user = {}
      end
      local userInfo = {
        id = user.id or msg.Sender,
        bets_count = user.bets_count and (user.bets_count + 1) or 1,
        bets_amount = user.bets_amount and (user.bets_amount+tonumber(msg.Quantity)) or tonumber(msg.Quantity),
        rewards_balance = user.rewards_balance or 0,
        total_rewards_count = user.total_rewards_count or 0,
        total_rewards_amount = user.total_rewards_amount or 0,
        create_at = user.create_at or msg.Timestamp,
        update_at = msg.Timestamp,
        participation_rounds = TOOLS:getParticipationRoundStr(user.participation_rounds)
      }
      USERS:replaceUserInfo(userInfo)
      -- 更新全局数据
      
      local target_round = ROUNDS[tostring(CURRENT_ROUND)]
      if target_round then
        target_round.bets_count = target_round.bets_count + 1
        target_round.bets_amount = target_round.bets_amount + tonumber(msg.Quantity)
        ROUNDS:set(tostring(CURRENT_ROUND),target_round)
      end
      

      -- 下发消息
      local json = json or require("json")
      local data_str = ""
      if msg.Donee then
        data_str = string.format("Placed %d bet%s for '%s' on aolotto Round %d , with the numbers: %s",
          msg.Quantity, tonumber(msg.Quantity)>1 and "s" or "" , msg.Donee , CURRENT_ROUND , json.encode(bets) )
      else
        data_str = string.format("Placed %d bet%s on aolotto Round %d , with the numbers: %s",
          msg.Quantity , tonumber(msg.Quantity)>1 and "s" or "", CURRENT_ROUND , json.encode(bets) )
      end


      local message = {
        Target = msg.Sender,
        Action = CONST.Actions.lotto_notice,
        Data = data_str,
        Quantity = msg.Quantity,
        Round = tostring(CURRENT_ROUND),
        Token = msg.From,
        ["aolotto"] = ao.id,
        ["Pushed-For"] = msg.Tags["Pushed-For"],
        ["X-Numbers"] = msg.Tags["X-Numbers"]
      }
      if msg.Donee then
        message['Donee'] = msg.Donee
      end
      ao.send(message)

      -- 增加奖池总额
      POOL_BALANCE = (POOL_BALANCE or 0) + tonumber(msg.Quantity)
      TOTAL_POOL_BALANCE = (TOTAL_POOL_BALANCE or 0)  + tonumber(msg.Quantity)
      -- 增加运营方1%提现额
      OPERATOR_BALANCE = (OPERATOR_BALANCE or 0) + tonumber(msg.Quantity) * TAX_RATE
      TOTAL_OPERATOR_BALANCE = (TOTAL_OPERATOR_BALANCE or 0)  + tonumber(msg.Quantity) * TAX_RATE

     
      -- 触发轮次结束
     
      if target_round.bets_amount >= target_round.base_rewards and msg.Timestamp >= (target_round.start_time + target_round.duration or ROUND_DUR) then
        print("Time to ended "..tostring(target_round.no))
        Send({Target=ao.id,Action=CONST.Actions.finish,Round=tostring(target_round.no)})
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
    if ao.isTrusted(msg) and msg.Tags.Action == "Finish" then return true else return false end
  end,
  function (msg)
    xpcall(function (msg)
      
      local no = msg.Round and tonumber(msg.Round) or CURRENT_ROUND
      local round = ROUNDS[tostring(no)]
      print(round)
      assert(round.drawn == nil or round.drawn == false,"The round has been drawn.")
      assert(round.status == 0,"The round has been finished.")
      local expired = (round.start_time or 0) + (round.duration*7)
      assert(msg.Timestamp >= round.start_time+round.duration and msg.Timestamp < expired,"Time has not yet reached.")
      assert(round.bets_amount>=round.base_rewards and msg.Timestamp < expired, "The betting amount has not reached.")
      ROUNDS:create(tostring(no+1),msg.Timestamp)
      CURRENT_ROUND = no+1
      -- 开奖
      local archive = BET:archive(no)
      local draw_info, rewards = ROUNDS:draw(archive,msg.Timestamp)
      archive.draw_info = draw_info

      -- 处理抽奖结果
      if draw_info.winners and #draw_info.winners>0 then
        USERS:shareRewardsToWinners(draw_info.winners,msg.Timestamp)
      else
        USERS:shareRewardsToAll(rewards,msg.Timestamp)
      end
      -- 把轮次归档发送给运营者
      local json = json or require("json")
      local message = {
        Target=OPERATOR,
        Action=CONST.Actions.archive_round,
        Data=json.encode(archive)
      }
      ao.send(message)
    end,function (err)
      print(err)
      TOOLS:sendError(err,msg.From)
    end,msg)
  end
)

--[[ 更新轮次查询进程 ]]

Handlers.add(
  "_round_spawned",
  function (msg)
    if msg.From == OPERATOR and msg.Tags.Action == CONST.Actions.round_spawned and msg.Tags.Round then  return true else return false end
  end,
  function (msg)
    ROUNDS[msg.Tags.Round].process = msg.Tags.ProcessID
  end
)

--[[ 查询历史轮次 ]]

Handlers.add(
  "fetchRounds",
  Handlers.utils.hasMatchingTag("Action","Rounds"),
  function (msg)
    local json = json or require("json")
    local data_str = ""
    local request_type = msg.RequestType or ""
    if request_type == "json" then
      data_str = json.encode(ROUNDS)
    else
      table.sort(ROUNDS,function (a,b) return a.no > b.no end)
      for i, v in ipairs(ROUNDS) do
        data_str = data_str..string.format("%4d : %s \n",v.no, v.process)
      end
    end
    local msssage = {
      Target = msg.From,
      Action = CONST.Actions.reply_rounds,
      Data = data_str
    }
    ao.send(msssage)
  end
)

--[[ 查询当前或指定轮次的信息 ]]

Handlers.add(
  "getRoundInfo",
  Handlers.utils.hasMatchingTag("Action","GetRoundInfo"),
  function (msg)
    xpcall(function (msg)
      local request_type = msg.RequestType or ""
    local key = msg.Round or tostring(CURRENT_ROUND)
    local round = ROUNDS[key]
    assert(round ~= nil,"The round did not exists")
    local str = ""
    if request_type == "json" then
      local json = json or require("json")
      str = json.encode(round)
    else
      local state_str = CONST.RoundStatus[round.status]
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
  Handlers.utils.hasMatchingTag("Action",CONST.Actions.bets),
  function (msg)
    xpcall(function (msg)
      local json = json or require("json")
      local key = msg.Round or tostring(CURRENT_ROUND)
      local is_current_round = key == tostring(CURRENT_ROUND) 
      local round = ROUNDS[key]
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
          data_str = string.format([[You've placed %d bets that cover %d numbers on Round %d : ]],total_bets,total_numbers,CURRENT_ROUND)..bets_str
        else
          data_str = string.format("You don't have any bets on aolotto Round %d.",CURRENT_ROUND)
        end
        local message = {
          Target = msg.From,
          Action = CONST.Actions.reply_user_bets,
          Data = (request_type == "json") and json.encode(user_bets.numbers) or data_str
        }
        ao.send(message)
      else
        local message = {
          Target = round.process,
          Action = CONST.Actions.bets,
          User = msg.From
        }
        if msg.RequestType then
          message["RequestType"] = msg.RequestType
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
  Handlers.utils.hasMatchingTag("Action", CONST.Actions.user_info),
  function (msg)
    xpcall(function (msg)
      local user = USERS:queryUserInfo(msg.From)
      assert(user ~= nil, "User not exists.")
      local request_type = msg.RequestType or ""
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
        Action = CONST.Actions.reply_user_info,
        Data = data_str
      }
      ao.send(msssage)
    end,function (err)
      sendError(err,msg.From)
    end,msg)
  end
)


-- [[ 领取奖金 ]]

Handlers.add(
  "claim",
  Handlers.utils.hasMatchingTag("Action", CONST.Actions.claim),
  function (msg)
    xpcall(function (msg)
      local user = USERS:queryUserInfo(msg.From)
      assert(user ~= nil,"User not exists")
      local err_str = string.format("Rewards balance is below the claim threshold of %s %s.",TOOLS:toBalanceValue(100),TOKEN.Ticker)
      assert(user.rewards_balance and user.rewards_balance >= 100,err_str)
      local TOKEN_PROCESS = TOKEN.Process or "Sa0iBLPNyJQrwpTTG-tWLQU-1QeUAJA73DdxGGiKoJc"
      local qty =  math.floor(user.rewards_balance * ((1-TAX_RATE) or 0.05))
      local message = {
        Target = TOKEN_PROCESS,
        Action = "Transfer",
        Recipient = msg.From,
        Quantity = tostring(qty),
        [CONST.Actions.x_transfer_type] = CONST.Actions.claim,
        ["X-Amount"] = tostring(user.rewards_balance),
        ["X-Tax"] = tostring(TAX_RATE),
        ["X-Pushed-For"] = msg["Pushed-For"]
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
  "_debit_rewards",
  function (msg)
    local triggered = msg.From == TOKEN.Process and msg.Tags.Action == "Debit-Notice" and msg.Tags[CONST.Actions.x_transfer_type] == CONST.Actions.claim
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
      POOL_BALANCE = math.max((POOL_BALANCE or 0) - tonumber(msg.Quantity),0)
      -- 增加奖励总额
      TOTAL_CLAIM_PAID = (TOTAL_CLAIM_PAID or 0) + tonumber(msg.Quantity)
    end,function (err)
      print(err)
      TOOLS:sendError(err,OPERATOR)
    end,msg)
  end
)

-- [[ 运营方提现 ]]
Handlers.add(
  "OP.withdraw",
  function (msg)
    if msg.From == OPERATOR and msg.Tags.Action == CONST.Actions.OP_withdraw then return true else return false end
  end,
  function (msg)
    xpcall(function (msg)
      local TOKEN_PROCESS = msg.Tags.Token or TOKEN.Process
      local is_rewards_token = TOKEN_PROCESS == TOKEN.Process
      if is_rewards_token then
        assert(math.floor(OPERATOR_BALANCE) >= 1, "Insufficient withdrawal amount")
        local message = {
          Target = TOKEN_PROCESS,
          Quantity = tostring(math.floor(OPERATOR_BALANCE)),
          Recipient = msg.From,
          Action = "Transfer",
          [CONST.Actions.x_transfer_type] = CONST.Actions.OP_withdraw,
          ["X-Pushed-For"] = msg["Pushed-For"]
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
    local triggered = msg.From == TOKEN.Process and msg.Tags.Action == "Debit-Notice" and msg.Tags[CONST.Actions.x_transfer_type] == CONST.Actions.OP_withdraw
    if triggered then return true else return false end
  end,
  function (msg)
    xpcall(function (msg)
      OPERATOR_BALANCE = math.max((OPERATOR_BALANCE or 0) - tonumber(msg.Quantity),0)
      POOL_BALANCE = math.max((POOL_BALANCE or 0) - tonumber(msg.Quantity),0)
      TOTAL_WITHDRAW = TOTAL_WITHDRAW or {}
      TOTAL_WITHDRAW[msg.From] = (TOTAL_WITHDRAW[msg.From] or 0) + tonumber(msg.Quantity)
    end,function (err)
      print(err)
      TOOLS:sendError(err,OPERATOR)
    end,msg)
  end
)

-- [[ 开奖触发器 ]]

-- Handlers.add(
--   "_shoot",
--   function (msg)
--     if msg.Cron
--   end,
--   function (msg)
    
--   end
-- )


Handlers.add(
  "CronTick",
  Handlers.utils.hasMatchingTag("Action", "Cron"),
  function (msg)
    
    local round = ROUNDS[tostring(CURRENT_ROUND)]
    assert(msg.Timestamp >= round.start_time + round.duration, "时间不满足")
    assert(round.bets_amount >= round.base_rewards and msg.Timestamp <= round.start_time + round.duration * 7,"奖金额度不满足")
    Send({
      Target = ao.id,
      Action = CONST.Actions.finish,
      Round = tostring(CURRENT_ROUND)
    })
  end
)


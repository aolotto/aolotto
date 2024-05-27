CURRENT_ROUND = 1
ROUNDS = {{
    no = 1,
    process = "pgMXPlpSxmp2r6EqIRkpv0M1c7WlRZZm77CoEdUP1VA",
    bets_count = 0,
    bets_amount = 0,
    prize = 0,
    base_awards = 0,
}}
SHOOTER = "7tiIWi2kR_H9hkDQHxy2ZqbOFVb58G4SgQ8wfZGKe9g"

local sqlite3 = require("lsqlite3")
local crypto = require(".crypto")
local bint = require('.bint')(256)
local utils = require(".utils")
local _utils = _utils or require("./utils")
 
db = sqlite3.open_memory()

--[[
  初始化表
]]--
db:exec[[
  CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    bets_count INTEGER,
    bets_amount INTEGER,
    rewards_balance INTEGER,
    total_rewards_amount INTEGER,
    total_rewards_count INTEGER,
    participation_rounds TEXT,
    create_at INTEGER,
    update_at INTEGER
  );

  CREATE TABLE IF NOT EXISTS rounds (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    draw_id TEXT,
    pool_total INTEGER,
    pool_base INTEGER,
    pool_sponsor INTEGER,
    pool_issued INTEGER,
    bets_count INTEGER,
    bets_amount INTEGER,
    users_count INTEGER,
    sponsors_count INTEGER,
    draw_numbers INTEGER,
    state INTEGER,
    started_at INTEGER,
    ended_at INTEGER
  );

  CREATE TABLE IF NOT EXISTS draws (
    id TEXT PRIMARY KEY NOT NULL,
    round_id INTEGER,
    l1_rewarded INTEGER,
    l2_rewarded INTEGER,
    l3_rewarded INTEGER,
    l1_bets_amount INTEGER,
    l2_bets_amount INTEGER,
    l3_bets_amount INTEGER,
    l1_bets_count INTEGER,
    l2_bets_count INTEGER,
    l3_bets_count INTEGER,
    winners_count INTEGER,
    state INTEGER,
    create_at INTEGER,
    update_at INTEGER
  );


  CREATE TABLE IF NOT EXISTS bets (
    id TEXT PRIMARY KEY NOT NULL,
    round_id INTEGER,
    user_id TEXT NOT NULL,
    order_id TEXT NOT NULL,
    draw_id TEXT,
    matched INTEGER,
    numbers INTEGER NOT NULL,
    amount INTEGER NOT NULL,
    create_at INTEGER,
    update_at INTEGER
  );

  CREATE TABLE IF NOT EXISTS orders (
    id TEXT PRIMARY KEY NOT NULL,
    round_id INTEGER,
    user_id TEXT,
    bets_amount INTEGER,
    total_price INTEGER,
    create_at INTEGER,
    update_at INTEGER,
    status INTEGER,
    trans_tx TEXT
  );


  CREATE TABLE IF NOT EXISTS rewards (
    id TEXT PRIMARY KEY NOT NULL,
    round_id INTEGER,
    user_id TEXT,
    bet_id TEXT,
    draw_id TEXT,
    bets_amount INTEGER,
    rewards_amount INTEGER,
    reward_type INTEGER,
    state INTEGER,
    create_at INTEGER,
    update_at INTEGER,
    trans_tx TEXT
  );


  CREATE TABLE IF NOT EXISTS claims (
    id TEXT PRIMARY KEY NOT NULL,
    round_id INTEGER,
    user_id TEXT,
    bet_id TEXT,
    claim_amount INTEGER,
    state INTEGER,
    trans_tx TEXT,
    create_at INTEGER,
    update_at INTEGER
  );

  CREATE TABLE IF NOT EXISTS sponsors (
    id TEXT PRIMARY KEY NOT NULL,
    round_id INTEGER,
    user_address TEXT,
    amount INTEGER,
    avatar INTEGER,
    note TEXT,
    trans_tx TEXT,
    create_at INTEGER,
    update_at INTEGER
  );

]]

sendError = function (err,target)
  ao.send({Target=target,Action="Error",Error=Dump(err),Data="400"})
end


_users = {
  checkUserExist = function (id)
    local select_str = string.format("SELECT 1 FROM %s WHERE id = '%s'",TABLES.users, id)
    local rows = {}
    for row in db:nrows(select_str) do table.insert(rows,row) end
    return #rows > 0
  end
}

_users.queryUserRewardsBalance = function (id)
  if not id then return end
  local sql = string.format("SELECT rewards_balance FROM %s WHERE id = '%s'",TABLES.users, id)
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

_users.queryUserInfo = function (id)
  if not id then return end
  local sql = string.format("SELECT * FROM %s WHERE id = '%s'",TABLES.users, id)
  local rows = {}
  for row in db:nrows(sql) do
    table.insert(rows,row)
  end
  if #rows > 0 then return rows[1] else return nil end
end


_users.replaceUserInfo = function (user)
  local sql = string.format([[ 
    REPLACE INTO users (id, bets_count, bets_amount, rewards_balance, total_rewards_count, total_rewards_amount, participation_rounds, create_at, update_at)
    VALUES ('%s',%d,%d,%d,%d,%d,'%s',%d,%d)
  ]],
  user.id, user.bets_count, user.bets_amount, user.rewards_balance, user.total_rewards_count, user.total_rewards_amount, user.participation_rounds, user.create_at, user.update_at
  )
  print(sql)
  db:exec(sql)
end

_rounds = {}

_rounds.clone = function (options)
  xpcall(function ()
    local round = tostring(CURRENT_ROUND+1)
    local base_rewards = tostring(math.floor((ROUNDS[CURRENT_ROUND].base_rewards + ROUNDS[CURRENT_ROUND].bets_amount)*0.5))
    print(round.."|"..base_rewards)
    ao.spawn(ao._module,{
      Name = "aolotto_round_dev",
      ['Round'] = round,
      ["BaseRewards"] = base_rewards
    })
  end,function (err) print(err) end)
end

_rounds.init_process = function (process)
  local code = string.format([[
    Handlers.add(
      "test",
      Handlers.utils.hasMatchingTag("Action","Test"),
      function(msg) 
        ao.send({Target=msg.From,Action="Tested",Data="%s"}) 
      end
    )
  ]],process)
  ao.send({Target=process,Action="Eval",Data=code})
end

-- 序列化table为字符串
function table2string(t)
  return string.format("%q", table.concat(t, ","))
end

-- 反序列化字符串为table
function string2table(s)
  local t = {}
  for num in string.gmatch(s, "%d+") do
      table.insert(t, tonumber(num))
  end
  return t
end

getParticipationRoundStr = function (str)
  local utils = utils or require("utils")
  local tbl = string2table(str)
  if not utils.includes(CURRENT_ROUND,tbl) then
    table.insert(tbl,CURRENT_ROUND)
    return table2string(tbl)
  else
    return str
  end
end


--[[
  Agent interfaces 
]]--


agentToTargetRound = function (msg,action)
  local utils = utils or require(".utils")
  local no = msg.Round or CURRENT_ROUND or 1
  local target_round = utils.find(function (round) return round.no == no end)(ROUNDS)
  if target_round then
    local message = {
      Target = target_round.process,
      Action = action,
      User = msg.From
    }
    ao.send(message)
  else
    ao.send({Target=msg.From,Data="The Round "..no.." has not started yet."})
  end
end


Handlers.add(
  "getRoundInfo",
  Handlers.utils.hasMatchingTag("Action", "GetRoundInfo"),
  function (msg) agentToTargetRound(msg,"Info") end
)

Handlers.add(
  "fetchUserBets",
  Handlers.utils.hasMatchingTag("Action", "Bets"),
  function (msg) agentToTargetRound(msg,"Bets") end
)

Handlers.add(
  "fetchWinners",
  Handlers.utils.hasMatchingTag("Action", "Winners"),
  function (msg) agentToTargetRound(msg,"Winners") end
)




--[[
  agent自身的接口
]]

Handlers.add(
  "getInfo",
  Handlers.utils.hasMatchingTag("Action", "Info"),
  function (msg)
    local data_str = [[
    aolotto is a lottery game built on theAoComputer, where you can buy bets 
    with three numbers to win the AO's CRED tokens. The draw is held within 
    24 hours.
    -------------------------------------------------------------------------
    * 当前进行轮次: 5
    * 最大奖金额: 400 CRED 
    * 累积参与用户: 3000
  ]]
    local message = {
      Target = msg.From,
      Data = data_str
    }
    ao.send(message)
  end
)

Handlers.add(
  "getUserRewardsBalance",
  Handlers.utils.hasMatchingTag("Action", "RewardsBalance"),
  function (msg)
    xpcall(function (msg)
      local user = _users.queryUserInfo(msg.From)
      local data_str = "User not exists."
      if user then
        data_str = "Your rewards balance is: "..(user.rewards_balance or 0)
      end
      local msssage = {
        Target = msg.From,
        Action = "ReplyRewardsBalance",
        Balance = tostring(user and user.rewards_balance or 0),
        Data = data_str
      }
      ao.send(msssage)
    end,function (err)
      sendError(err,msg.From)
    end,msg)
  end
)

Handlers.add(
  "getUserInfo",
  Handlers.utils.hasMatchingTag("Action", "UserInfo"),
  function (msg)
    xpcall(function (msg)
      local user = _users.queryUserInfo(msg.From)
      local data_str = "User not exists."
      if user then
        local json = json or require("json")
        data_str = json.encode(user)
      end
      local msssage = {
        Target = msg.From,
        Action = "ReplyUserInfo",
        Balance = tostring(balance),
        Data = data_str
      }
      ao.send(msssage)
    end,function (err)
      sendError(err,msg.From)
    end,msg)
  end
)


Handlers.add(
  "getRoundList",
  Handlers.utils.hasMatchingTag("Action", "RoundList"),
  function (msg)
    local json = json or require("json")
    local message = {
      Target = msg.From,
      Data = json.encode(ROUNDS)
    }
    ao.send(message)
  end
)


Handlers.add(
  "claim",
  Handlers.utils.hasMatchingTag("Action", "Claim"),
  function (msg)
    xpcall(function (msg)
      local user = _users.queryUserInfo(msg.From)
      if user.rewards_balance and user.rewards_balance >= 100 then
        local CRED_PROCESS = CRED_PROCESS or "Sa0iBLPNyJQrwpTTG-tWLQU-1QeUAJA73DdxGGiKoJc"
        local qty =  math.floor(user.rewards_balance * 0.9)
        local message = {
          Target = CRED_PROCESS,
          Action = "Transfer",
          Recipient = msg.From,
          Quantity = tostring(qty),
          ["X-Transfer-Type"] = "Claim",
          ["X-Amount"] = tostring(user.rewards_balance),
          ["X-Tax"] = tostring(0.1),
          ["X-Pushed-For"] = msg["Pushed-For"]
        }
        ao.send(message)
      else
        ao.send({
          Target = msg.From,
          Action = "ClaimFaild",
          Data = "你的奖金账户为0"
        })
      end
    end,function (err) sendError(err,msg.From) end,msg)
  end
)


Handlers.add(
  "spawnedMonitor",
  function (msg)
    if msg.From == ao.id and msg.Tags.Action == "Spawned" then return true else return false end
  end,
  function (msg)
    if msg.Tags["Round"] then
      -- 更新轮次信息
      local round_info = {
        no = tonumber(msg.Tags["Round"]),
        process = msg.Process,
        base_rewards = tonumber(msg.Tags["BaseRewards"]),
        bets_amount = 0,
        bets_count = 0,
        total_participant = 0
      }
      table.insert(ROUNDS,round_info)
      print("Process has been saved:"..msg.Process)
    end
  end
)

Handlers.add(
  "CRED_Debit_Handler",
  function (msg)
    local CRED_PROCESS = CRED_PROCESS or "Sa0iBLPNyJQrwpTTG-tWLQU-1QeUAJA73DdxGGiKoJc"
    if msg.From == CRED_PROCESS and msg.Tags.Action == "Debit-Notice" then
      return true
    else
      return false
    end
  end,
  function (msg)
    xpcall(function (msg)
      print(msg.Tags["X-Transfer-Type"])
      local switch = {
        ["Claim"] = function (msg)
          local user = _users.queryUserInfo(msg.Recipient)
          if user and user.rewards_balance > 0 then
            user.rewards_balance = 0
            user.update_at = msg.Timestamp
            _users.replaceUserInfo(user)
          end
        end
      }
      local fn = switch[msg.Tags["X-Transfer-Type"] or ""]
      if fn then fn(msg) else return nil end
    end,function (err)
      print(err)
    end,msg)
  end
)


Handlers.add(
  'CRED_Bet_Credit',
  function (msg)
    local CRED_PROCESS = CRED_PROCESS or "Sa0iBLPNyJQrwpTTG-tWLQU-1QeUAJA73DdxGGiKoJc"
    if msg.From == CRED_PROCESS and msg.Tags.Action == "Credit-Notice" then
      return true
    else
      return false
    end
  end,
  function (msg)
    xpcall(function (msg)
      local round_no = CURRENT_ROUND or 1
      
      -- local numbers_str = msg.Tags["X-Numbers"]
      local quantity_str = msg.Quantity or "1"
      local num_table = _utils.convertCommandToNumbers(msg.Tags["X-Numbers"] or "")
      local bets = {}
      if #num_table == 0 then
        local random_3 = _utils.getRandomNumber(msg.Timestamp,3)
        table.insert(bets,{random_3,tonumber(quantity_str)})
      else
        bets = _utils.countBets(num_table,tonumber(quantity_str))
      end
      -- 更新用户数据
      local user = _users.queryUserInfo(msg.Sender)
      local userInfo = {
        id = user.id or msg.Sender,
        bets_count = user.bets_count and (user.bets_count + 1) or 1,
        bets_amount = user.bets_amount and (user.bets_amount+tonumber(msg.Quantity)) or tonumber(msg.Quantity),
        rewards_balance = user.rewards_balance or 0,
        total_rewards_count = user.total_rewards_count or 0,
        total_rewards_amount = user.total_rewards_amount or 0,
        create_at = user.create_at or msg.Timestamp,
        update_at = msg.Timestamp,
        participation_rounds = user.participation_rounds and getParticipationRoundStr(user.participation_rounds) or tostring(CURRENT_ROUND)
      }
      _users.replaceUserInfo(userInfo)
      
      -- 更新全局数据
      ROUNDS[round_no]['bets_count'] = ROUNDS[round_no]['bets_count'] + 1
      ROUNDS[round_no]['bets_amount'] = ROUNDS[round_no]['bets_amount'] + tonumber(msg.Quantity)
      ROUNDS[round_no]['total_participant'] = ROUNDS[round_no]['total_participant'] and  (ROUNDS[round_no]['total_participant']+ (user and 0 or 1)) or 1

      -- 发送消息给Round process
      local round_process = ROUNDS[round_no] and ROUNDS[round_no].process or "pgMXPlpSxmp2r6EqIRkpv0M1c7WlRZZm77CoEdUP1VA"
      local json = json or require("json")
      local message = {
        Target = round_process,
        Action = "SaveNumbers",
        Data = json.encode(bets),
        User = msg.Sender,
        Quantity = quantity_str,
        Round = tostring(round_no),
        ["Pushed-For"] = msg.Tags["Pushed-For"],
        ["X-Numbers"] = msg.Tags["X-Numbers"]
      }
      if msg.Tags['X-Donee'] and msg.Tags['X-Donee'] ~= msg.Sender then
        message['Donee'] = msg.Tags['X-Donee']
      end
      ao.send(message)
    end,function(err) 
      sendError(err,msg.Sender)
    end, msg)
  end
)

Handlers.add(
  "changeRound",
  Handlers.utils.hasMatchingTag("Action","Ended"),
  function (msg)
    local utils = utils or require("utils")
    local target_round = utils.find(function (round) return round.process == msg.From end)(ROUNDS)
    if target_round.no == CURRENT_ROUND then
      print("结束Round")
      _rounds.clone()
    end
  end
)

Handlers.add(
  "_test",
  Handlers.utils.hasMatchingTag("Action","Test"),
  function (msg)
    _rounds.clone()
  end
)
--[[
  *******************
  Global constants and module imports
  *******************
]]--
if not NAME then NAME = "aolotto" end
if not VERSION then VERSION = "dev" end
if not CRED_PROCESS then  CRED_PROCESS = "Sa0iBLPNyJQrwpTTG-tWLQU-1QeUAJA73DdxGGiKoJc" end
if not CURRENT_ROUND then CURRENT_ROUND = 1 end
if not ROUNDS then ROUNDS = {{
    no = 1,
    process = "pgMXPlpSxmp2r6EqIRkpv0M1c7WlRZZm77CoEdUP1VA",
    bets_count = 0,
    bets_amount = 0,
    prize = 0,
    base_awards = 0,
}} end

if not SHOOTER then SHOOTER = "7tiIWi2kR_H9hkDQHxy2ZqbOFVb58G4SgQ8wfZGKe9g" end


sqlite3 = require("lsqlite3")
crypto = require(".crypto")
utils = require(".utils")



--[[
  *******************
  Initialize the database to store user information。
  *******************
]]--

db = sqlite3.open_memory()
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
]]

--[[
  *******************
  global functions
  *******************
]] --

-- Send error information to the caller
sendError = function (err,target)
  ao.send({Target=target,Action="Error",Error=Dump(err),Data="400"})
end

-- Get the string of the user's participation round
getParticipationRoundStr = function (str)
  local json = json or require("json")
  local tbl = str and json.decode(str) or {}
  local utils = utils or require(".utils")
  if not utils.includes(CURRENT_ROUND,tbl) then
    table.insert(tbl,CURRENT_ROUND)
  end
  return json.encode(tbl)
end

-- Get random numbers
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



function parseStringToBets(str, limit)
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



-- Proxy user instructions to a specific round process
agentToTargetRound = function (msg,action)
  
  local utils = utils or require(".utils")
  local no = tonumber(msg.Round) or CURRENT_ROUND or 1
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

shareRewardsToAll = function (rewards,timestamp)
  local allBetsAmount = _users.countUserTotalBetsAmount()
  local per_share = rewards/allBetsAmount
  local sql = string.format("UPDATE %s SET rewards_balance = rewards_balance + bets_amount * %.3f,total_rewards_amount = total_rewards_amount + bets_amount * %.3f, update_at = %d",TABLES.users,per_share,per_share,timestamp)
  db:exec(sql)
end


shareRewardsToWinners =  function (winners,timestamp)
  local utils =  utils or require(".utils")
  utils.map(function (val, key)
    local sql = string.format("UPDATE %s SET rewards_balance = rewards_balance + %.3f , total_rewards_amount = total_rewards_amount + %.3f, total_rewards_count = total_rewards_count + 1, update_at = %d WHERE id == '%s'",TABLES.users,val.rewards,val.rewards,timestamp,val.id)
    db:exec(sql)
  end,winners)
end


--[[
  *******************
  functions for users
  *******************
]] --

_users = {}

_users.checkUserExist = function (id)
  local select_str = string.format("SELECT 1 FROM %s WHERE id = '%s'",TABLES.users, id)
  local rows = {}
  for row in db:nrows(select_str) do table.insert(rows,row) end
  return #rows > 0
end

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
    VALUES ('%s',%d,%d,%f,%d,%f,'%s',%d,%d)
  ]],
  user.id, user.bets_count, user.bets_amount, user.rewards_balance, user.total_rewards_count, user.total_rewards_amount, user.participation_rounds, user.create_at, user.update_at
  )
  db:exec(sql)
end

_users.countUserTotalBetsAmount = function ()
  local sql = string.format("SELECT SUM(bets_amount) FROM users")
  local stmt = db:prepare(sql)
  stmt:step()
  local total = stmt:get_value(0)
  stmt:finalize()
  return total
end

_users.queryAllUsers = function ()
  local sql = string.format("SELECT * FROM users")
  local rows = {}
  for row in db:nrows(sql) do
    table.insert(rows,row)
  end
  return rows
end




--[[
  *******************
  functions for rounds
  *******************
]] --

_rounds = {}

_rounds.clone = function (msg,target_round)
  xpcall(function (msg)
    local utils = utils or require(".utils")
    local target_round = utils.find(function (round) return round.no == CURRENT_ROUND end)(ROUNDS)
    local base_rewards = math.floor((target_round.base_rewards + target_round.bets_amount)*0.5)
    local message = {
      Name = NAME.."_"..VERSION.."_"..tostring(CURRENT_ROUND+1),
      Data = "1234",
      ["Round"]= tostring(CURRENT_ROUND+1),
      ["BaseRewards"] = tostring(base_rewards),
      ["Agent"] = ao.id,
      ["Shooter"] = SHOOTER,
      ["Duration"] = "86400000",
      ["StartTime"] = tostring(msg.Timestamp)
    }
    print(message)
    Spawn(ao._module,message)
  end,function (err) return print(err) end,msg)
end

_rounds.initProcess = function (process,code)
  xpcall(function (process,code)
    print("初始化进程:"..process)
    local result =  ao.send({
      Target = process,
      Action = "Eval",
      Data = code or round_fn_code
    })
    local target = result.Target
    print(target)
    return "target"
  end,function (err)
    print(err)
    return false
  end,process,code)
end


_rounds.replaceTargetRound = function (data)
  for index, value in ipairs(ROUNDS) do
    if value.no == data.no then
      ROUNDS[index] = data
    end
  end
end

_rounds.getTargetRound = function (no)
  local utils = utils or require(".utils")
  return utils.find(function (val) return val.no == no end,ROUNDS)
end

--[[
  *******************
  Agent interfaces
  *******************
]]--




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


Handlers.add(
  "getInfo",
  Handlers.utils.hasMatchingTag("Action", "Info"),
  function (msg)
    local data_str = string.format([[
    aolotto, the first lottery game built on theAoComputer.
    --------------------------------------------------------
    * Current Round:                 %d
    * Max Rewards:                   400 CRED 
    * Total Participation:           3000
    --------------------------------------------------------
  ]],CURRENT_ROUND)
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
        data_str = string.format("Your rewards balance is: %.3f CRED",(user.rewards_balance/1000 or 0))
      end
      local msssage = {
        Target = msg.From,
        Action = "Reply-RewardsBalance",
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
      local request_type = msg.RequestType or ""
      local data_str = "User not exists."
      if user then
        if request_type == "json" then
          local json = json or require("json")
          data_str = json.encode(user)
        else
          data_str = string.format([==[
  %s
  -------------------------------------------
  * Number of Wins :   %d
  * Rewards Balance :  %.3f CRED
  * Total Rewards :    %.3f CRED
  * Bets Amount :      %d
  * Bets Placed :      %d
  -------------------------------------------
  Joined at %d
          ]==],user.id, user.total_rewards_count, user.rewards_balance/1000, user.total_rewards_amount/1000, user.bets_amount,user.bets_count,user.create_at)
        end  
      end
      local msssage = {
        Target = msg.From,
        Action = "ReplyUserInfo",
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
        CRED_PROCESS = CRED_PROCESS or "Sa0iBLPNyJQrwpTTG-tWLQU-1QeUAJA73DdxGGiKoJc"
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


--[[
  *****************
  Internal message processing
  *****************
]]--

Handlers.add(
  "_spawned",
  function (msg)
    if msg.From == ao.id and msg.Tags.Action == "Spawned" then return true else return false end
  end,
  function (msg)
    xpcall(function (msg)
      if msg.Tags["Round"] then
        print("新进程创建成功->"..msg.Process)
        -- 初始化新进程的代码
        -- _rounds.initProcess(msg.Process)
        local init =  ao.send({
          Target = msg.Process,
          Action = "Eval",
          Data = round_fn_code
        })

        -- 更新轮次信息
        table.insert(ROUNDS,{
          no = tonumber(msg.Tags["Round"]),
          process = msg.Process,
          base_rewards = tonumber(msg.Tags["BaseRewards"]),
          bets_amount = 0,
          bets_count = 0,
          inited = init.Target == msg.Process
        })
        -- 切换定时触发器发送对象
        ao.send({
          Target = SHOOTER,
          Action = "ChangeSubscriber",
          Data = msg.Process
        })
  
        -- 切换轮次
        local last_round_no = CURRENT_ROUND
        CURRENT_ROUND = tonumber(msg.Tags["Round"])
  
        -- 触发上一轮次开奖
        local last_round = utils.find(function (val) return val.no == last_round_no end,ROUNDS)
        print("触发上一轮次开奖->"..last_round.process)
        print(last_round)
        ao.send({
          Target = last_round.process,
          Action = "Draw",
          ReserveToNextRound = tostring(msg.BaseRewards)
        })
      end
    end,function (err)
      print(err)
    end,msg)
  end
)

Handlers.add(
  "_debit",
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
  '_credit',
  function (msg)
    local CRED_PROCESS = CRED_PROCESS or "Sa0iBLPNyJQrwpTTG-tWLQU-1QeUAJA73DdxGGiKoJc"
    if msg.From == CRED_PROCESS and msg.Tags.Action == "Credit-Notice" and msg.Sender ~= CRED_PROCESS then
      return true
    else
      return false
    end
  end,
  function (msg)
    xpcall(function (msg)
      assert(type(msg.Quantity) == 'string', 'Quantity is required!')
      CURRENT_ROUND = CURRENT_ROUND or 1
      local numbers_str = msg.Tags["X-Numbers"] or getRandomNumber(msg.Id,3)
      -- local quantity_str = msg.Quantity or "1"
      local bet_tbl = parseStringToBets(numbers_str,tonumber(msg.Quantity))
      if not bet_tbl then
        local key = getRandomNumber(msg.Id,3)
        bet_tbl = {}
        bet_tbl[key] = tonumber(msg.Quantity)
      end
      local bets = {}
      for key, value in pairs(bet_tbl) do
        table.insert(bets,{key,value})
      end
      
      -- 更新用户数据
      local user = _users.queryUserInfo(msg.Sender)
      local userInfo = user or {}
      userInfo = {
        id = userInfo.id or msg.Sender,
        bets_count = userInfo.bets_count and (userInfo.bets_count + 1) or 1,
        bets_amount = userInfo.bets_amount and (userInfo.bets_amount+tonumber(msg.Quantity)) or tonumber(msg.Quantity),
        rewards_balance = userInfo.rewards_balance or 0,
        total_rewards_count = userInfo.total_rewards_count or 0,
        total_rewards_amount = userInfo.total_rewards_amount or 0,
        create_at = userInfo.create_at or msg.Timestamp,
        update_at = msg.Timestamp,
        participation_rounds = getParticipationRoundStr(userInfo.participation_rounds)
      }
      _users.replaceUserInfo(userInfo)
      -- 更新全局数据
      
      local target_round = _rounds.getTargetRound(CURRENT_ROUND)
      if target_round then
        target_round.bets_count = target_round.bets_count + 1
        target_round.bets_amount = target_round.bets_amount + tonumber(msg.Quantity)
        _rounds.replaceTargetRound(target_round)
      end
      

      -- 发送消息给Round process
      local json = json or require("json")
      local message = {
        Target = target_round.process,
        Action = "SaveNumbers",
        Data = json.encode(bets),
        User = msg.Sender,
        Quantity = msg.Quantity,
        Round = tostring(CURRENT_ROUND),
        ["Pushed-For"] = msg.Tags["Pushed-For"],
        ["X-Numbers"] = msg.Tags["X-Numbers"]
      }
      if msg.Tags['X-Donee'] and msg.Tags['X-Donee'] ~= msg.Sender then
        message['Donee'] = msg.Tags['X-Donee']
      end
      ao.send(message)
    end,function(err)
      print(err)
      sendError(err,msg.Sender)
    end, msg)
  end
)

Handlers.add(
  "_change",
  Handlers.utils.hasMatchingTag("Action","Ended"),
  function (msg)
    xpcall(function (msg)
      local utils = utils or require(".utils")
      local target_round = utils.find(function (round) return round.process == msg.From end)(ROUNDS)
      if target_round and target_round.no == CURRENT_ROUND then
        _rounds.clone(msg)
      end
    end,function (err)
      print(err)
    end,msg)
  end
)

Handlers.add(
  "_save_winners",
  function (msg)
    if msg.Tags.Action == "SaveWinners" then
      local utils = utils or require(".utils")
      return utils.includes(msg.From,utils.map(function (val, key) return val.process end,ROUNDS))
    else
      return false
    end
  end,
  function (msg)
    print("SaveWinners->"..msg.Tags["Rewards"])
    local json = json or require("json")
    local num_winbets = tonumber(msg.Tags["Winbets"])
    local num_rewards = tonumber(msg.Tags["Rewards"])
    local num_winners = tonumber(msg.Tags["Winners"])
    local winners = json.decode(msg.Data)
    local utils = utils or require(".utils")
    utils.map(function (val, key)
      if val.process == msg.From then
        val.rewards = num_rewards
        val.winbets = num_winbets
        val.winners = num_winners
        val.drawed = true
      end
    end,ROUNDS)
    if #winners > 0 then
      shareRewardsToWinners(winners,msg.Timestamp)
    else
      shareRewardsToAll(num_rewards,msg.Timestamp)
    end
  end
)

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
      Action = "Reply-Rounds",
      Data = data_str
    }
    ao.send(msssage)
  end
)

Handlers.add(
  "_test",
  Handlers.utils.hasMatchingTag("Action","Test"),
  function (msg)
    print("Test")
    local a = _rounds.initProcess("k8pdBowde6n-E_ayphBIjZtcl-O2QXuFUnShId_iXQk")
    print("a->")
    print(Dump(a))
  end
)



--[[
  *****************
  Administrator interface
  *****************
]]--

Handlers.add(
  "_manage",
  function (msg)
    ADMINISTRATOR = ADMINISTRATOR or "-_hz5V_I73bHVHqKSJF_B6cDBBSn8z8nPEUGcViTYko"
    if msg.From == ADMINISTRATOR then return true else return false end
  end,
  function (msg)
    ao.authorities = {ADMINISTRATOR}
    print("call -> "..msg.Action)
    if msg.Action == "UpdateTemplate" then
      spawn_fn_code = msg.Data
    end
  end
)
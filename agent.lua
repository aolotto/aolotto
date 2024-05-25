CURRENT_ROUND = 1
ROUNDS = {{
    no = 1,
    process = "pgMXPlpSxmp2r6EqIRkpv0M1c7WlRZZm77CoEdUP1VA",
    bets_count = 0,
    bets_amount = 0,
    prize = 0,
}}

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

--[[
  User related functions
]]
_users = {
  checkUserExist = function (id)
    local select_str = string.format("SELECT 1 FROM %s WHERE id = '%s'",TABLES.users, id)
    local rows = {}
    for row in db:nrows(select_str) do table.insert(rows,row) end
    return #rows > 0
  end
}



_rounds = {
  clone = function ()
    xpcall(function ()
      ao.spawn(ao._module,{
        Name = "aolotto_round_dev",
      })
      print('进程已克隆')
    end,function (err) print(err) end)
  end,

  init_process = function (process)
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
}


--[[
  User related interfaces for CLI
]]--

Handlers.add(
  "getRoundInfo",
  Handlers.utils.hasMatchingTag("Action", "GetRoundInfo"),
  function (msg)
    local utils = utils or require(".utils")
    local no = msg.Round or CURRENT_ROUND or 1
    local target_round = utils.find(function (round) return round.no == no end)(ROUNDS)
    if target_round then
      local message = {
        Target = target_round.process,
        Action = "Info",
        User = msg.From
      }
      ao.send(message)
    else
      ao.send({Target=msg.From,Data="The Round "..no.." has not started yet."})
    end
  end
)

Handlers.add(
  "getRoundInfo",
  Handlers.utils.hasMatchingTag("Action", "GetRoundInfo"),
  function (msg)
    print("GetRoundInfo -> "..msg.From)
  end
)


--[[
  到账处理
]]

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
      local round_process = ROUNDS[CURRENT_ROUND] and ROUNDS[CURRENT_ROUND].process or "pgMXPlpSxmp2r6EqIRkpv0M1c7WlRZZm77CoEdUP1VA"
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
      if _users.checkUserExist(msg.Sender) then
        local update_stmt = string.format(
          "UPDATE users SET bets_count = bets_count + 1 , bets_amount = bets_amount + %d, update_at = %d WHERE id = '%s'",
          quantity_str,
          msg.Timestamp,
          msg.Sender
        )
        db:exec(update_stmt)
      else
        local insert_stmt = string.format(
          [[
            INSERT INTO users (id, bets_count,bets_amount,rewards_balance, total_rewards_count, total_rewards_amount,create_at,update_at)
            VALUES ('%s', 1, %d, 0, 0, 0,%d,%d)
          ]],
          msg.Sender,
          quantity_str,
          msg.Timestamp,
          msg.Timestamp
        )
        db:exec(insert_stmt)
      end

      -- 更新全局数据
      ROUNDS[CURRENT_ROUND]['bets_count'] = ROUNDS[CURRENT_ROUND]['bets_count'] + 1
      ROUNDS[CURRENT_ROUND]['bets_amount'] = ROUNDS[CURRENT_ROUND]['bets_amount'] + tonumber(quantity_str)
      ROUNDS[CURRENT_ROUND]['prize'] = ROUNDS[CURRENT_ROUND]['prize'] + tonumber(quantity_str)

      -- 发送消息给Round process
      local json = json or require("json")
      local tags = {
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
        tags['Donee'] = msg.Tags['X-Donee']
      end
      ao.send(tags)
    end,function(err) 
      sendError(err,msg.Sender)
    end, msg)
  end
)


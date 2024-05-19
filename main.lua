local sqlite3 = require("lsqlite3")
local crypto = require(".crypto")
local bint = require('.bint')(256)
local _utils = _utils or require("./utils")
 
db = sqlite3.open_memory()

--[[
  初始化表
]]--
db:exec[[
  CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    name TEXT, 
    wallet_address TEXT,
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

--[[
  User related functions
]]
_users = {
  checkUserExist = function (msg)
    local select_str = string.format("SELECT 1 FROM %s WHERE id = '%s'",TABLES.users, msg.From)
    local rows = {}
    for row in db:nrows(select_str) do table.insert(rows,row) end
    return #rows > 0
  end
}

--[[
  User related interface
]]--
Handlers.add(
  "register",
  Handlers.utils.hasMatchingTag("Action", "Register"),
  function (msg)
    xpcall(function (msg)
      local registered = _users.checkUserExist(msg)
      if not registered then
        local registe_result = (function ()
          local insert_stmt = db:prepare [[
            INSERT INTO users (id, name, wallet_address, create_at)
            VALUES (:id, :name, :wallet_address, :create_at)
          ]]
          insert_stmt:bind_names({
            id = msg.From,
            name = msg.Name or "",
            wallet_address = msg.WalletAddress or msg.Owner,
            create_at = msg.Timestamp
          })
          local result = insert_stmt:step()
          insert_stmt:reset()
          return result
        end)(msg)
        print("registe_result: ".. type(registe_result))
        ao.send({Target=msg.From,Action="RegisterSucesssNotice",Data="Registered at "..msg.Timestamp})
      else
        error("User exists.")
      end
    end, function(err) _utils.sendError(err,msg.From) end, msg)
  end
)

Handlers.add(
  "getUserInfo",
  Handlers.utils.hasMatchingTag("Action", "GetUserInfo"),
  function (msg)
    xpcall(function (msg)
      local query_str = string.format("SELECT * FROM %s WHERE id == '%s' LIMIT 1",TABLES.users,msg.From)
      local rows = {}
      for row in db:nrows(query_str) do
          table.insert(rows, row)
      end
      if(#rows > 0) then
        local json = json or require("json")
        ao.send({Target=msg.From,Action="ReplyUserInfo",Data=json.encode(rows[#rows])})
      else
        error("User not Exists.")
      end
    end,function(err) _utils.sendError(err,msg.From) end, msg)
  end
)

Handlers.add(
  "setUserInfo",
  Handlers.utils.hasMatchingTag("Action", "SetUserInfo"),
  function (msg)
    xpcall(function (msg)
      local is_user_exist = _users.checkUserExist(msg)
      if is_user_exist then
        local json = json or require("json")
        local data = json.decode(msg.Data)
        local name = msg.Name or data.Name
        if not name then error("Missed Name value.") end
        local update_str = string.format("UPDATE %s SET name = '%s',update_at = %d WHERE id = '%s'",TABLES.users,name,msg.Timestamp,msg.From)
        local code = db:exec(update_str)
        ao.send({Target=msg.From,Action="SetUserInfoSucess",Data=code>0 and "updated." or "nothing updated."})
      else
        error("your process have not been registered.")
      end
    end,function(err) _utils.sendError(err,msg.From) end, msg)
  end
)

Handlers.add(
  "modifyUserAddress",
  Handlers.utils.hasMatchingTag("Action", "ModifyUserAddress"),
  function (msg)
    xpcall(function (msg)
      if not msg.Address then error("Missed Wallet Address tag.",1) end
      local is_user_exist = _users.checkUserExist(msg)
      if is_user_exist then
        local update_str = string.format("UPDATE %s SET wallet_address = '%s',update_at = %d WHERE id = '%s'",TABLES.users,msg.Address,msg.Timestamp,msg.From)
        db:exec(update_str)
        ao.send({Target=msg.From,Action="ModifyAddressSucess",Data="The process has been transferred to "..msg.Address})
      else
        error("your process have not been registered.")
      end
    end,function(err) _utils.sendError(err,msg.From) end, msg)
  end
)

Handlers.add(
  "getLottoInfo",
  Handlers.utils.hasMatchingTag("Action", "GetLottoInfo"),
  function (msg)
    print("GetLottoInfo - From -> "..msg.From)
    print("GetLottoInfo - Action -> "..msg.Action)
    print("GetLottoInfo - UserAddress -> "..msg.UserAddress)
  end
)

Handlers.add(
  "getRoundInfo",
  Handlers.utils.hasMatchingTag("Action", "GetRoundInfo"),
  function (msg)
    print("GetRoundInfo -> "..msg.From)
  end
)



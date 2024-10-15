


local ao = require(".ao")
local crypto = require(".crypto")

local utils = require(".utils")
-- Extend utils methods
utils.parseNumberStringToBets = function(str,len)
  local bets = {}
  local total = 0
  
  for item in string.gmatch(str, "[^,]+") do
    local start, finish, multiplier = string.match(item, "(%d+)-?(%d*)%*?(%d*)")
    
    if start and string.len(start) <= len then
      multiplier = tonumber(multiplier) or 1
      
      if finish == "" then
        -- Single number or number with multiplier
        bets[start] = (bets[start] or 0) + multiplier
        total = total + multiplier
      else
        -- Number range
        local startNum, finishNum = tonumber(start), tonumber(finish)
        if startNum and finishNum and startNum <= finishNum and string.len(finish) <= len then
          for i = startNum, finishNum do
            local num = string.format("%0"..len.."d", i)
            bets[num] = (bets[num] or 0) + multiplier
            total = total + multiplier
          end
        end
      end
    end
    -- Skip illegal input
  end
  
  return bets, total
end

utils.getRandomNumber = function(len,seed)
  local numbers = ""
  for i = 1, len or 3 do
    local r = crypto.cipher.issac.getRandom()
    local n = crypto.cipher.issac.random(0, 9, tostring(i)..seed..tostring(r))
    numbers = numbers .. n
  end
  return numbers
end

utils.increaseById = function(self, id, tbl)
  self[id] = self[id] or {}
  for k,v in pairs(tbl) do
    if type(v) == "number" then
      self[id][k] = (self[id][k] or 0) + (v or 0)
    end
    if type(v) == "table" then
      self[id][k] = self[id][k] or {}
      for _k,_v in pairs(v) do
        self[id][k][_k] = (self[id][k][_k] or 0) + (_v or 0)
      end
    end
  end
end

utils.decreaseById = function(self, id, tbl)
  self[id] = self[id] or {}
  for k,v in pairs(tbl) do
    if type(v) == "number" then
      self[id][k] = (self[id][k] or 0) - (v or 0)
    end
    if type(v) == "table" then
      self[id][k] = self[id][k] or {}
      for _k,_v in pairs(v) do
        self[id][k][_k] = (self[id][k][_k] or 0) - (_v or 0)
      end
    end
  end
end

utils.getById = function(self, id)
  return self[id]
end

utils.updateById = function(self, id, tbl)
  self[id] = self[id] or {}
  for k,v in pairs(tbl) do
    self[id][k] = v
  end
end


Pools = Pools or {}
setmetatable(Pools, {
  __index = {
    -- Get a pool by ID
    getById = utils.getById,
    -- Add a new pool with given ID and table
    add = function(self, id, tbl)
      self[id] = tbl
    end,
    -- Update an existing pool's properties
    updateById = utils.updateById,
    -- Remove a pool by ID
    remove = function(self, id)
      self[id] = nil
    end,
    -- Increase pool's values
    increaseById = utils.increaseById,
    -- Decrease pool's values
    decreaseById = utils.decreaseById,
    increaseMine = function(self,id,v)
      assert(id ~= nil, "missed id")
      assert(v ~= nil and type(v) == "number","error type of v ")
      self[id].mine = self[id].mine or {0,0,0}
      self[id].mine[1] = (self[id].mine[1] or 0) + v
      self[id].mine[2] = (self[id].mine[2] or 0) + v
    end,
    decreaseMine = function(self,id,v)
      assert(id ~= nil, "missed id")
      assert(v ~= nil and type(v) == "number","error type of v ")
      self[id].mine = self[id].mine or {0,0,0}
      self[id].mine[1] = (self[id].mine[1] or 0) - v
      self[id].mine[3] = (self[id].mine[3] or 0) + v
    end
  }
})

Players = Players or {}
setmetatable(Players, {
  __index = {
    -- Get a player by ID
    getById = utils.getById,
    -- Add a new player with given ID and table
    add = function(self, id, tbl)
      self[id] = self[id] or {}
      for k,v in pairs(tbl) do
        self[id][k] = v
      end
    end,
    -- Increase player's values
    increaseById = utils.increaseById,
    -- Decrease player's values
    decreaseById = utils.decreaseById,
    -- Update player's values
    updateById = utils.updateById,
    -- Remove a player by ID
    remove = function(self, id)
      self[id] = nil
    end,

    increaseRewards = function(self,id,token,value)

      assert(id and type(id) == "string", "Invalid player ID")
      assert(token and type(token) == "string", "Invalid token")
      assert(value and type(value) == "number", "Invalid reward value")
      
      self[id] = self[id] or {}
      self[id].rewards = self[id].rewards or {}
      local bal = self[id].rewards[token] or {}
      bal[1] = (bal[1] or 0) + value
      bal[2] = (bal[2] or 0) + value

      self[id].rewards[token] = bal

    end,

    decreaseRewards = function(self, id, token, value)
      assert(id and type(id) == "string", "Invalid player ID")
      assert(token and type(token) == "string", "Invalid token")
      assert(value and type(value) == "number", "Invalid reward value")
      
      self[id] = self[id] or {}
      self[id].rewards = self[id].rewards or {}
      local bal = self[id].rewards[token] or {}
      bal[1] = math.max(0, (bal[1] or 0) - value)
      bal[2] = bal[2] or 0

      self[id].rewards[token] = bal
    end,

    increaseBets =  function(self,id,token,values)
      assert(id and type(id) == "string", "Invalid player ID")
      assert(token and type(token) == "string", "Invalid token")
      assert(values and type(values) == "table", "Invalid Values" )


      self[id] = self[id] or {}
      self[id].bets = self[id].bets or {}
      self[id].bets[token] = self[id].bets[token] or {}
      local b = self[id].bets[token]
      for i,v in ipairs(values) do
        self[id].bets[token][i] = (b[i] or 0) + (v or 0)
      end
    end,

    increaseMine = function(self,id,value)
      self[id].mine = self[id].mine or {0,0,0}
      self[id].mine[1] = self[id].mine[1] + value
      self[id].mine[2] = self[id].mine[2] + value
    end,

    decreaseMine = function(self,id,value)
      self[id].mine = self[id].mine or {0,0,0}
      self[id].mine[1] = self[id].mine[1] - value
      self[id].mine[3] = self[id].mine[3] + value
    end
  }
})
State = State or {}
Payments = Payments or {}
TAX = TAX or 0.05
ALTOKEN = ALTOKEN or "Sj2vhYBdl-Q1jDw3HPNHUz_1zp4CPMywhSW53Z4AHpU"
Balances = Balances or {}
Notice = Notice or {}




-- handlers

Handlers.add("pools", "Pools", function(msg)
  local pools = {}
  for k,v in pairs(Pools) do
    if v.state == 1 then
      pools[k] = v
    end
  end
  msg.reply({Data = pools})
end)

Handlers.add("all-pools", "All-Pools", function(msg)
  msg.reply({Data = Pools})
end)

Handlers.add("get-player", "Get-Player", function(msg)
  local player = Players[msg['Player'] or msg.From]
  if player then
    msg.reply({Data = player})
  else
    msg.reply({Error = "Player not found"})
  end
end)

Handlers.add("bet", {
  Action = "Credit-Notice",
  Quantity = "%d",
  From ="_",
  ['X-Numbers'] = "_",
  Data = "_"
}, function(msg)
  
  local pool = Pools:getById(msg.From)
  assert(pool ~= nil and pool.pool_id ~= nil, "Pool not found or not active")
  local max_bets_in_quantity = math.floor(tonumber(msg.Quantity)/pool.price) 
  assert(max_bets_in_quantity > 0, "Invalid quantity")
  local bet_items, total_bets = utils.parseNumberStringToBets(msg['X-Numbers'],pool.digits or 3)

  -- If total_bets is not equal to max_bets_in_quantity, generate a random number
  if total_bets ~= max_bets_in_quantity then
    bet_items = {}
    total_bets = 0
    local random_number = utils.getRandomNumber(pool.digits or 3,msg.Id)
    bet_items[random_number] = max_bets_in_quantity
    total_bets = max_bets_in_quantity
  end

  print(bet_items)
  print(total_bets)

  -- Create player if not exists
  if not Players:getById(msg.Sender) then
    print("Add new player")
    Players:add(msg.Sender, {
      id = msg.Sender,
      ts_create = msg.Timestamp,
    })
    State.total_palyers=(State.total_palyers or 0)+1
  end
  

  Send({
    Target = pool.pool_id,
    Action = "Save-Bets",
    Ticket = msg.Id,
    Player = msg.Sender,
    Ticker = pool.ticker,
    Denomination = pool.denomination,
    Price = tostring(pool.price),
    ['Ticket-Nouce'] = utils.getRandomNumber(3,ao.id),
    Data = {
      count = total_bets,
      amount = total_bets * pool.price,
      numbers = bet_items,
      ts_bet = msg.Timestamp
    }
  })
  .onReply(function(m)
    -- Increase player's bets and tickets
    Players:increaseById(msg.Sender, {tickets = 1})
    local new_bet = {}
    new_bet[1] = total_bets
    new_bet[2] = total_bets * pool.price
    new_bet[3] = 1
    Players:increaseBets(msg.Sender,msg.From,new_bet)
    -- Increase pool's stats
    Pools[msg.From].stats = m.Data
    -- Update player's latest bet timestamp
    Players:updateById(msg.Sender,{
      ts_latest_bet = msg.Timestamp
    })

    Send({
      Target = msg.Sender,
      Action = "Lotto-Notice",
      ['Ticket-Id'] = msg.Id,
      ['Pool-Id'] = m.From or pool.pool_id,
      ['Token-Id'] = msg.From or pool.token_id,
      ['Ticker'] = pool.ticker,
      ['Denomination'] = tostring(pool.denomination),
      ['Price'] = tostring(pool.price),
      ['Count'] = tostring(total_bets),
      ['Amount'] = tostring(total_bets * pool.price),
      ['Bet-Timestamp'] = tostring(msg.Timestamp),
      ['X-Numbers'] = msg['X-Numbers'],
      Data = bet_items
    })
  end)


end)



Handlers.add("draw-notice","Draw-Notice",function(msg)
  local pool = nil
  for k,v in pairs(Pools) do
    if v.pool_id == msg.From then
      pool = v
    end
  end
  assert(pool~=nil,"pool is not exist")
  print("save draw")
  table.insert(Notice,msg.Data)
  
  local draw = msg.Data.draw
  local players = msg.Data.players
  
  for player_id,reward in pairs(draw.rewards) do
    Players:increaseRewards(player_id,pool.token_id,reward)
    Send({
      Target = player_id,
      Action = "Bonus-Added",
      Quantity = tostring(reward),
      Token = pool.token_id,
      Ticker = pool.ticker,
      Denomination = tostring(pool.denomination),
      Sender = msg.From,
      Data = "You get a bonus of "..tostring(reward).." $"..pool.ticker
    })
  end

  if pool.mine[1] > 0 then
    local per_mine_amount = pool.mine[1] / msg.Data.state.bet_count
    local players = msg.Data.players
    for id, v in pairs(players) do
      Players:increaseMine(id,v[1]*per_mine_amount)
    end
    Pools:decreaseMine(pool.token_id, pool.mine[1])
    table.insert(Mines,{
      id = msg.Id,
      quantity = pool.mine[1],
      pool = pool.token_id,
      round = tostring(msg.Data.state.current_round),
      type = "decrease",
      ts_create = msg.Timestamp
    })

  end
  Handlers.mine(pool.token_id)
end)



Handlers.add("claim",{
  Action = "Claim",
  Token = "_",
  From = function(_from) return Players:getById(_from) ~= nil end
},function(msg)
  local player = Players:getById(msg.From)
  assert(player.rewards ~= nil and player.rewards[msg.Token] ~= nil and player.rewards[msg.Token][1] > 0, "no rewards to calim")
  local balance = player.rewards[msg.Token][1]
  local quantity = math.floor(balance * (1-TAX))
  assert(quantity > 0, "Amount too small, unable to claim")
  Players:decreaseRewards(msg.From,msg.Token,balance)
  local pool = Pools[msg.Token]
  table.insert(Payments,{
    id = msg.Id,
    quantity = quantity,
    token = msg.Token,
    recipient = msg.From,
    ticker = pool.ticker,
    logo = pool.logo,
    denomination = pool.denomination,
    ts_created = msg.Timestamp
  })
  

  Handlers.once("once-claimed-"..msg.Id,{
    Action = "Debit-Notice",
    From = msg.Token,
    Quantity = tostring(quantity),
    Recipient = msg.From,
    ['X-Transfer-Type'] = "Claim-Notice",
    ['X-Claim-Id'] = msg.Id,
    ['X-Claim-Tax'] = tostring(TAX),
  },function(m)
    while i <= #Payments do
      if Payments[i].id == msg['X-Claim-Id'] then
        Payments[i] = nil

        Send({
          Target = m.Recipient,
          Action = "Bonus-Removed",
          Balance = m['X-Balance'] or tostring(balance),
          Quantity = m.Quantity or tostring(quantity),
          Tax = m['X-Claim-Tax'] or tostring(TAX),
          Token = m.From or msg.Token,
          Ticker = pool.ticker,
          Denomination = pool.denomination,
          Data = "You've claim a bouns of "..tostring(balance).." $"..pool.ticker
        })
        
      end 
    end
  end)

  Send({
    Target = msg.Token,
    Action = "Transfer",
    Recipient = msg.From,
    ['X-Transfer-Type'] = "Claim-Notice",
    ['X-Claim-Id'] = msg.Id,
    ['X-Claim-Tax'] = tostring(TAX),
    ['X-Balance'] = tostring(balance),
    Quantity = tostring(quantity)
  })

end)





Handlers.add('create-pool',{
  Action = "Create-Pool",
  From = Owner,
  Token = "_",
  Pool = "_",
  Name = "_"
},function(msg)
  assert(Pools[msg.Token] == nil, "Pool already exists")
  State.total_pools = (State.total_pools or 0) + 1
  State.pools_ref = (State.pools_ref or 0) + 1
  Pools[msg.Token] = {
    ref = State.pools_ref,
    name = msg.Name,
    pool_id = msg.Pool,
    token_id = msg.Token,
    ts_created = msg.Timestamp,
    digits = tonumber(msg.Digits) or 3,
    ticker = msg.Ticker,
    denomination = msg.Denomination,
    logo = msg.Logo
  }
  msg.reply({
    Action = "Pool-Created",
    Data = Pools[msg.Token]
  })
end)

Handlers.add("start-pool",{
  Action = "Credit-Notice",
  Quantity = "%d+",
  From = "_",
  ['X-Price'] = "%d+",
  ['X-Transfer-Type'] = "Start-Pool"
},function(msg)
  assert(Pools[msg.From] ~= nil, "no pool for the token")
  local pool = Pools[msg.From]
  assert(pool.pool_id ~= nil, "no process for this pool.")
  assert(pool.state ~= 1, "the pool was starting before.")
  assert(tonumber(msg.Quantity) >= tonumber(msg['X-Price'])* (10^(pool.digits or 3)))
  Handlers.once('started_pool'..msg.From,{
    From = Pools[msg.From].pool_id,
    Action = "Pool-Started",
  },function(m)
    Pools[msg.From].stats = m.Data
    Pools[msg.From].state = 1
    Pools[msg.From].price = tonumber(msg['X-Price'])
    print("Pool ["..msg.From.."] 's process has been started.")
  end)

  Send({
    Target = Pools[msg.From].pool_id,
    Action = "Start-Pool",
    ['Funds'] = msg.Quantity,
    Price = msg['X-Price'],
    Data = Pools[msg.From]
  })

end)

Handlers.mine = function(pid)
  assert(pid ~= nil, "missed pool id")
  local pool = Pools:getById(pid)
  assert(pool ~= nil,"pool not exists")
  assert(pool.mine == nil or pool.mine[1] == 0, "already mined for current round before")
  Mines = Mines or {}
  
  Handlers.once(
    "once-mined-"..pid.."-"..pool.stats.current_round.."-"..os.time(),
    {
      Action = "Mined",
      From = ALTOKEN,
      Pool = pid,
      Round = tostring(pool.stats.current_round),
      Quantity = "%d+"
    },
    function(m)
      table.insert(Mines,{
        id = m.Id,
        quantity = tonumber(m.Quantity),
        pool = m.Pool,
        round = m.Round,
        type = "increase",
        ts_create = m.Timestamp
      })
      Pools:increaseMine(m.Pool,tonumber(m.Quantity))
      Pools:increaseById(m.Pool,{total_mined = 1})
      State.total_mined = (State.total_mined or 0) + 1

    end
  )

  Send({
    Target = ALTOKEN,
    Action = "Mine",
    Pool = pid,
    Round = tostring(pool.stats.current_round)
  })
end
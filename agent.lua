Pools = Pools or {total=0,ref=0}
Players = Players or {total=0}
State = State or {}
TAX = 0.05
Payments = Payments or {}

local crypto = require(".crypto")
local utils = require(".utils")
local ao = require(".ao")

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

-- Create a metatable for Global Tables with custom methods
local players = setmetatable(Players, {
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
    end

  }
})



local pools = setmetatable(Pools, {
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
  }
})



Handlers.add("pools", "Pools", function(msg)
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
  From = function(_from)
    return Pools[_from] ~= nil and Pools[_from].pool_id ~= nil
  end,
  ['X-Numbers'] = "_",
  Data = "_"
}, function(msg)
  local pool = pools:getById(msg.From)
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
  if not players:getById(msg.Sender) then
    print("Add new player")
    players:add(msg.Sender, {
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
    Ticker = pool.token_info.ticker,
    Denomination = pool.token_info.denomination,
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
    players:increaseById(msg.Sender, {tickets = 1})
    local new_bet = {}
    new_bet[1] = total_bets
    new_bet[2] = total_bets * pool.price
    new_bet[3] = 1
    print(new_bet)
    players:increaseBets(msg.Sender,msg.From,new_bet)
    -- Increase pool's stats
    Pools[msg.From].stats = m.Data
    -- Update player's latest bet timestamp
    players:updateById(msg.Sender,{
      ts_latest_bet = msg.Timestamp
    })

    print("saved!!!")

    Send({
      Target = msg.Sender,
      Action = "Lotto-Notice",
      ['Ticket-Id'] = msg.Id,
      ['Pool-Id'] = m.From or pool.pool_id,
      ['Token-Id'] = msg.From or pool.token_id,
      ['Ticker'] = pool.token_info.ticker,
      ['Denomination'] = tostring(pool.token_info.denomination),
      ['Price'] = tostring(pool.price),
      ['Count'] = tostring(total_bets),
      ['Amount'] = tostring(total_bets * pool.price),
      ['Bet-Timestamp'] = tostring(msg.Timestamp),
      ['X-Numbers'] = msg['X-Numbers'],
      Data = bet_items
    })
  end)


end)


Handlers.createNewPool = function(params)
  assert(params.pool_id ~= nil and params.token_id ~= nil and params.name ~= nil, "Invalid params")
  assert(pools[params.token_id] == nil, "Pool already exists")

  for k,v in pairs(Pools) do
    assert(v.pool_id ~= params.pool_id, "Pool ID already exists")
  end

  table.insert(ao.authorities,params.pool_id)

  State.total_pools = (State.total_pools or 0) + 1
  State.pools_ref = (State.pools_ref or 0) + 1
  Pools[params.token_id] = {
    ref = State.pools_ref,
    name = params.name,
    pool_id = params.pool_id,
    token_id = params.token_id,
    price = params.price or 100,
    digits = params.digits or 3,
    token_info = params.token_info,
    ts_create = os.time(),
    state = 0
  }
  if params.token_info == nil then
    Handlers.once("once_get_token_info_"..params.token_id,{
      From = params.token_id,
      Name = "_",
      Ticker = "_",
      Denomination = "_",
      Logo = "_",
    },function(m)
      Pools[params.token_id].token_info = {
        id = m.From,
        name = m.Name,
        ticker = m.Ticker,
        denomination = m.Denomination,
        logo = m.Logo,
      }
      print('Pool created -> '..params.token_id)
    end)


    Send({
      Target = params.token_id,
      Action = "Info",
    })
  end
end

Handlers.removePool = function(id)
  if Pools[id] ~= nil then
    Pools[id] = nil
    State.total_pools = math.max(0,(State.total_pools or 0)-1)
    print('Pool ['..id.."] has been removed!")
  end
end


Handlers.add("start_pool",{
  From = function(_from)
    return Pools[_from] ~= nil
  end,
  Action = "Credit-Notice",
  Quantity = function(qty,_m)
    return tonumber(qty) >= Pools[_m.From].price * math.floor(10 ^ Pools[_m.From].digits)
  end,
  ['X-Transfer-Type'] = "Start-Pool"
},function(msg)
  Handlers.once('started_pool'..msg.From,{
    From = Pools[msg.From].pool_id,
    Action = "Pool-Started",
  },function(m)
    Pools[msg.From].stats = m.Data
    Pools[msg.From].state = 1
    print("Pool ["..msg.From.."] 's process has been started.")
  end)

  Send({
    Target = Pools[msg.From].pool_id,
    Action = "Start-Pool",
    ['Funds'] = msg.Quantity,
    Data = Pools[msg.From]
  })

end)



Handlers.add("draw_notice",{
  Action="Draw-Notice",
  From = function(_from)
    local pool = nil
    for k,v in pairs(Pools) do
      if v.pool_id == _from then
        pool = v
      end
    end
    return pool ~= nil
  end
},function(msg)
  local pool = nil
  for k,v in pairs(Pools) do
    if v.pool_id == msg.From then
      pool = v
    end
  end
  assert(pool~=nil,"pool is not exist")
  local draw = msg.Data
  
  for player_id,reward in pairs(draw.rewards) do
    players:increaseRewards(player_id,pool.token_id,reward)
    Send({
      Target = player_id,
      Action = "Bonus-Added",
      Quantity = tostring(reward),
      Token = pool.token_id,
      Ticker = pool.token_info.ticker,
      Denomination = tostring(pool.token_info.denomination),
      Sender = msg.From,
      Data = "You get a bonus of "..tostring(reward).." $"..pool.token_info.ticker
    })
    print("rewarded!!")
  end

end)



Handlers.add("claim",{
  Action = "Claim",
  Token = "_",
  From = function(_from) return players:getById(_from) ~= nil end
},function(msg)
  local player = players:getById(msg.From)
  assert(player.rewards ~= nil and player.rewards[msg.Token] ~= nil and player.rewards[msg.Token][1] > 0, "no rewards to calim")
  local balance = player.rewards[msg.Token][1]
  local quantity = math.floor(balance * (1-TAX))
  assert(quantity > 0, "Amount too small, unable to claim")
  players:decreaseRewards(msg.From,msg.Token,balance)
  local token_info = Pools[msg.Token].token_info
  table.insert(Payments,{
    id = msg.Id,
    quantity = quantity,
    token = msg.Token,
    recipient = msg.From,
    token_info = token_info,
    ts_created = msg.Timestamp
  })
  

  Handlers.once("once_claimed_"..msg.Id,{
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
          Ticker = token_info.ticker,
          Denomination = token_info.denomination,
          Data = "You've claim a bouns of "..tostring(balance).." $"..pool.token_info.ticker
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
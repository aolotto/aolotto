local ao = require(".ao")
local drive = require("modules.drive")
local utils = require("modules.utils")
local crypto = require(".crypto")


TAXER = TAXER or Owner

State = State or {}
Pools = Pools or  {}
Players = Players or {}
Balances = Balances or {}
Taxation = Taxation or {}
Leaderboard = Leaderboard or {}

-- This function forwards a ticket to the specified pool.
-- It checks if the pool exists and if the quantity is within the pool's price range.
-- It also verifies if the 'From' field matches the token of the pool.
-- If all conditions are met, it forwards the ticket to the pool with a 'Ticket-Notice' action.
Handlers.add("forward-ticket",{
  Action = "Credit-Notice",
  Quantity = "%d+",
  ['X-Pool'] = function(pid,m) return Pools[pid]~= nil and Pools[pid].price <= tonumber(m.Quantity) end,
  ['X-Numbers'] = "_",
  From = function(from,m) return Pools[m['X-Pool']].token == from end
},function(msg)
  msg.forward(msg['X-Pool'],{Action = "Ticket-Notice",Token=msg.From})
end)


-- This function processes the "lotto-notice" action, updating the state of the pool and the player's information.
-- It handles the increment of tickets sold, total tickets, and balances.
Handlers.add("lotto-notice",{
  Action = "Lotto-Notice",
  From = function(from) return Pools[from]~=nil end,
  Player = "_",
  Pool = "_",
  Round = "%d+",
  Count = "%d+",
  Amount = "%d+",
  ['X-Numbers'] = "_",
  Price = "%d+",
  Token = "_",
  Currency = "_",
  Ticket = "_"
},function(msg)

  Pools[msg.From].state = msg.Data
  -- if not the player then create a new player.
  if not Players[msg.Player] then
    Players[msg.Player] = {}
    utils.increase(State,{total_players=1})
  end

  if not Players[msg.Player][msg.From] then 
    Players[msg.Player][msg.From] = {0,0,0,0,0} -- count,amount,tickets,rewarded,balance 
  end

  utils.increase(Players[msg.Player][msg.From],{tonumber(msg.Count),tonumber(msg.Amount),1,0,0})
  utils.increase(State,{total_tickets=1})
  utils.increase(Pools[msg.From].sold,{tonumber(msg.Count),tonumber(msg.Amount),1})
  if not Balances[msg.Token] then
    Balances[msg.Token] = {0,0,0}
  end
  utils.increase(Balances[msg.Token],{tonumber(msg.Amount),tonumber(msg.Amount),0})
end)

-- This function processes the "draw-notice" action, updating the state of the pool and the player's information.
-- It handles the increment of tickets sold, total tickets, and balances.
Handlers.add("draw-notice","Draw-Notice",function(msg)
  assert(ao.isTrusted(msg),"Not trusted message")
  assert(Pools[msg.From]~=nil,"The pool does not exist")
  local rewards = msg.Data.rewards
  local win_rates = {}
  for k,v in pairs(rewards) do
    if not Players[k][msg.From] then Players[k][msg.From] = {0,0,0,0,0} end
    utils.increase(Players[k][msg.From],{0,0,0,v[1],v[1]})
    local rate = v[1]/v[2]
    if rate > 0 then
      table.insert(win_rates,{
        player = k,
        pool = msg.From,
        currecy = Pools[msg.From].currecy,
        reward = v[1],
        bet = v[2],
        rate = rate,
        ts = msg.Timestamp
      })
    end
    if #win_rates>0 then
      local new_leaderboard = utils.concat(Leaderboard,win_rates)
      table.sort(new_leaderboard, function(a, b) return a.rate > b.rate end)
      if #new_leaderboard >50 then
        for i = 51, #new_leaderboard do
          table.remove(new_leaderboard, 51)
        end
      end
      Leaderboard = new_leaderboard
    end
  end
  utils.increase(State,{total_draws = 1})
end)


-- This function processes the "claim" action, handling the player's claim process.
-- It verifies the player's balance, calculates the tax, and initiates the transfer process.
-- It also updates the player's balance, the pool's balance, and the taxation records.
Handlers.add("claim",{
  Action="Claim",
  From = function(from) return Players[from]~=nil end,
  Pool = function(pid) return Pools[pid]~=nil end,
},function(msg)
  local player = Players[msg.From]
  local pool = Pools[msg.Pool]
  local stat = player and player[msg.Pool] or nil
  local balance = stat and stat[5] or 0
  assert(balance >= math.max(pool.withdraw_min,10),"Insufficient amount to claim.")
  local tax = balance * math.max(pool.tax,0.1)
  local user_quantity = balance - tax
  
  if balance >= math.max(pool.withdraw_min,10) then
    local tax = balance * pool.tax
    local quantity = balance - tax
    Send({
      Target = pool.token,
      Action = "Transfer",
      Recipient = msg.From,
      Quantity = string.format("%.0f", quantity),
      ['X-Transfer-Type'] = "Claim",
      ['X-Amount'] = string.format("%.0f", balance),
      ['X-Tax'] = string.format("%.0f", tax),
      ['X-Tax-Rate'] = string.format("%.0f", pool.tax),
      ['X-Taxer'] = TAXER or Owner,
      ['X-Pool'] = msg.Pool or pool.id
    }).onReply(function(tx)
      if tx.Action == "Debit-Notice" then
        local amount = tonumber(tx['X-Amount'])
        local player_id = tx.Recipient or msg.From
        local pool_id = tx['X-Pool']
        if Players[player_id] and Players[player_id][pool_id] then
          utils.decrease(Players[player_id][pool_id],{0,0,0,0,amount})
        end
        if Balances[tx.From] then
          utils.decrease(Balances[tx.From],{amount,0,-amount})
          utils.increase(State,{total_cliams=1})
          Taxation = Taxation or {}
          if not Taxation[tx.From] then Taxation[tx.From] = {0,0,0} end
          local tax_amount = tonumber(tx['X-Tax'])
          utils.increase(Taxation[tx.From],{tax_amount,tax_amount,0})
        end
      else
        FailedTransactions = FailedTransactions or {}
        table.insert(FailedTransactions,{
          id=tx.Id,type=tx['X-Transfer-Type'],
          quantity=tx.Quantity,
          recipient = tx.Recipient,
          ts_created = tx.Timestamp})
        print("Player fails to claim prize")
      end
    end)
  end
end)

-- This function handles the "pools" action, sending a list of all non-hidden pools to the client.
-- It iterates through the Pools table, adding non-hidden pools to a local table, then sorts them by their addition timestamp.
-- Finally, it sends the sorted list back to the client.
Handlers.add("pools", "Pools", function(msg)
  local pools = {}
  for k,pool in pairs(Pools) do
    if not pool.hidden then
      table.insert(pools,pool)
    end
  end
  table.sort(pools, function(a, b) return a.ts_added > b.ts_added end)
  msg.reply({Data = pools})
end)




-- This function adds or updates a pool with the specified pid.
-- If the pool exists, it synchronizes the pool information; otherwise, it adds a new pool.
-- It sends an "Info" action to the pool and updates the pool's information based on the reply.
-- It also updates the authorities list if the pool is not already included.
Handlers.addPool = function(pid)
  if Pools[pid] then
    print("🔄 Sync Pool [ "..pid.." ] ...")
  else
    print("🆕 Add Pool [ "..pid.." ] ...")
  end
  
  Send({
    Target = pid,
    Action = "Info"
  }).onReply(function(msg)
    local print_text = "✅ The pool [ " .. msg.From .." ] is synchronized."
    if not Pools[msg.From] then
      Pools[msg.From] = {}
      utils.increase(State,{total_pools = 1})
      print_text = "✅ The pool [ " .. msg.From .." ] is added."
    end

    local pool = Pools[msg.From]

    utils.update(Pools[msg.From],{
      id = msg.From,
      token = msg.Token or pool.token,
      name = msg.Name or pool.name,
      currency = msg.Currency,
      logo = msg.Logo or pool.logo,
      agent = msg.Agent or pool.agent,
      timer = msg.Timer or pool.timer,
      tax = tonumber(msg.Tax) or pool.tax,
      price = tonumber(msg.Price) or pool.price,
      digits = tonumber(msg.Digits) or pool.digits,
      draw_delay = tonumber(msg['Draw-Delay']) or pool.draw_delay,
      jackpot_scale = tonumber(msg['Jackpot-Scale']) or pool.jackpot_scale,
      withdraw_min = tonumber(msg['Withdraw-Min']) or pool.withdraw_min,
      state = type(msg.Data) == "table" and msg.Data or pool.state,
      ts_added = pool.ts_added or msg.Timestamp,
      sold = pool.sold or {0,0,0},
      type = msg['Pool-Type']
    })
    
    if not utils.includes(msg.From,ao.authorities) then
      table.insert(ao.authorities,msg.From)
    end
    print(print_text)
  end)
end

-- This function removes a pool with the specified pid.
-- It also removes the pool from the authorities list if it exists.
Handlers.removePool = function(pid)
  if Pools[pid] then
    Pools[pid] = nil
  end
  if utils.includes(pid,ao.authorities) then
    for i,v in ipairs(ao.authorities) do
      if v==pid then
        table.remove(ao.authorities,i)
      end
    end
  end
  print("Pool ["..pid.."] has been removed.")
end

-- This function updates the specified pool(s).
-- If no pool is specified, it updates all pools.
-- It calls the addPool function for each specified pool or all pools if none are specified.
Handlers.updatePools = function(...)
  local n = select("#", ...)
  if n and n > 0 then
    for i = 1, n do
      local pid = select(i, ...)
      if Pools[pid] then Handlers.addPool(pid) end
    end
  else
    for k,v in pairs(Pools) do
      if k then Handlers.addPool(k) end
    end
  end
end

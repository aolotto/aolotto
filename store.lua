local ao = require(".ao")
local drive = require("modules.drive")
local utils = require("modules.utils")
local crypto = require(".crypto")


State = State or {}
Pools = Pools or  {}
Players = Players or {}
Notices = Notices or {}
Balances = Balances or {}


Handlers.add("forward-ticket",{
  Action = "Credit-Notice",
  Quantity = "%d+",
  ['X-Pool'] = function(pid,m) return Pools[pid]~= nil and Pools[pid].price <= tonumber(m.Quantity) end,
  ['X-Numbers'] = "_",
  From = function(from,m) return Pools[m['X-Pool']].token == from end
},function(msg)
  msg.forward(msg['X-Pool'],{Action = "Ticket-Notice",Token=msg.From})
end)



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

Handlers.add("draw-notice","Draw-Notice",function(msg)
  assert(ao.isTrusted(msg),"Not trusted message")
  assert(Pools[msg.From]~=nil,"The pool is not exists")
  local notice = {
    type = "Draw-Notice",
    id= msg.Id,
    data=msg.Data,
    title = "",
    content = "",
    ts_created = msg.Timestamp
  }
  table.insert(Notices,notice)
  local rewards = msg.Data.rewards
  for k,v in pairs(rewards) do
    if not Players[k][msg.From] then Players[k][msg.From] = {0,0,0,0,0} end
    utils.increase(Players[k][msg.From],{0,0,0,v,v})
  end
end)


Handlers.addPool = function(pid)
  print("Adding or updating pool ...")
  Send({
    Target = pid,
    Action = "Info"
  }).onReply(function(msg)
    print(msg['Pool-Type'])
    if not Pools[msg.From] then
      Pools[msg.From] = {}
      utils.increase(State,{total_pools = 1})
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
    print("The pool [" .. msg.From .."] has been added or updated.")
  end)
end

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



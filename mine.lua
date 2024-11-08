--[[
  Extend the token interface, 
  allowing the AGENT to mint new tokens for betting and mining, 
  with each minting being 0.01% of the balance (MaxSupply - TotalSupply).
]]

local bint = require('.bint')(256)
local json = require('json')

--[[
  utils helper functions to remove the bint complexity.
]]
--

local utils = {
  add = function (a,b) 
    return tostring(bint(a) + bint(b))
  end,
  subtract = function (a,b)
    return tostring(bint(a) - bint(b))
  end,
  toBalanceValue = function (a)
    return tostring(bint(a))
  end,
  toNumber = function (a)
    return tonumber(a)
  end
}


STORE = STORE or "_5mdWhc-dWnFXeghS10acKtAFl8n2YtA0XxYJelEqY0"
assert(type(STORE) == "string" and string.len(STORE) == string.len(ao.id), "STORE address is incorrect.")
MaxSupply = MaxSupply or string.format("%.0f",210000000 * 10 ^ Denomination)
TotalSupply = TotalSupply or utils.toBalanceValue(10000 * 10 ^ Denomination)
Pools = Pools or {}
Miners = Miners or {}

Handlers.add('mine',{
  Action = "Mining",
  From = function(from) return Pools[from] ~= nil end,
  Player = "_",
  ['X-Mine-Amount'] = "%d+",
  ['X-Mine-Token'] = ao.id
},function(msg)
  print("Mining for "..msg.Player)
  local id = msg.From
  local miner = msg.Player

  local miningPool = Pools[id]
  local avalable = miningPool.avalable
  assert(bint(msg['X-Mine-Amount']) <= bint(avalable), "no more avalable assets to mined.")
  local quantity = msg['X-Mine-Amount']

  if not Balances[miner] then Balances[miner] = "0" end
  if not Miners[miner] then Miners[miner] = "0" end
  Balances[miner] = utils.add(Balances[miner], quantity)
  Miners[miner] = utils.add(Miners[miner], quantity)
  TotalSupply = utils.add(TotalSupply, quantity)
  Pools[id].avalable = utils.subtract(avalable,quantity)
  Pools[id].mined = utils.add(Pools[id].mined,quantity)
  Pools[id].count_mine = utils.add(Pools[id].count_mine or "0","1")
  Miners[miner] = utils.add(Miners[miner] or "0",quantity)
  MiningQuota = utils.subtract(MiningQuota or "0",quantity)
  Mine_Ref = (Mine_Ref or 0) + 1

  local message = {
    Action = "Mine-Notice",
    Miner = miner,
    Quantity = quantity,
    ['Pool-Available-Before'] = avalable,
    ['Pool-Available-Current'] = Pools[id].avalable,
    ['Pool-Mined-Current'] = Pools[id].mined,
    ['Miner-Balance'] = Balances[miner],
    Currency = table.concat({Ticker,Denomination,Logo},","),
    ['Pushed-For']=msg['Pushed-For'],
    Data={tonumber(Pools[id].avalable), tonumber(Pools[id].mined), Pools[id].productivity}
  }

  -- Add forwarded tags to the credit and debit notice messages
  for tagName, tagValue in pairs(msg) do
    -- Tags beginning with "X-" are forwarded
    if string.sub(tagName, 1, 2) == "X-" then
      message[tagName] = tagValue
    end
  end

  msg.reply(message)
end)

Handlers.addMiningQuota = function(id,msg)
  assert(Pools[id]~=nil,"the pool is not exists")
  local productivity = Pools[id].productivity
  local unsupply = utils.subtract(MaxSupply,TotalSupply)
  unsupply = utils.subtract(unsupply,MiningQuota or 0)
  assert(tonumber(unsupply)>=1,"no more token to mine")
  local amount = math.max(tonumber(unsupply) * tonumber(productivity),1)
  Pools[id].avalable = utils.add(Pools[id].avalable or "0",amount)
  Pools[id].count_add_quota = utils.add(Pools[id].count_add_quota or "0", "1")
  Pools[id].latest_add_quota = msg.Timestamp or os.time()
  MiningQuota = utils.add(MiningQuota or "0",amount)
  Quota_Ref = (Quota_Ref or 0) + 1
  Send({
    Target = id,
    Action = "Quota-Added",
    Store = STORE,
    Amount = string.format("%.0f",amount),
    No = string.format("%.0f",Quota_Ref),
    ['Pool-Available-Current'] = Pools[id].avalable,
    ['Pool-Mined-Current'] = Pools[id].mined,
    Currency = table.concat({Ticker,Denomination,Logo},","),
    Token = ao.id,
    ['Pushed-For']=msg['Pushed-For'] or "",
    Data={tonumber(Pools[id].avalable), tonumber(Pools[id].mined), Pools[id].productivity}
  })
end

Handlers.add("add-mining-quota",{
  Action = "Quota-Requsting",
  From = STORE,
  ['X-Origin'] = function(pid) return Pools[pid]~=nil end
},function(msg)
  Handlers.addMiningQuota(msg['X-Origin'],msg)
end)


Handlers.add("add-mining-pool",{
  From = STORE,
  Action = "Add-Mining-Pool",
  Pool = "_",
  Productivity = "%d+"
},function(msg)
  local id = msg.Pool
  if not Pools then Pools = {} end
  if not Pools[msg.Pool] then Pools[msg.Pool] = {} end
  Pools[id].productivity = Pools[id].productivity or math.min(tonumber(msg.Productivity),0.0001)
  Pools[id].ts_created = Pools[id].ts_created or msg.Timestamp
  Pools[id].avalable = Pools[id].avalable or "0"
  Pools[id].mined = Pools[id].mined or "0",
  ao.addAssignable("assignments_from_"..id.."_to_store",{
    Target = msg.From,
    From = msg.Pool
  })

  msg.reply({
    Action = "Mining-Pool-Added",
    Pool = id,
    Productivity = msg.Productivity,
    Token = ao.id,
    Currency = table.concat({Ticker,Denomination,Logo},","),
    Data = {tonumber(Pools[id].avalable), tonumber(Pools[id].mined), Pools[id].productivity}
  })
end)


Handlers.add("get-dividend-snap",{
  Action = "Get-Dividend-Snap"
},function(msg)
  if msg.reply then
    msg.reply({Action="Reply-Dividend-Snap",Total=TotalSupply,Data=Balances})
  else
    Send({Target=msg.From,Action="Reply-Dividend-Snap",Total=TotalSupply,Data=Balances})
  end
end)
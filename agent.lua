local bint = require('.bint')(256)

local utils = {
  add = function(a, b)
    return tostring(bint(a) + bint(b))
  end,
  subtract = function(a, b)
    return tostring(bint(a) - bint(b))
  end,
  multiply = function(a, b)
    return string.format("%.f",bint(a) * bint(b))
  end,
  divide = function(a, b)
    return string.format("%.f",bint(a) / bint(b))
  end,
  divisible = function(a,b)
    return string.format("%.0f",bint.tonumber(a) // bint.tonumber(b))
  end,
  toBalanceValue = function(a)
    return string.format("%.0f",bint.tonumber(a))
  end,
  toNumber = function(a)
    return bint.tonumber(a)
  end
}

TOKEN = TOKEN or "KCAqEdXfGoWZNhtgPRIL0yGgWlCDUl0gvHu8dnE5EJs"
MaxSupply = MaxSupply or string.format("%.0f",210000000 * 10 ^ Denomination)
-- TotalSold = TotalSold or "0"
TotalMined = TotalMined or "0"
TotalQuota = TotalQuota or "0"
-- Profits = Profits or {"0","0","0"}
Pools = Pools or {}
-- Minings = Minings or {}


Handlers.add("bet_and_mine",{
  Action="Credit-Notice",
  From = TOKEN,
  Quantity = "%d+",
  ['X-Pool'] = function(pool,m) return Pools[pool] ~= nil and utils.toNumber(Pools[pool].price) <= utils.toNumber(m.Quantity) end,
  ['X-Numbers'] = "_",
},function(msg)
  local pool = Pools[msg['X-Pool']]
  local count,amount = Handlers.computeBets(msg.Quantity,pool.price)
  local fwdMsg = {Action = "Save-Lotto",Count=count,Amount=amount}
  if utils.toNumber(pool.quota[1]) >= 1 then
    local mined = Handlers.mine(msg['X-Pool'],amount,msg.Sender)
    fwdMsg['X-Mined'] = mined..","..Ticker..","..Denomination..","..ao.id
    fwdMsg.Data = {quota = Pools[msg['X-Pool']].quota, miner = {id = msg.Sender, balance = Balances[msg.Sender]}}
  end
  msg.forward(msg['X-Pool'], fwdMsg)
end)

Handlers.add("query_minning_quota",{
  Action="Mining-Quota",
  Pool="_"
},function(msg)
  if Pools[msg.Pool] then
    msg.reply({Data=Pools[msg.Pool]})
  end
end)

Handlers.add("reset_quota_by_archive_round",{
  From = function(_from) return Pools[_from] ~= nil end,
  Action = "Archive"
},function(msg)
  Handlers.resetQuota(msg.From)
  msg.reply({
    Action = "Archived",
    Round = msg.Round,
    ['Archive-Id'] = msg.Id,
    Data = Pools[msg.From]
  })
end)

Handlers.add("claiming",{
  Action = "Claiming",
  From = function(_from) return Pools[_from] ~= nil end,
  Quantity = "%d+",
  Recipient = "_",
},function(msg)
  local trans = {
    Target = TOKEN,
    Action = "Transfer",
    Quantity = msg.Quantity,
    Recipient = msg.Recipient,
    ['Pushed-For'] = msg['Pushed-For']
  }
  for tagName, tagValue in pairs(msg) do
    if string.sub(tagName, 1, 2) == "X-" then
      trans[tagName] = tagValue
    end
  end

  Send(trans).onReply(function(m)
    if m.Action == "Debit-Notice" then
      m.forward(msg.From)
    end
  end)
end)


Handlers.mine = function(pid,quantity,user)
  local pool = Pools[pid]
  local _unit = math.max(utils.divisible(pool.quota[1],2100),"1")
  local _count = utils.divide(quantity, pool.price)
  local mined = string.format("%.0f", utils.toNumber(_unit) * utils.toNumber(_count))

  -- 增加挖矿数量
  TotalMined = utils.add(TotalMined,mined)
  Pools[pid].mined = utils.add(Pools[pid].mined,mined)
  -- Minings[user] = utils.add(Minings[user] or 0, mined)
  -- 减少挖矿配额
  TotalQuota = utils.subtract(TotalQuota,mined)
  Pools[pid].quota[1] = utils.subtract(pool.quota[1], mined)
  -- 增加发行量
  TotalSupply = utils.add(TotalSupply,mined)
  if not Balances[user] then
    Balances[user] = "0"
    Holders = utils.add(Holders,1)
  end
  Balances[user] = utils.add(Balances[user], mined)
  return utils.toBalanceValue(mined)
end


Handlers.addPool = function(id)
  print("Add pool > "..id)
  Send({
    Target = id,
    Action = "Info"
  }).onReply(function(m)
    if  Pools[id] == nil then
      Pools[id] = {
        price = m.Price,
        tax = m.Tax,
        max_bet = m['Max-Bet'],
        min_claim = m['Withdraw-Min'],
        quota = {"0","0"},
        mined = "0",
      }
      print("Pool ["..id.."] has been added.")
      Handlers.resetQuota(id)
    else
      Pools[id].price = m.Price
      Pools[id].tax = m.Tax
      Pools[id].max_bet = m['Max-Bet']
      Pools[id].min_claim = m['Withdraw-Min']
      print("Pool ["..id.."] has been updated.")
    end
  end)
end

Handlers.resetQuota = function(id)
  assert(Pools[id] ~= nil, "The Pool does not exist")
  local unsupply = utils.subtract(MaxSupply, TotalSupply)
  local reserve_quota = Pools[id].quota[1]
  local freezed_quota = utils.subtract(TotalQuota,reserve_quota)
  local base_quota = utils.subtract(unsupply,freezed_quota)
  local reset_quota = math.max(utils.divisible(base_quota, 2100),"1")

  -- print(utils.toBalanceValue(utils.add(freezed_quota,reset_quota)))
  local _quota = utils.toBalanceValue(reset_quota)
  Pools[id].quota = {_quota,_quota}
  TotalQuota = utils.toBalanceValue(utils.add(freezed_quota,reset_quota))

  print("The quota of ["..id.."] is reseted to :"..reset_quota)

end




Handlers.computeBets = function(quantity,price)
  local count = math.floor(utils.toNumber(quantity) / utils.toNumber(price))
  local amount = utils.toNumber(price) * count
  return utils.toBalanceValue(count), utils.toBalanceValue(amount)
end


Handlers.test =function(a,b)
  local c = math.max(utils.divisible(a,b),"8000000")
  print(c)
end
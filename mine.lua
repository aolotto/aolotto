--[[
  Extend the token interface, 
  allowing the AGENT to mint new tokens for betting and mining, 
  with each minting being 0.01% of the balance (MaxSupply - TotalSupply).
]]

local bint = require('.bint')(256)
local ao = require('.ao')
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


STORE = STORE or "l0RxEkP1pTaFA8J09aNjcGi9QD4Sz9VPNKnFxc3fch0"
MINE_RATIO = MINE_RATIO or 0.0001


--[[
  Expose mint interface to aolotto
]] --

Handlers.add(
  'mine',
  {
    Action = "Mine",
    From = STORE,
    Miner = "_",
    Productivity = "%d+"
  },
  function(msg)

    if not MaxSupply then MaxSupply = utils.toBalanceValue(bint(210000000) * bint(10) ^ bint(Denomination)) end
    
    if not Balances[msg.From] then Balances[msg.From] = "0" end
    if not NumberOfMine then NumberOfMine = 0 end

    local unSupplied = utils.subtract(MaxSupply,TotalSupply)
    local productivity =  math.min(tonumber(msg.Productivity),1)
    
    assert(bint(unSupplied) > 0, 'The total supply has reached its maximum limit!')
    local quantity = string.format("%.f",bint.__mul(unSupplied * productivity, MINE_RATIO or 0.0001))
    Balances[msg.From] = utils.add(Balances[msg.From], quantity)
    TotalSupply = utils.add(TotalSupply, quantity)
    NumberOfMine = NumberOfMine + 1


    msg.reply({
      Action = "Mined",
      Quantity = quantity,
      Productivity = tostring(productivity),
      Miner = msg.Miner,
      ['Mine-Count'] = tostring(NumberOfMine),
      Data = "Successfully Mined : " .. quantity .. " for " .. msg.Miner
    })


end)


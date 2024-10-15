--[[
  Extend the token interface, 
  allowing the Agent to mint new tokens for betting and mining, 
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


AGENT = AGENT or "fqDCPQubE9azVpiB92FOXb-ydwkqCiQH9y-p3e53RT0"
MINE_RATIO = MINE_RATIO or 0.0001


--[[
  Expose mint interface to aolotto
]] --

Handlers.add(
  'mine',
  {
    Action = "Mine",
    From = AGENT,
    Pool = "_",
    Round="%d+"
  },
  function(msg)
    assert(type(msg.Round) == 'string', 'Round is required!')

    if not MaxSupply then MaxSupply = utils.toBalanceValue(bint(210000000) * bint(10) ^ bint(Denomination)) end
    
    if not Balances[msg.From] then Balances[msg.From] = "0" end
    if not NumberOfMine then NumberOfMine = 0 end

    local unSupplied = utils.subtract(MaxSupply,TotalSupply)
    
    assert(bint(unSupplied) > 0, 'The total supply has reached its maximum limit!')
    local quantity = string.format("%.f",bint.__mul(unSupplied, MINE_RATIO or 0.0001))
    Balances[msg.From] = utils.add(Balances[msg.From], quantity)
    TotalSupply = utils.add(TotalSupply, quantity)
    NumberOfMine = NumberOfMine + 1

    Send({
      Target = msg.From,
      Action = "Mined",
      Quantity = quantity,
      Pool = msg.Pool,
      Round = msg.Round,
      ['Mine-Count'] = tostring(NumberOfMine),
      Data = "Successfully Mined Token : " .. quantity
    })

end)


local bint = require('.bint')(256)
local ao = require('ao')
local json = require('json')
local const = require("modules.const")

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

--[[
     Initialize State
   ]]
--

AOLOTTO = AOLOTTO or "2vheopvdwEfont-jQC_G9--6bV2hGn-IzlHxsq4CLWY"


--[[
  Expose mint interface to aolotto
]] --

Handlers.add('mintRewards',Handlers.utils.hasMatchingTag('Action',const.Actions.mint_rewards),function(msg)
  assert(type(msg.Round) == 'string', 'Round is required!')

  if not MaxSupply then MaxSupply = utils.toBalanceValue(210000000 * 10 ^ Denomination) end
  
  if not Balances[msg.From] then Balances[msg.From] = "0" end
  if not NumberOfMinted then NumberOfMinted = 0 end
  if not MintLogs then MintLogs = {} end

  if msg.From == AOLOTTO then
    local UnSupplied = utils.subtract(MaxSupply,TotalSupply)
    assert(bint(UnSupplied) > 0, 'The total supply has reached its maximum limit!')
    local Quantity = utils.toBalanceValue(math.floor(bint(UnSupplied) * 0.0001))
    Balances[msg.From] = utils.add(Balances[msg.From], Quantity)
    TotalSupply = utils.add(TotalSupply, Quantity)
    NumberOfMinted = NumberOfMinted + 1
    
    local msssage = {
      Target = msg.From,
      Action = "Minted",
      Round = msg.Round,
      Quantity = tostring(Quantity),
      Data = "Successfully minted "
    }
    -- table.insert(MintLogs,{
    --   id = msg.Id,
    --   minter = msg.From,
    --   quantity = Quantity,
    --   timestamp = msg.Timestamp,

    -- })
    ao.send(msssage)
  else
    ao.send({
      Target = msg.From,
      Action = 'Mint-Error',
      ['Message-Id'] = msg.Id,
      Error = 'Only the Process Id can mint new ' .. Ticker .. ' tokens!'
    })
  end
end)
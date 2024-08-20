local const = require("modules.const")
local utils = require(".utils")
local Refund = {}

function Refund:refundToParticipantInBets(bets,token_process)
  for key, value in pairs(bets) do
    local qty = 0
    for k, v in pairs(value.numbers) do
      qty = qty + v
    end
    local message = {
      Target = token_process,
      Action = "Transfer",
      Recipient = tostring(key),
      Quantity = tostring(qty),
      [const.Actions.x_transfer_type] = const.Actions.refund
    }
    ao.send(message)
  end
end


function Refund:rejectToken(msg)
  assert(msg.Sender ~= nil, "Missed Sender.")
  assert(msg.Quantity ~= nil and tonumber(msg.Quantity) > 0, "Missed Quantity.")
  local message = {
    Target = msg.From,
    Action = "Transfer",
    Recipient = msg.Sender,
    Quantity = msg.Quantity,
    [const.Actions.x_transfer_type] = const.Actions.reject
  }
  ao.send(message)
end

return Refund
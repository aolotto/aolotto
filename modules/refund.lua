local const = require("modules.const")
local Refund = {}

function Refund:refundToParticipantInBets(bets,token_process)
  for key, value in pairs(bets) do 
    local message = {
      Target = token_process,
      Actions = "Transfer",
      Recipient = tostring(key),
      Amount = tostring(value.bets_amount),
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
local Refund = {}

function Refund:refundToParticipantInBets(bets,token_process)
  for key, value in pairs(bets) do 
    local message = {
      Target = token_process,
      Recipient = tostring(key),
      Amount = tostring(value.bets_amount)
    }
  end
end

return Refund
--[[ 奖金赞助 ]]
Handlers.add(
  '_credit_sponsor',
  function (msg)
    if msg.From == TOKEN.Process 
      and msg.Tags.Action == "Credit-Notice" 
      and msg.Tags[const.Actions.x_transfer_type] == const.Actions.sponsor
    then
      return true
    else
      return false
    end
  end,
  function (msg)
    xpcall(function (msg)
      assert(type(msg.Quantity) == 'string', 'Quantity is required!')
      CURRENT.buff = (CURRENT.buff or 0) + tonumber(msg.Quantity)
      STATE:increasePoolBalance(msg.Quantity)
      STATE:increaseOperatorBalance(msg.Quantity)
    end,function(err)
      print(err)
      messenger:sendError(err,msg.Tags.Sender)
    end, msg)
  end
)

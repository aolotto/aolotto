local utils = require(".utils")
local ao = require(".ao")

Subscriptions = Subscriptions or {}

Handlers.add("cron",Handlers.utils.hasMatchingTag("Action","Cron"),function(msg)
  
  if #Subscriptions > 0 then
    for i,v in pairs(Subscriptions) do
      if msg.Timestamp >= v.Timestamp then
        print("send time-up to "..v.Process)
        ao.send({
          Target = v.Process,
          Action = "Time-Up"
        })
        Subscriptions[i] = nil
      end
    end
  else
    return
  end
end)

Handlers.add("add-subscription",Handlers.utils.hasMatchingTag("Action","Add-Subscription"),function(msg)
  print("add-subscription")
  if ao.isTrusted(msg) then
    table.insert(Subscriptions,{
      Process = msg['From-Process'] or msg.From,
      Timestamp = tonumber(msg.Time)
    })
  end
end)

Handlers.add("add-subscriber",Handlers.utils.hasMatchingTag("Action","Add-Subscriber"),function(msg) 
  print("add-subscriber")
  assert(msg.Subscriber ~= nil,"missed process tag")
  if msg.From == Owner then
    table.insert(ao.authorities,msg.Subscriber)
    msg.reply({
      Action = "Subscriber-Added"
    })
  end
end)
local const = require("modules.const")
local Messenger = {}

function Messenger:replyUserBets(target, options)
  local user_bets = options.user_bets
  local no = options.no
  local request_type = options.request_type
  local data_str = ""
  if user_bets and user_bets.count > 0 then
    local total_numbers = 0
    local total_bets = 0
    local bets_str = "\n"..string.rep("-", 58).."\n"
    for key, value in pairs(user_bets.numbers) do
      total_numbers = total_numbers + 1
      total_bets = total_bets + value
      bets_str = bets_str .. string.format(" %03d *%5d ",key,value) .. (total_numbers % 4 == 0 and "\n"..string.rep("-", 58).."\n" or " | ")
    end
    data_str = string.format([[You've placed %d bets that cover %d numbers on Round %s : ]],total_bets,total_numbers,no)..bets_str
  else
    data_str = string.format("You don't have any bets on aolotto Round %s.",no)
  end
  local message = {
    Target = target,
    Action = const.Actions.reply_user_bets,
    Data = (request_type == "json") and json.encode(user_bets.numbers) or data_str
  }
  ao.send(message)
end

function Messenger:forwardTo(target,msg)
  local message = {
    Target = target,
    Data = msg.Data,
    User = msg.From,
  }
  local exclude = {["From-Module"] = true, ["Variant"] = true, ["Data-Protocol"] = true, ["Ref_"] = true}
  for key , val  in pairs(msg.Tags) do
    if not exclude[key] then
      message[key] = val
    end
  end
  ao.send(message)
end

return Messenger
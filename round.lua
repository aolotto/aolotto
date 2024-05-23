ROUND = 1
AOLOTTO = "wqwklmuSqSPGaeMR7dHuciyvBDtt1UjmziAoWu-pKuI"
_STATE  = {
  ended = nil
}
Bets = {}
Bet_logs = {}
_utils = {}

local crypto = require(".crypto")
local bint = require('.bint')(256)
local json = json or require("json")






Handlers.add(
  'saveNumbers',
  function (msg)
    local AOLOTTO = AOLOTTO or "wqwklmuSqSPGaeMR7dHuciyvBDtt1UjmziAoWu-pKuI"
    if msg.From == AOLOTTO and msg.Tags.Action == "SaveNumbers" and msg.Tags["User"] then
      return true
    else
      return false
    end
  end,
  function (msg)
    xpcall(function (msg)
      if not msg.Quantity then return end
      local json = json or require("json")
      local bets = json.decode(msg.Data)
      -- 保存用户的bets
      Bets = Bets or {}
      local bet_uid = msg.Donee or msg.User
      local user_bets_table = Bets[bet_uid] or {}
      for i, v in ipairs(bets) do
        local num = v[1]
        local qty = v[2]
        local cur_qty = user_bets_table[v[1]] or 0
        user_bets_table[num] = cur_qty + qty
      end
      Bets[bet_uid] = user_bets_table
      -- 保存用户参与记录
      local log = {
        ['Timestamp'] = msg.Timestamp,
        ['User'] = msg.User,
        ['Bets'] = bets,
        ['Donee'] = msg.Donee or nil,
        ['Quantity'] = msg.Quantity,
        ['Id'] = msg.Id
      }
      table.insert(Bet_logs,log)

      -- 下发消息
      local data_str = string.format("Placed %d bet%s in aolotto Round %d , with the numbers: %s",tonumber(msg.Quantity),tonumber(msg.Quantity)>1 and "s" or "",ROUND or tonumber(msg.Round),msg.Data )
      local tags = {
        Target = msg.User,
        Action = "Lotto-Notice",
        Data = data_str,
        Quantity = msg.Quantity,
        Round = tostring(ROUND) or msg.Round,
        AOLOTTO = AOLOTTO,
        ["Pushed-For"] = msg.Tags["Pushed-For"],
        ["X-Numbers"] = msg.Tags["X-Numbers"]
      }
      if msg.Donee then
        tags['Donee'] = msg.Donee
      end
      ao.send(tags)
    end,function (err) print(err) end, msg)
  end
)

Handlers.add(
  'autoDraw',
  function (msg)
    local SHOOTER = SHOOTER or "7tiIWi2kR_H9hkDQHxy2ZqbOFVb58G4SgQ8wfZGKe9g"
    if not _STATE.ended and msg.From == SHOOTER and msg.Tags.Action == "1m_shoot" then
      return true
    else
      return false
    end
  end,
  function (msg)
    print("自动检查是否开奖")
  end
)

Handlers.add(
  'manualDraw',
  function (msg)
    if not _STATE.ended and msg.Tags.Action == "ManualDraw" then
      return true
    else
      return false
    end
  end,
  function (msg)
    print("手工检查是否开奖")
  end
)

Handlers.add(
  'fetchBets',
  Handlers.utils.hasMatchingTag("Action","FetchBets"),
  function (msg)
    local json = json or require("json")
    local user_bets_table = Bets[msg.From]
    local message = {
      Target = msg.From,
      Action = "ReplyUserBets",
      Data=json.encode(user_bets_table)
    }
    ao.send(message)
  end
)

Handlers.add(
  'fetchInfo',
  Handlers.utils.hasMatchingTag("Action","Info"),
  function (msg)
    local json = json or require("json")
    local user_bets_table = Bets[msg.From]
    local message = {
      Target = msg.From,
      Action = "ReplyUserBets",
      Data=json.encode(user_bets_table)
    }
    ao.send(message)
  end
)
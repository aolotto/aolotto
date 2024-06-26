local const = require("modules.const")
local messenger = require("modules.messenger")
local _config = require("_config")
local utils = require(".utils")
local json = require("json")
if not AGENT then  AGENT = _config.AGENT end
if not TOKEN then TOKEN =  _config.TOKEN end
if not utils.includes(AGENT, ao.authorities) then table.insert(ao.authorities,AGENT) end



local _archive = {}
function _archive:save(data)
  self.data = data
end


if not ARCHIVES then ARCHIVES = {data={}} end
setmetatable(ARCHIVES,{__index=_archive})


Handlers.add(
  "_archive_round",
  function(msg)
    if msg.From == AGENT and msg.Tags.Action == const.Actions.archive_round then return true else return false end
  end,
  function(msg)
    assert(msg.Tags.Round ~= nil, "Missed round tag.")
    ARCHIVES:save(json.decode(msg.Data))
    ao.send({
      Target = msg.From,
      Action = const.Actions.round_archived,
      Round = msg.Tags.Round,
    })
  end  
)

Handlers.add(
  'fetchBets',
  Handlers.utils.hasMatchingTag("Action",const.Actions.bets),
  function (msg)
    xpcall(function (msg)
      if msg.Round == ARCHIVES.data.no then
        print(msg.User)
        local user_bets = ARCHIVES.data.bets[msg.User]
        assert(user_bets~=nil, "no bets you pleaced in this round.")
        messenger:replyUserBets(msg.User,{
          user_bets = user_bets,
          request_type = msg.RequestType or "",
          no = ARCHIVES.data.no
        })
      end
    end,function (err)
      print(err)
    end,msg)
  end
)

Handlers.add(
  "getRoundInfo",
  Handlers.utils.hasMatchingTag("Action",const.Actions.get_round_info),
  function (msg)
    xpcall(function (msg)
      if msg.Round == ARCHIVES.data.no then
        messenger:sendRoundInfo(ARCHIVES.data, TOKEN, msg)
      end
        
    end,function (err)
      print(err)
      messenger:sendError(err,msg.From)
    end,msg)
  end
)
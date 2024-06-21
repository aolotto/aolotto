local const = require("modules.const")
local _config = require("_config")
local utils = require(".utils")
local json = require("json")
if not AGENT then  AGENT = _config.AGENT end
if not utils.includes(AGENT, ao.authorities) then table.insert(ao.authorities,AGENT) end


local _archive = {}
function _archive:save(round,archive)
  self.repo = self.repo or {}
  self.repo[round] = archive
end

function _archive:includes(round)
  if self.repo and self.repo[round]~=nil then return true else return false end
end

if not ARRCHIVES then ARRCHIVES = {repo={}} end
setmetatable(ARRCHIVES,{__index=_archive})


Handlers.add(
  "_archive_round",
  function(msg)
    if msg.From == AGENT and msg.Tags.Action == const.Actions.archive_round then return true else return false end
  end,
  function(msg)
    assert(msg.Tags.Round ~= nil, "Missed round tag.")
    if not ARRCHIVES:includes(msg.Tags.Round) then
      ARRCHIVES:save(msg.Tags.Round,json.decode(msg.Data))
      ao.send({
        Target = msg.From,
        Action = const.Actions.round_archived,
        Round = msg.Tags.Round,
        Data = ""
      })
    end
  end  
)
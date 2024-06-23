local utils = require(".utils")
local tools = require("modules.tools")
local const = require("modules.const")
local rounds = {}
function rounds:create(no,timestamp)
  local pre = tonumber(no) > 1 and self.repo[tostring(tonumber(no)-1)] or nil
  local expired = false

  if pre then
    expired = timestamp >= pre.start_time+(pre.duration*7)
    self.repo[pre.no].end_time = timestamp
    self.repo[pre.no].status = expired and -1 or 1
  end

  local base_rewards = 0
  if expired then
    base_rewards = pre.base_rewards
  else
    base_rewards = pre and math.floor((pre.bets_amount+pre.base_rewards)*0.5) or 0
  end

  self.repo[tostring(no)] = {
    no = tostring(no),
    base_rewards = base_rewards,
    bets_amount = 0,
    bets_count = 0,
    start_time = timestamp,
    status = 0,
    duration = self.duration or 86400000,
    participants = 0
  }
  self.current = tonumber(no)

  return self.repo[tostring(no)]
end

function rounds:set(no,data)
  if #self.repo > 0  then
    local key  = no and tostring(no) or tostring(self.current)
    self.repo[key] = data
  end
end

function rounds:get(no)
  if #self.repo > 0 then
    local key  = no and tostring(no) or tostring(self.current)
    return self.repo[key]
  else
    return
  end
end




function rounds:get(no)
  local key = no~=nil and tostring(no) or tostring(self.current)
  return self.repo[key]
end

return rounds
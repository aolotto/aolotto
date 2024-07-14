local tools = require("modules.tools")
local Current = {}

function Current:isParticipated(uid)
  assert(uid~=nil,"missed user id.")
  return self.bets[uid]
end

function Current:saveBets(bets,msg)
  local uid = msg.Donee or msg.Sender
  local participated = self.bets[uid]
  local user_bets_table = participated and self.bets[uid] or {}
  local numbers = user_bets_table.numbers or {}
  local count = user_bets_table.count or 0
  for i, v in ipairs(bets) do
    local num = v[1]
    local qty = v[2]
    numbers[tostring(num)] = (numbers[tostring(num)] or 0) + qty
    self.statistics[tostring(num)] = (self.statistics[tostring(num)] or 0) + qty
  end
  user_bets_table['numbers'] = numbers
  user_bets_table['count'] = msg.Donee and count or count + 1
  self.bets[uid] = user_bets_table

  -- 记录日志
  local log = {
    ['Timestamp'] = msg.Timestamp,
    ['User'] = msg.Sender,
    ['Bets'] = bets,
    ['Donee'] = msg.Donee or nil,
    ['Quantity'] = msg.Quantity,
    ['Id'] = msg.Id
  }
  table.insert(self.logs,log)

  -- 更新轮次信息
  self.bets_count = self.bets_count + 1
  self.bets_amount = self.bets_amount + tonumber(msg.Quantity)
  self.participants = (self.participants or 0) + (participated and 0 or 1)

  if self.start_time == 0 or self.start_time == nil then
    self.start_time = msg.Timestamp
  end

end

function Current:new(msg)

  local expired = msg.Timestamp >= self.start_time + self.duration * 7
  self.no = tostring(tonumber(self.no)+1)
  self.base_rewards = expired and self.base_rewards or math.floor((self.base_rewards+self.bets_amount) * 0.5)
  self.participants = 0
  self.bets_count = 0
  self.bets_amount = 0
  self.buff = expired and self.buff or 0
  self.start_time = msg.Timestamp
  self.start_height = msg['Block-Height']
  self.logs = {}
  self.bets = {}
  self.statistics = {}

end


function Current:archive(msg)
  local archive = {}
  for key,val in pairs(self) do
    archive[key] = val
  end
  archive.end_time = msg.Timestamp
  archive.end_height = msg['Block-Height']
  archive.status = (msg.Timestamp >= archive.start_time + archive.duration * 7) and -1 or 1
  return archive
end 


return Current
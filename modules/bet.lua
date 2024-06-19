local bet = {}

function bet:save(bets,msg)
  local uid = msg.Donee or msg.Sender
  local user_bets_table = {}
  self.bets = self.bets or {}
  if self.bets[uid] then
    user_bets_table = self.bets[uid]
  else
    local participants = ROUNDS[tostring(CURRENT_ROUND)].participants or 0
    ROUNDS[tostring(CURRENT_ROUND)].participants = participants + 1
  end
  local numbers = user_bets_table.numbers or {}
  local count = user_bets_table.count or 0
  for i, v in ipairs(bets) do
    local num = v[1]
    local qty = v[2]
    numbers[tostring(num)] = (numbers[tostring(num)] or 0) + qty
    self.statistics = self.statistics or {}
    self.statistics[tostring(num)] = (self.statistics[tostring(num)] or 0) + qty
  end
  user_bets_table['numbers'] = numbers
  user_bets_table['count'] = msg.Donee and count or count + 1
  self.bets[uid] = user_bets_table
end

function bet:log(bets,msg)
  self.logs = self.logs or {}
  local log = {
    ['Timestamp'] = msg.Timestamp,
    ['User'] = msg.Sender,
    ['Bets'] = bets,
    ['Donee'] = msg.Donee or nil,
    ['Quantity'] = msg.Quantity,
    ['Id'] = msg.Id
  }
  table.insert(self.logs,log)
end

function bet:archive(no)
  local archive = {
    logs = self.logs,
    bets = self.bets,
    round = ROUNDS[tostring(no)],
    no = no
  }
  self.logs = {}
  self.bets = {}
  self.statistics = {}
  return archive
end


return bet
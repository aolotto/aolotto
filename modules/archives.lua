local const = require("modules.const")
local json = require("json")
local tools = require("modules.tools")
local utils = require(".utils")
local Archives = {} 

function Archives:add(archive)
  self.repo = self.repo or {}
  self.repo[archive.no] =  archive
end

function Archives:draw( no, win_num )
  local archive = self.repo[no]
  assert(archive ~= nil, "round not exsits")
  assert(archive.no == no, "No is not equal。")
  local expired = archive.end_time >= archive.start_time + archive.duration * 7
  local winners = {}
  local rewards  = 0
  
  if not expired then

    rewards = math.floor( (archive.base_rewards + archive.bets_amount) * 0.5 )
    
    for key, value in pairs(archive.bets) do
      if value.numbers[win_num] then
          table.insert(winners, {
            id = key,
            matched_bets = value.numbers[win_num]
          })
      end
    end

    -- 统计获奖者的奖金比例
    if #winners > 0 then
      local total = utils.reduce(function (acc, v) return acc + v end)(0)(utils.map(function (val) return val.amount end)(winners))
      local per = math.floor(rewards/total)
      self.repo[no].total_win_bets = total
      self.repo[no].per_reward = per
      self.repo[no].total_rewarded = rewards
      utils.map(function (v, key)
        v["percent"] = v.amount / total
        v["rewards"] = math.floor(v.amount * per)
        v["winning_number"] = win_num
      end,winners)
    end

  end

  self.repo[no].winners = winners
  self.repo[no].win_num = win_num
  self.repo[no].rewards = rewards
  self.repo[no].expired = expired
  self.repo[no].drawn = true
  self.repo[no].status = expired and -1 or 1

  return winners, rewards
end

function Archives:set(no,data)
  self.repo = self.repo or {}
  self.repo[tostring(no)] = type(data) == "string" and data or json.encode(data)
end

function Archives:removeRawData(no)
  no = tostring(no)
  assert(self.repo[no]~=nil,"no target archive for "..no)
  assert(self.repo[no].archiver~=nil,"no archiver address.")
  self.repo[no].bets = nil
  self.repo[no].logs = nil
  self.repo[no].statistics = nil
  self.repo[no].winners = nil
  self.repo[no].archived = true
end


return Archives
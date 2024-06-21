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

function rounds:draw(archive,timestamp)
  local no = tostring(archive.no)
  local round = self.repo[no]
  local rewards = math.floor((round.base_rewards + round.bets_amount)*0.5)
  -- 构建抽奖结果表
  local draw_info = {}
  draw_info.round = no
  draw_info.raw_round_data = round
  draw_info.timestamp = timestamp
  draw_info.rewards = rewards
  -- 获取随机抽奖号
  local seed = string.format("seed_%s_%d_%d_%d",no,timestamp,round.bets_amount,round.bets_count)
  local win_num = tools:getRandomNumber(seed,3)
  draw_info.win_num = win_num
  -- 统计获奖者
  local winners = {}
  for key, value in pairs(archive.bets) do
    if value.numbers[win_num] then
        table.insert(winners, {
          id = key,
          amount = value.numbers[win_num]
        })
    end
  end
  draw_info.winners = winners
  -- 统计获奖者的奖金比例
  if #winners > 0 then
    local total = utils.reduce(function (acc, v) return acc + v end)(0)(utils.map(function (val) return val.amount end)(winners))
    local per = math.floor(rewards/total)
    draw_info.total_win_bets = total
    draw_info.per_reward = per
    utils.map(function (v, key)
      v["percent"] = v.amount / total
      v["rewards"] = math.floor(v.amount * per)
      v["matched"] = win_num
    end,winners)
  else
    draw_info.total_win_bets = 0
  end
  -- 更改轮次状态
  self.repo[no].drawn = true
  self.repo[no].winners_count = #winners
  self.repo[no].total_win_bets = draw_info.total_win_bets or 0
  self.repo[no].win_num = win_num
  self.repo[no].status = 1
  -- 增加奖金锁定
  return draw_info, rewards
end


function rounds:refundToken(msg)
  assert(msg.Sender ~= nil, "Missed Sender.")
  assert(msg.Quantity ~= nil and tonumber(msg.Quantity) > 0, "Missed Quantity.")
  local message = {
    Target = msg.From,
    Action = "Transfer",
    Recipient = msg.Sender,
    Quantity = msg.Quantity,
    [const.Actions.x_transfer_type] = const.Actions.refund
  }
  ao.send(message)
end

function rounds:get(no)
  local key = no~=nil and tostring(no) or tostring(self.current)
  return self.repo[key]
end

return rounds
local utils =  utils or require(".utils")
local users = {}

function users:checkUserExist(id)
  local select_str = string.format("SELECT 1 FROM %s WHERE id = '%s'",self.db_name, id)
  local rows = {}
  for row in db:nrows(select_str) do table.insert(rows,row) end
  return #rows > 0
end

function users:queryUserRewardsBalance(id)
  assert(id~=nil,"missed id")
  local sql = string.format("SELECT rewards_balance FROM %s WHERE id = '%s'",self.db_name, id)
  local rows = {}
  for row in db:nrows(sql) do
    table.insert(rows,row[1] or 0)
  end
  local result = 0
  if #rows > 0 then
    result = rows[1]
  end
  return result
end

function users:queryUserInfo(id)
  assert(id~=nil,"missed id")
  local sql = string.format("SELECT * FROM %s WHERE id = '%s'",self.db_name, id)
  local rows = {}
  for row in db:nrows(sql) do
    table.insert(rows,row)
  end
  if #rows > 0 then return rows[1] else return nil end
end


function users:replaceUserInfo(user)
  local sql = string.format([[ 
    REPLACE INTO users (id, bets_count, bets_amount, rewards_balance, total_rewards_count, total_rewards_amount, participation_rounds, create_at, update_at)
    VALUES ('%s',%d,%d,%f,%d,%f,'%s',%d,%d)
  ]],
  user.id, user.bets_count, user.bets_amount, user.rewards_balance, user.total_rewards_count, user.total_rewards_amount, user.participation_rounds, user.create_at, user.update_at
  )
  db:exec(sql)
end

function users:countUserTotalBetsAmount ()
  local sql = string.format("SELECT SUM(bets_amount) FROM users")
  local stmt = db:prepare(sql)
  stmt:step()
  local total = stmt:get_value(0)
  stmt:finalize()
  return total
end

function users:queryAllusers()
  local sql = string.format("SELECT * FROM users")
  local rows = {}
  for row in db:nrows(sql) do
    table.insert(rows,row)
  end
  return rows
end

function users:increaseAllRewardBalance (rewards,timestamp)
  local all = self:countUserTotalBetsAmount()
  local per_share = rewards/all
  local sql = string.format("UPDATE %s SET rewards_balance = rewards_balance + bets_amount * %.3f,total_rewards_amount = total_rewards_amount + bets_amount * %.3f, total_shared_count=total_shared_count+1, update_at = %d",self.db_name,per_share,per_share,timestamp)
  db:exec(sql)
end


function users:increaseWinnersRewardBalance (winners,timestamp)
  utils.map(function (val, key)
    local sql = string.format("UPDATE %s SET rewards_balance = rewards_balance + %.3f , total_rewards_amount = total_rewards_amount + %.3f, total_rewards_count = total_rewards_count + 1, update_at = %d WHERE id == '%s'",self.db_name,val.rewards,val.rewards,timestamp,val.id)
    db:exec(sql)
  end,winners)
end



return users
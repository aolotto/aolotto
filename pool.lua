local ao = require(".ao")
local drive = require("modules.drive")
local utils = require(".utils")
local crypto = require(".crypto")

utils.toTokenQuantity = function(v,denomination)
  local precision = denomination or 3
  return v / 10^precision
end

utils.query = function(self,limit,offset,sort)
  local temp = {}
  table.move(self, 1, #self, 1, temp)
  if(sort) then
    table.sort(temp,function(a,b) 
      if sort[2] == "desc" then
        return a[sort[1]] > b[sort[1]]
      else
        return a[sort[1]] < b[sort[1]]
      end
    end)
  end
  local result = {}
  table.move(temp, offset or 1, math.min((limit or #temp) + (offset or 0)-1, #temp),1, result)
  return result
end

utils.getDrawNumber = function(seed,len)
  local numbers = ""
  for i = 1, len or 3 do
    local n = crypto.cipher.issac.random(0, 9, tostring(i)..seed..numbers)
    numbers = numbers .. n
  end
  return numbers
end

utils.deepCopy = function(original)
  if type(original) ~= "table" then
      return original
  end
  local copy = {} 
  for k, v in pairs(original) do
      copy[k] = utils.deepCopy(v) 
  end
  return copy
end

Const = Const or {
  MIN_BET=1,
  MAX_BET=1000,
  PRICE = 100,
  DRAW_DURATION = 86400000,
  
}
Info = Info or {
  name = ao.env.Process.Tags.Name or "FEI",
  token = ao.env.Process.Tags.Token or "zQ0DmjTbCEGNoJRcjdwdZTHt0UBorTeWbb_dnc6g41E",
  agent = ao.env.Process.Tags.Agent or "OOyuoFCDnKwl1QlJRiRNEoaSf0B_P553B3QpSVW4ffI",
  description = ao.env.Process.Tags.Name.."pool" or "Aolotto-Fei pool",
  timer = ao.env.Process.Tags.Timer or "cPRHI5QAEzruiUIFDK5wdBNNLv_4r9zPFnRXN4rUgo4"
}

-- Get token information
if not Info.token_info then
  local token_id = Info.token or ao.env.Process.Tags.Token
  if token_id then
    Handlers.once("once_get_tokeninfo_"..token_id,{
      From = token_id,
      Name = "_",
      Ticker = "_",
      Logo = "_",
      Denomination = "_"
    },function(m)
      Info.token_info = {
        id = m.From,
        name = m.Name,
        ticker = m.Ticker,
        denomination = m.Denomination,
        logo = m.Logo,
      }
    end)
    Send({Target=token_id,Action="Info"})
  end
end

State = State or {
  current_round=0,
  jackpot=0,
  balance=0,
  bet_count=0,
  bet_amount=0,
  latest_bet_time=0,
  latest_draw_time=0,
  alt_reward=0,
  selected_numbers=0
}
setmetatable(State, {
  __index = {
    increase = function(self,table)
      self = self or {}
      for k,v in pairs(table) do
        if type(v) == "number" then
          self[k] = (self[k] or 0) + v
        end
      end
    end,
    update = function(self,table)
      self = self or {}
      for k,v in pairs(table) do
        self[k] = v
      end
    end
  }
})


Players = Players or {}
setmetatable(Players, {
  __index = {
    get = function(self,id)
      self = self or {}
      return self[id]
    end,
    set = function(self,id,table)
      self = self or {}
      self[id] = table
    end,
    clear = function(self)
      self = self or {}
      for k,v in pairs(self) do
        self[k] = nil
      end
    end,
    increaseBets = function(self,id,bet_arr)
      self = self or {}
      self[id] = self[id] or {}
      for i,v in ipairs(bet_arr) do
        if type(v) == "number" then
          self[id][i] = (self[id][i] or 0) + v
        end
      end
    end
  }
})
Draws = Draws or {}
setmetatable(Draws,{
  __index = {
    get = function(self,no)
      no = tonumber(no)
      self = self or {}
      local result
      for i,v in ipairs(self) do
        if v.round == no then
          result = v
        end
      end
      return result
    end,
    add = function(self,draw)
      self = self or {}
      table.insert(self,draw)
    end,
    remove = function(self,no)
      no = tonumber(no)
      self = self or {}
      for i,v in ipairs(self) do
        if v.round == no then
          self[i] = nil
        end
      end
    end,
    count = function(self)
      return #self
    end
  }
})
Numbers = Numbers or {}
setmetatable(Numbers,{
  __index = {
    clear = function(self)
      self = self or {}
      for k,v in pairs(self) do
        self[k] = nil
      end
    end,
    batchIncrease = function(self,numbers)
      self = self or {}
      for k,v in pairs(numbers) do
        self[k] = (self[k] or 0) + v
      end
    end
  }
})
Bets = Bets or {}
setmetatable(Bets,{
  __index = {
    add = function(self,draw)
      self = self or {}
      table.insert(self,draw)
    end,
    clear = function(self)
      self = self or {}
      for i,v in ipairs(self) do
        self[i] = nil
      end
    end,
    count = function(self)
      return #self
    end
  }
})


Handlers.add("info","Info",function(msg) 
  msg.reply({Data={
    state=State,
    info=Info,
    constants=Const,
  }})
end)

Handlers.add("save-bets",{
  Action = "Save-Bets",
  From = Info.agent,
  Ticket = "_",
  Player = "_",
  Data = "_",
  Price = "_",
  Ticker = "_",
  Denomination = "_"
},function(msg)
  -- if State.selected_numbers >= (10 ^ Const.DIGITS or 1000) then
  --   Handlers.switchRound(msg)
  -- end

  local data = msg.Data

  Bets:add({
    id = msg.Ticket,
    numbers = data.numbers,
    purchase = {
      amount = data.amount,
      price = tonumber(msg.Price),
      ticker = msg.Ticker,
      denomination = tonumber(msg.Denomination)
    },
    round = {
      round_no = State.current_round,
    },
    bet = {
      count = data.count,
      amount = data.amount
    },
    player = {
      id = msg.Player,
    },
    ts_created = data.ts_bet,
    nouce = msg['Ticket-Nouce']
  })
  State:increase({
    bet_count = data.count,
    bet_amount = data.amount,
    balance = data.amount,
    jackpot = data.amount * 0.5,
    players_count = Players:get(msg.Player) and 0 or 1,
    tickets = 1
  })
  for k,v in pairs(data.numbers) do
    State:increase({
      selected_numbers = Numbers[k] and 0 or 1
    })
  end

  Numbers:batchIncrease(data.numbers)
  Players:increaseBets(msg.Player,{
    [1] = data.count,
    [2] = data.amount,
    [3] = 1
  })


  State:update({latest_bet_time = data.ts_bet})

  if State.selected_numbers < math.floor(10 ^ (Const.DIGITS or 3)) and State.bet_amount < State.jackpot then
    State:update({latest_draw_time = data.ts_bet + (Const.DRAW_DURATION or 86400000)})
  end

  msg.reply({
    Action = "Bets-Saved",
    Data = State
  })

  if not Timer then
    Handlers.addTimer(State.latest_draw_time)
  end
  
end)


Handlers.add("get",{Action = "Get"},{
  [{Table = "Bets"}] = function(msg)
    msg.reply({
      Total= tostring(#Bets),
      Data=utils.query(Bets,tonumber(msg.Limit) or 100,tonumber(msg.Offset) or 1,{"ts_created","desc"})
    }) 
  end,
  [{Table = "Draws"}] = function(msg)
    msg.reply({
      Total= tostring(#Draws),
      Data=utils.query(Draws,tonumber(msg.Limit) or 100,tonumber(msg.Offset) or 1,{"ts_draw","desc"})
    }) 
  end
})

Handlers.add("start_pool",{
  Action = "Start-Pool",
  From = Info.agent,
  Funds = "%d+"
},function(msg)
  if State.current_round == nil or State.current_round<=0 then
    State:update({
      balance = tonumber(msg.Funds),
      jackpot = tonumber(msg.Funds) * 0.5,
      current_round = 1,
      round_start_time = msg.Timestamp,
    })

    Const.PRICE = tonumber(msg.Price) or msg.Data.price
    Const.DIGITS = msg.Data.digits
  end
  msg.reply({
    Action = "Pool-Started",
    Data = State
  })
end)




Handlers.switchRound = function(msg)
  local archive = nil
  if Archive == nil then

    State:update({
      round_end_time = msg.Timestamp or os.time()
    })
  
    archive = {
      state = utils.deepCopy(State),
      bets = utils.deepCopy(Bets),
      numbers = utils.deepCopy(Numbers),
      players = utils.deepCopy(Players)
    }
  
    State:increase({
      current_round = 1
    })
    State:update({
      round_end_time = nil,
      round_start_time = msg.Timestamp,
      jackpot= (archive.state.balance - archive.state.jackpot)*0.5,
      balance= archive.state.balance - archive.state.jackpot,
      bet_count=0,
      bet_amount=0,
      latest_bet_time=0,
      latest_draw_time=0,
      alt_reward=0,
      selected_numbers=0,
      players_count=0,
      tickets = 0
    })
    Players:clear()
    Numbers:clear()
    Bets:clear()
    Archive = archive
    Timer = nil

  else
    archive = Archive
  end
  
  Handlers.once("once_archived_"..archive.state.current_round,{
    Action = "Archived",
    From = ao.id,
    Round = "%d+"
  },function(m)
    print('archived and draw')
    local draw = Handlers.draw(m.Data,m)
    Draws:add(draw)
    Archive = nil
    print('Round ['..m.Data.state.current_round.."] has been drawn.")
    Send({
      Target=Info.agent,
      Action = "Draw-Notice",
      Data = {
        draw = draw,
        players = m.Data.players,
        state = m.Data.state
      }
    })
  end)

  Send({
    Target = ao.id,
    Action = "Archived",
    Round = tostring(archive.state.current_round),
    Data = archive
  })

end

Handlers.draw = function(archive,msg)
  assert(archive~=nil and type(archive) == "table","missed archive data")
  assert(msg~=nil and type(msg) == "table","missed msg")
  local latest_bet = archive.bets[#archive.bets]
  local block = drive.getBlock(msg['Block-Height'] or 1520692)
  local seed = latest_bet.id ..'_'.. block.hash ..'_'.. latest_bet.nouce ..'_'.. archive.state.bet_count
  local lucky_number = utils.getDrawNumber(seed,Const.DIGITS or 3)
  print("lucky_number:"..lucky_number)
  archive.numbers = archive.numbers or {}
  local win_number_count = archive.numbers[lucky_number]
  local per_number_share
  local win_bets = {}
  local winners_count = 0
  local winners = {}
  local rewards = {}

  if win_number_count and win_number_count > 0 then
    per_number_share = math.floor(archive.state.jackpot / win_number_count)
    for i,bet in ipairs(archive.bets) do
      local matched_number_count = bet.numbers[lucky_number] or 0 
      if matched_number_count >= 1 then
        table.insert(win_bets,{
          matched_number_count = matched_number_count,
          rewards = matched_number_count * per_number_share,
          player = bet.player.id,
          ticket = bet.id,
          ts_created = bet.ts_created,
          purchase = bet.purchase
        })
      end
    end

    for i,v in ipairs(win_bets) do
      if winners[v.player] then
        local winner = winners[v.player]
        table.insert(winner.tickets,v.ticket)
        winner.rewards = winners[v.player].rewards + v.rewards
        winners[v.player] = winner
      else
        local tickets = {}
        table.insert(tickets,v.ticket)
        winners[v.player] = {
          rewards = v.rewards,
          tickets = tickets
        }
        winners_count = winners_count + 1
      end
      rewards[v.player] = winners[v.player].rewards
    end
    
  else
    table.insert(win_bets,{
      matched_number_count = 0,
      rewards = archive.state.jackpot,
      player = latest_bet.player.id,
      ticket = latest_bet.id,
      ts_created = latest_bet.ts_created,
      purchase = latest_bet.purchase
    })
    rewards[latest_bet.player.id] = archive.state.jackpot
  end
  
  local draw = {
    round = archive.state.current_round,
    lucky_number = lucky_number,
    ts_draw = msg.Timestamp,
    jackpot = archive.state.jackpot,
    per_number_share = per_number_share,
    win_number_count = win_number_count,
    draw_type = (win_number_count and win_number_count > 0) and "WIN" or "NON-WIN",
    winners_count = winners_count,
    archive = msg.Id,
    seed = seed,
    win_bets = win_bets,
    winners = winners,
    rewards = rewards
  }

  return draw

end



Handlers.addTimer = function(time)
  if not time then
    time = os.time() + (Const.DRAW_DURATION or 86400000)
  end
  Send({
    Target = Info.timer,
    Action = "Add-Subscription",
    Time = tostring(time)
  })
  Timer = time
end


Handlers.add("timer",{
  From = Info.timer,
  Action = "Time-Up"
},function(msg)
  if msg.Timestamp >= State.latest_draw_time then
    if State.latest_draw_time > 0 then
      Handlers.switchRound(msg)
    end
  else
    Handlers.addTimer(State.latest_draw_time)
  end
end)


local ao = require ".ao"
local drive = require "modules.drive"
local utils = require(".utils")
local crypto = require(".crypto")

utils.toTokenQuantity = function(v,denomination)
  local precision = denomination or 3
  return v / 10^precision
end

utils.increase = function(self,tbl)
  for k,v in pairs(tbl) do
    self[k] = (self[k] or 0) + v
  end
end

utils.increaseById = function(self,id,tbl)
  self[id] = self[id] or {}
  for k,v in pairs(tbl) do
    self[id][k] = (self[id][k] or 0) + v
  end
end

utils.update = function(self,tbl)
  for k,v in pairs(tbl) do
    self[k] = v
  end
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

utils.getById = function(self, id)
  return self[id]
end

utils.getDrawNumber = function(seed,len)
  local numbers = ""
  for i = 1, len or 3 do
    local n = crypto.cipher.issac.random(0, 9, tostring(i)..seed..numbers)
    numbers = numbers .. n
  end
  return numbers
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
  description = "Aolotto-Fei pool",
}
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

Players = Players or {}
Draws = Draws or {}
Numbers = Numbers or {}
Bets = Bets or {}


local state = setmetatable(State,{
  __index = {
    increase = utils.increase,
    update = utils.update
  }
})

local numbers = setmetatable(Numbers,{
  __index = {
    increase = utils.increase
  }
})

local players = setmetatable(Players,{
  __index = {
    increaseById = utils.increaseById,
    getById = utils.getById,
    increaseBets =  function(self,id,values)
      assert(id and type(id) == "string", "Invalid player ID")
      assert(values and type(values) == "table", "Invalid Values" )
      self[id] = self[id] or {}
      local b = self[id]
      for i,v in ipairs(values) do
        self[id][i] = (b[i] or 0) + (v or 0)
      end
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
  if State.selected_numbers >= (10 ^ Const.DIGITS or 1000) then
    Handlers.switchRound(msg)
  end
  local data = msg.Data

  table.insert(Bets,{
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
  state:increase({
    bet_count = data.count,
    bet_amount = data.amount,
    balance = data.amount,
    jackpot = data.amount * 0.5,
    players_count = players:getById(msg.Player) and 0 or 1
  })
  for k,v in pairs(data.numbers) do
    state:increase({
      selected_numbers = Numbers[k] and 0 or 1
    })
  end

  numbers:increase(data.numbers)
  players:increaseBets(msg.Player,{
    [1] = data.count,
    [2] = data.amount,
    [3] = 1
  })


  state:update({latest_bet_time = data.ts_bet})

  if State.selected_numbers < math.floor(10 ^ (Const.DIGITS or 3)) and State.bet_amount < State.jackpot then
    state:update({latest_draw_time = data.ts_bet + (Const.DRAW_DURATION or 86400000)})
  end

  msg.reply({
    Action = "Bets-Saved",
    Data = State
  })
end)


Handlers.add("get",{Action = "Get"},{
  [{Table = "Bets"}] = function(msg)
    msg.reply({
      Total= tostring(#Bets),
      Data=utils.query(Bets,tonumber(msg.Limit) or 100,tonumber(msg.Offset) or 1,{"ts_created","desc"})
    }) 
  end
})

Handlers.add("start_pool",{
  Action = "Start-Pool",
  From = Info.agent,
  Funds = "%d+"
},function(msg)
  if State.current_round == nil or State.current_round<=0 then
    state:update({
      balance = tonumber(msg.Funds),
      jackpot = tonumber(msg.Funds) * 0.5,
      current_round = 1,
      round_start_time = msg.Timestamp,
    })

    Const.PRICE = msg.Data.price
    Const.DIGITS = msg.Data.digits
    Info.name = msg.Data.name
    Info.token = msg.Data.token_info.id
    Info.token_info = msg.Data.token_info
  end
  msg.reply({
    Action = "Pool-Started",
    Data = State
  })
end)




Handlers.switchRound = function(msg)
  state:update({
    round_end_time = msg.Timestamp or os.time()
  })

  Archive = {
    state = State,
    bets = Bets,
    numbers = Numbers
  } 
  state:increase({
    current_round = 1
  })
  state:update({
    round_end_time = nil,
    round_start_time = msg.Timestamp,
    jackpot= Archive.state.balance - Archive.state.jackpot,
    balance= Archive.state.balance - Archive.state.jackpot,
    bet_count=0,
    bet_amount=0,
    latest_bet_time=0,
    latest_draw_time=0,
    alt_reward=0,
    selected_numbers=0
  })
  Bets = {}
  Numbers = {}
  Players = {}
  

  Handlers.once("once_archived"..Archive.state.current_round,{
    Action = "Archived",
    From = ao.id,
    Round = "%d+"
  },function(m)
    local draw = Handlers.draw(Archive,m)
    table.insert(Draws,draw)
    Archive = nil
    print('Round ['..Archive.state.current_round.."] has been drawn.")
    Send({
      Target=Info.agent,
      Action = "Draw-Notice",
      Data = draw
    })
  end)


  Send({
    Target = ao.id,
    Action = "Archived",
    Round = tostring(Archive.state.current_round),
    Data = Archive
  })
  print("round archived")
end

Handlers.draw = function(archive,msg)
  assert(archive~=nil and type(archive) == "table","missed archive data")
  assert(msg~=nil and type(msg) == "table","missed msg")
  local latest_bet = archive.bets[#archive.bets]
  local block = drive.getBlock(msg['Block-Height'] or 1520692)
  local seed = latest_bet.id ..'_'.. block.hash ..'_'.. latest_bet.nouce ..'_'.. archive.state.bet_count
  local lucky_number = utils.getDrawNumber(seed,Const.DIGITS or 3)
  print(lucky_number)
  archive.numbers = archive.numbers or {}
  local win_number_count = archive.numbers[lucky_number]
  print(win_number_count)
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



Handlers.add("cron",{
  Action="Cron"
},function(msg)
  if msg.Timestamp < State.latest_draw_time then
    return
  else
    Handlers.switchRound()
  end
end)



Handlers.test = function(msg)
  local _archive = {
    state = State,
    bets = Bets,
    numbers = Numbers
  }
  Handlers.once("once_archived_".._archive.state.current_round,{
    Action = "Archived",
    From = ao.id,
    Round = "%d+"
  },function(m)
    local draw = Handlers.draw(m.Data,m)
    TestDraw = {}
    table.insert(TestDraw,draw)
    -- _archive = nil
    Send({
      Target=Info.agent,
      Action = "Draw-Notice",
      Data = draw
    })
    print('Round ['..m.Data.state.current_round.."] has been drawn.")
  end)


  Send({
    Target = ao.id,
    Action = "Archived",
    Round = tostring(_archive.state.current_round),
    Data = _archive
  })
  print("round archived")

end




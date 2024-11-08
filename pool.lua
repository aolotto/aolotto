local drive = require("modules.drive")
local utils = require("modules.utils")
local crypto = require(".crypto")

STORE = STORE or ao.env.Process.Tags.Store or nil
TOKEN = TOKEN or ao.env.Process.Tags.Token or nil
assert(type(STORE) == "string" and string.len(STORE) == string.len(ao.id), "STORE address is incorrect.")
assert(type(TOKEN) == "string" and string.len(TOKEN) == string.len(ao.id), "TOKEN address is incorrect.")

TAX = TAX or 0.1
RUN = RUN or 1 -- Bonus switch, 1 represents open, 0 represents close
PRICE = PRICE or 100000000000
DIGITS = DIGITS or 3
DRAW_DELAY = DRAW_DELAY or 86400000
JACKPOT_SCALE = JACKPOT_SCALE or 0.5
WITHDRAW_MIN = WITHDRAW_MIN or 10
MAX_BET_COUNT = 100
TYPE = "3D"

Info = Info or {id = ao.id}
State = State or {
  round = 1,
  bet = {0,0,0}, -- {quantity, amount, tickets }
  jackpot = 0,
  picks = 0,
  balance = 0,
  players = 0,
  ts_latest_draw = 0,
  ts_latest_bet = 0,
  ts_round_start = 0,
  ts_round_end = 0,
}
Sales = {0,0,0} -- {total_bet_count, total_bet_amount, total_tickets}
Bets = Bets or {}
Players = Players or {}
Draws = Draws or {}
Numbers = Numbers or {}


Handlers.add('bet',{
  Action = "Betting",
  Quantity = "%d",
  From = STORE,
  ['X-Origin'] = TOKEN,
  ['X-Numbers'] = "_",
  ['X-Pool'] = ao.id,
},function(msg)
  assert(tonumber(msg.Quantity)>=PRICE,"Quantity must >= PRICE ")
  assert(RUN==1,"The pool is not accepting bets")

  local x_numbers = msg['X-Numbers']
  local numbers, count = utils.parseNumberStringToBets(x_numbers,DIGITS or 3)
  local max_count = math.min(math.floor(tonumber(msg.Quantity)/PRICE),MAX_BET_COUNT)
  assert(max_count >=1,"Insufficient bet amount")
  
   -- If total_bets is not equal to max_bets_in_quantity, generate a random number
   if count ~= max_count then
    numbers = {}
    local random_number = utils.getRandomNumber(DIGITS or 3,msg['X-Numbers'])
    numbers[random_number] = max_count
    x_numbers = random_number.."*"..max_count
    count = max_count
  end

  local amount = count*PRICE
  local jackpot = count*PRICE*JACKPOT_SCALE

  -- Create new Player if not exists and increase total_players
  if not Players[msg.Sender] then
    Players[msg.Sender] = {0,0,0}
    utils.increase(State,{players=1})
  end

  utils.increase(Players[msg.Sender],{count,amount,1})
  utils.increase(Sales,{count,amount,1})


  -- Save the bet
  local bet = {
    id = msg['Pushed-For'],
    round = State.round,
    amount = amount,
    count = count,
    x_numbers = x_numbers,
    ts_created = msg.Timestamp,
    player = msg.Sender,
    numbers = numbers,
    price = PRICE,
    token = Token.id or TOKEN,
    currency = { Token.ticker,Token.denomination,Token.logo},
    store = msg.From,
  }

  if State.mine and tonumber(State.mine[1])>=1 then
    local unit_amount = tonumber(State.mine[1]) / 1000
    local mine_amount = math.max(unit_amount * count,1)
    bet.mine = {mine_amount,Info.mining[3]}
    utils.decrease(State.mine,{mine_amount,0,0})
  end

  table.insert(Bets,bet)

  if not BetsIndexer then BetsIndexer = {} end
  BetsIndexer[bet.id] = #Bets

  utils.increase(State.bet,{count, amount, 1})
  utils.increase(State,{jackpot=jackpot,balance=amount})
  utils.update(State,{
    ts_latest_bet = msg.Timestamp,
    bet_hash_chain = utils.getMd4Digests((State.bet_hash_chain or "")..msg.Id)
  })

  -- If the total bet amount is less than the maximum of 1000 units of bet amount or jackpot, delay the draw time
  if State.bet[2] < math.max(State.jackpot, PRICE * 10 ^ (DIGITS or 3)) then
    utils.update(State,{ts_latest_draw = msg.Timestamp + DRAW_DELAY})
  end

  -- Count numbers
  for key,value in pairs(numbers) do
    if Numbers[key] == nil then
      utils.increase(State,{picks=1})
    end
  end
  utils.increase(Numbers,numbers)

  local lotto_notice = {
    Target = bet.store or STORE,
    Action = "Lotto-Notice",
    Player = bet.player or msg.Sender,
    Round = string.format("%.0f", bet.round or State.round),
    Count = string.format("%.0f", count),
    Amount = string.format("%.0f", amount),
    ['X-Numbers'] = x_numbers,
    Price = string.format("%.0f", PRICE),
    Token = bet.token or TOKEN or Token.id,
    Ticket = msg['Pushed-For'],
    Currency = table.concat(bet.currency,","),
    ['Pushed-For'] = bet.pushed_for or msg['Pushed-For'],
    Data = State,
  }
  
  if bet.mine then
    local mining_msg = {
      Target = MINER,
      Action = "Mining",
      Player = lotto_notice.Player,
      ['Pushed-For'] = lotto_notice['Pushed-For'],
      ['X-Mine-Amount'] = string.format("%.0f", bet.mine[1]),
      ['X-Mine-Token'] = Info.mining[2],
      ['X-Mine-Currency'] = bet.mine[2] or Info.mining[3]

    }
    lotto_notice['X-Mine-Amount'] = mining_msg['X-Mine-Amount']
    lotto_notice['X-Mine-Token'] = mining_msg['X-Mine-Token']
    lotto_notice['X-Mine-Currency'] = mining_msg['X-Mine-Currency']
    
    Send(lotto_notice)
    Send(mining_msg).onReply(function(m)
      State.mine = m.Data
    end)
  else
    Send(lotto_notice)
  end

  if State.ts_latest_draw <= msg.Timestamp then
    Handlers.archive()
  end

end)


Handlers.archive = function(...)
  if Archive == nil then
    assert(#Bets >=1,"bets length must greater than 1.")
    assert(State.jackpot >=1,"jackpot must greater than 1.")
    State.ts_round_end = os.time()
    Archive = {
      state = utils.deepCopy(State),
      players = utils.deepCopy(Players),
      bets = utils.deepCopy(Bets),
      numbers = utils.deepCopy(Numbers)
    }
    Players = {}
    Bets = {}
    Numbers = {}
    BetsIndexer = {}
    local balance = State.balance - State.jackpot
    local jackpot = balance * JACKPOT_SCALE
    local round = State.round + 1
    utils.update(State,{
      picks = 0,
      bet = {0,0,0},
      players = 0,
      ts_round_start = os.time(),
      ts_latest_bet = 0,
      round = round,
      balance = balance,
      jackpot = jackpot,
      ts_round_end = 0,
      ts_latest_draw = 0
    })
    print("Round switch to "..State.round)
  end
  
  if Archive then
  
    Handlers.once("_once_archive_"..Archive.state.round,{
      From = ao.id,
      Action = "Archive",
      Round = tostring(Archive.state.round)
    },function(m)
      print("The round ["..m.Round.."] has been archived as: "..m.Id)
      Handlers.draw(m.Id, Archive, m['Block-Height'], m.Timestamp)
      Archive = nil
    end)

    Send({
      Target = ao.id,
      Action = "Archive",
      Round = tostring(Archive.state.round),
      Data = {
        state = Archive.state,
        player = Archive.player,
        numbers = Archive.numbers
      }
    })

  end

end


Handlers.draw = function(...)
  assert(select(1,...)~=nil,"missed archive id.")
  assert(select(2,...)~=nil and type(select(2,...)) == "table","missed draw data")
  assert(select(3,...)~=nil and type(select(3,...)) == "number","missed block-height")
  local archive_id = select(1,...)
  local data = select(2,...)
  local state = data.state or Archive.state
  local players = data.players or Archive.players
  local bets = data.bets or Archive.bets
  local numbers = data.numbers or Archive.numbers
  local latest_bet = bets[#bets]
  local block = drive.getBlock(select(3,...) or 1520692)
  local seed = block.hash ..'_'..archive_id
  local lucky_number = utils.getDrawNumber(seed,DIGITS or 3)
  print("lucky_number:"..lucky_number)
  -- count winners and rewards
  local winners = 0
  local rewards = {}
  local matched_count = 0
  local share = 0
  if numbers[lucky_number] and numbers[lucky_number]>0 then
    matched_count = numbers[lucky_number]
    share = state.jackpot / matched_count
    for i,v in ipairs(bets) do
      if v.numbers[lucky_number] then
        winners = winners + 1
        local _prize = v.numbers[lucky_number] * share
        local _amount = players[v.player][2] or v.amount
        rewards[v.player] ={_prize,_amount}
      end
    end
  else
    local _prize = state.jackpot
    local _amount = players[latest_bet.player][2] or latest_bet.amount
    rewards[latest_bet.player] = {_prize,_amount}
  end


  local draw =  {
    round = state.round,
    lucky_number = lucky_number,
    players = state.players,
    jackpot = state.jackpot,
    rewards = rewards,
    archive = archive_id,
    winners = winners,
    ts_draw = select(4,...) or os.time(),
    bet = state.bet,
    block_hash = block.hash,
    currency = {Token.ticker,Token.denomination,Token.logo}
  }
  table.insert(Draws,draw)
  Send({
    Target = STORE,
    Action = "Draw-Notice",
    Round = string.format("%.0f", draw.round),
    Players = string.format("%.0f", draw.players),
    Jackpot = string.format("%.0f", draw.jackpot),
    Winners = string.format("%.0f", draw.winners),
    Archive = draw.archive or archive_id,
    Token = TOKEN or Token.id,
    Currency = table.concat(draw.currency,","),
    ['Pool-Info'] = table.concat({Info.name,Info.logo},","),
    ['Lucky-Number'] = tostring(draw.lucky_number),
    ['Awarded-To'] = draw.winners > 0 and tostring(draw.winners) or "1",
    ['Pool-Type'] = TYPE,
    Data = draw
  })
end


Handlers.add("info","Info",function(msg)
  local message = {
    Name = Info.name or Token.ticker,
    Token = Token.id or TOKEN,
    Store = STORE,
    Currency = table.concat({Token.ticker,Token.denomination,Token.logo},","),
    Logo = Info.logo,
    Tax = tostring(TAX or 0.01),
    Run = tostring(RUN or 0),
    Price = tostring(PRICE or 100000000000),
    Digits = tostring(DIGITS or 3),
    ['Pool-Type'] = TYPE,
    ['Draw-Delay'] = tostring(DRAW_DELAY or 86400000),
    ['Jackpot-Scale'] = tostring(JACKPOT_SCALE or 0.5),
    ['Withdraw-Min'] = tostring(WITHDRAW_MIN or 1),
    Data = State
  }
  if Info.mining then
    message.Mining = table.concat(Info.mining,",")
  end
  msg.reply(message)
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

Handlers.add("numbers","Numbers",function(msg)
  msg.reply({Data = Numbers})
end)

Handlers.add("query_by_id",{Action="Query"},{
  [{Table = "Bets",['Query-Id']="_"}] = function(msg)
    local index = BetsIndexer[msg['Query-Id']]
    if index ~= nil then
      msg.reply({Data = Bets[index]})
    end
  end
})


Handlers.add('cron',"Cron",function(msg)
  if State.ts_latest_draw > 0 and State.ts_latest_draw <= msg.Timestamp then
    Handlers.archive()
  end
end)


Handlers.fetchTokenInfo = function(token)
  token = token or TOKEN
  if token~=nil and type(token)=="string" then
    Handlers.once("once_get_tokeninfo_"..token,{
      From = token,
      Name = "_",
      Ticker = "_",
      Logo = "_",
      Denomination = "_"
    },function(m)
      Token = {
        id = m.From,
        name = m.Name,
        ticker = m.Ticker,
        denomination = tonumber(m.Denomination),
        logo = m.Logo,
      }
      if not Info.logo then Info.logo = m.Logo end
      if not Info.name then Info.name = m.Ticker end
      print("Token info updated.")
    end)
    Send({Target=token,Action="Info"})
  end
end

if not Token or not Info.name then
  local token_id = TOKEN or ao.env.Process.Tags.Token
  if token_id then Handlers.fetchTokenInfo(token_id) end
end

Handlers.resetPool = function(...)
  State = {
    round = 1,
    bet = {0,0,0}, 
    jackpot = 0,
    picks = 0,
    balance = 0, 
    players = 0, 
    ts_latest_draw = 0,
    ts_latest_bet = 0,
    ts_round_start = 0,
    ts_round_end = 0
  }
  Bets = {}
  Players = {}
  Draws = {}
  Numbers = {}
  Sales = {0,0,0}
end






Handlers.initMiningHandlers = function(miner)
  assert(miner~=nil,"missed miner process")
  MINER = miner
  ao.addAssignable("assignments_from_miner",{ From = miner})
  Handlers.add("mining-quota-added",{
    Action = "Quota-Added",
    From = miner,
    Amount = "%d+"
  },function(msg)
    print("Added mining quota: "..msg.Amount)
    State.mine = msg.Data
  end)
  print("✅ Handlers added for Mining process: "..miner)
end

Handlers.add("mining-pool-added",{
  From = STORE,
  Action = "Mining-Pool-Added"
},function(msg)
  MINER = msg['X-Origin'] or msg.Token
  Handlers.initMiningHandlers(MINER,STORE)
  Info.mining = {tonumber(msg.Productivity), MINER, msg.Currency}
  State.mine = msg.Data
end)

if MINER then Handlers.initMiningHandlers(MINER) end



Handlers.test = function(...)
  print(utils.getMd4Digests(select(1,...)))
end
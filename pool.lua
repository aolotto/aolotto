local ao = require(".ao")
local drive = require("modules.drive")
local utils = require("modules.utils")
local crypto = require(".crypto")

AGENT = AGENT or ao.env.Process.Tags.Agent or "mvM7nLGsgdEYLRgi85haT_6XuINRevh8dLpxMXsYpZM"
TIMER = TIMER or ao.env.Process.Tags.Timer or ""
TOKEN = TOKEN or ao.env.Process.Tags.Token or "UHMKwYgQzDduuAGr85DQxhVpmak9vXM4GVL18nQ9Iak"
MINER = MINER or ao.env.Process.Tags.Miner or ""
TAX = TAX or 0.1
RUN = RUN or 1
PRICE = PRICE or 100000000000
DIGITS = DIGITS or 3
DRAW_DELAY = DRAW_DELAY or 86400000
JACKPOT_SCALE = JACKPOT_SCALE or 0.5
WITHDRAW_MIN = WITHDRAW_MIN or 10
TYPE = "3D"


Info = Info or {
  id = ao.id,
  name = "XIN",
  logo = ao.env.Process.Tags.Logo,
}


-- @param car
State = State or {
  round = 1,
  bet = {0,0,0}, --@param bet table {quantity, amount, tickets }
  jackpot = 0,
  picks = 0,
  balance = 0, -- {current_banlance, progressive_balance}
  players = 0, -- {current, total}
  ts_latest_draw = 0,
  ts_latest_bet = 0,
  ts_round_start = 0,
  ts_round_end = 0
}

if not Token then
  local token_id = TOKEN or ao.env.Process.Tags.Token
  if token_id then Handlers.fetchTokenInfo(token_id) end
end

Bets = Bets or {}
Players = Players or {}
Draws = Draws or {}
Numbers = Numbers or {}


Handlers.add('bet',{
  Action = "Ticket-Notice",
  Quantity = "%d",
  From = AGENT,
  ['X-Numbers'] = "_",
  ['X-Pool'] = ao.id,
},function(msg)
  assert(tonumber(msg.Quantity)>=PRICE,"Quantity must >= PRICE ")
  assert(RUN==1,"The pool is not accepting bets")

  local x_numbers = msg['X-Numbers']
  local numbers, count = utils.parseNumberStringToBets(x_numbers,DIGITS or 3)
  local max_count = math.floor(tonumber(msg.Quantity)/PRICE) 
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
  

  -- Save the bet
  local bet = {
    id = msg.Id,
    round = State.round,
    amount = amount,
    count = count,
    x_numbers = x_numbers,
    ts_created = msg.Timestamp,
    player = msg.Sender,
    numbers = numbers,
    price = PRICE,
    token = Token.id or TOKEN,
    currency = { Token.ticker,Token.denomination,Token.logo}
  }

  table.insert(Bets,bet)
  utils.increase(State.bet,{count, amount, 1})
  utils.increase(State,{jackpot=jackpot,balance=amount})
  utils.update(State,{ts_latest_bet = msg.Timestamp})
  if State.bet[2] < math.max(State.jackpot,PRICE * 10 ^ (DIGITS or 3)) then
    utils.update(State,{ts_latest_draw = msg.Timestamp + DRAW_DELAY})
  end

  -- Count numbers
  for key,value in pairs(numbers) do
    if Numbers[key] == nil then
      utils.increase(State,{picks=1})
    end
  end
  utils.increase(Numbers,numbers)

  
  Send({
    Target = AGENT or msg.From,
    Action = "Lotto-Notice",
    Player = msg.Sender,
    Pool = ao.id,
    Round = string.format("%.0f", bet.round or State.round),
    Count = string.format("%.0f", count),
    Amount = string.format("%.0f", amount),
    ['X-Numbers'] = x_numbers,
    Price = string.format("%.0f", PRICE),
    Token = bet.Token or msg.Token or TOKEN or Token.id,
    Ticket = msg.Id,
    Currency = table.concat(bet.currency,","),
    Data = State
  })
  
end)


Handlers.archive = function(...)
  if Archive == nil then
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
      Handlers.draw(m.Id, m.Data or Archive, m['Block-Height'], m.Timestamp)
      Archive = nil
    end)

    Send({
      Target = ao.id,
      Action = "Archive",
      Round = tostring(Archive.state.round),
      Data = Archive
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
  local seed = block.hash ..'_'.. latest_bet.id ..'_'..'_'..archive_id
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
    latest_bet_id = latest_bet.id,
    block_hash = block.hash
  }
  table.insert(Draws,draw)
  Send({
    Target = AGENT,
    Action = "Draw-Notice",
    Round = string.format("%.0f", draw.round),
    Players = string.format("%.0f", draw.players),
    Jackpot = string.format("%.0f", draw.jackpot),
    Winners = string.format("%.0f", draw.winners),
    Archive = draw.archive or archive_id,
    Token = TOKEN or Token.id,
    Ticker = Token.ticker,
    Denomination = string.format("%.0f", Token.denomination),
    Data = draw
  })
end


Handlers.add("info","Info",function(msg)
  msg.reply({
    Name = Info.name or Token.ticker,
    Token = Token.id or TOKEN,
    Agent = AGENT,
    Timer = TIMER,
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
  })
end)


Handlers.add("time-up",{
  Action = "Time-Up",
  From = TIMER,
})

Handlers.once("once_listed_on_agent",{
  Action="Listed",
  From = AGENT,
},function(msg)
  RUN = 1
  AGENT = msg.From
  TIMER = msg.Timer or TIMER
  if State.round < 1 then
    State.round = 1
  end
  if State.ts_round_start == nil then
    State.ts_round_start = msg.Timestamp
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

Handlers.resetPool = function(...)
  State = {
    round = 1,
    bet = {0,0,0}, --@param bet table {quantity, amount, tickets }
    jackpot = 0,
    picks = 0,
    balance = 0, -- {current_banlance, progressive_balance}
    players = 0, -- {current, total}
    ts_latest_draw = 0,
    ts_latest_bet = 0,
    ts_round_start = 0,
    ts_round_end = 0
  }
  
  Bets = {}
  Players = {}
  Draws = {}
  Numbers = {}

  AGENT = select(1,...) or AGENT or ao.env.Process.Tags.Agent or "mvM7nLGsgdEYLRgi85haT_6XuINRevh8dLpxMXsYpZM"
  TIMER = select(2,...) or TIMER or ao.env.Process.Tags.Timer or ""
  TOKEN = select(3,...) or TOKEN or ao.env.Process.Tags.Token or "UHMKwYgQzDduuAGr85DQxhVpmak9vXM4GVL18nQ9Iak"
  MINER = select(4,...) or MINER or ao.env.Process.Tags.Miner or ""

  local token_id = TOKEN or ao.env.Process.Tags.Token
  if token_id then Handlers.fetchTokenInfo(token_id) end


end
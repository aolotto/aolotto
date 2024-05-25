--[[
    initialization constants
]]--

NAME = "aolotto"

ROUND_CONFIG = {
    max = 73000,
    min_bets_amount = 1000,
    l1_ratio = 0.5,
    l2_ratio = 0.2,
    l3_ratio = 0.1,
    next_round_ratio = 0.2
}

BET_PRICE = 1000

INTERVAL = {
    draw = 1440 -- minus
}

TAX_RATE = {
  claim = 0.1,
}

ROUND_STATES = {
    unstart = 0,
    inprocess = 1,
    ended = 2,
    expired = 3,
    paused = -1,
    cancelled = -2
}

DRAW_STATES = {
    unreward = 0,
    rewarded = 1,
}

ORDER_STATES = {
    unpay = 0,
    paid = 1
}

REAWARD_STATES = {
  unpay = 0,
  paid = 1
}

CLAIM_STATES = {
  unpay = 0,
  paid = 1
}

REAWARD_TYPES = {
    l1 = 1,
    l2 = 2,
    l3 = 3
}

TABLES = {
    users = "users",
    rounds = "rounds",
    draws = "draws",
    bets = "bets",
    orders = "orders",
    rewards = "rewards",
    claims = "claims",
    sponsors = "sponsors"
}


CURRENT_ROUND = 1
ROUNDS = {{
    
    process = "pgMXPlpSxmp2r6EqIRkpv0M1c7WlRZZm77CoEdUP1VA",
    bets_count = 0,
    bets_amount = 0,
    prize = 0,
}}
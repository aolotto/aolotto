local _config = require("_config")
local const = require("modules.const")
local utils = require(".utils")
local json = require("json")
if not TOKEN then TOKEN = _config.TOKEN end
if not Members then Members = {} end
if not Initial_Supply then Initial_Supply = 210000000000 * 0.4 end
if not Total_Supply then Total_Supply = 210000000000 * 0.7 end
if not Supplied then Supplied = 0 end
if not BlackList then BlackList = {} end
if not Logs then Logs = {} end
if not State then State = {
  current_quantity = Initial_Supply / 10000,
  available = true,
  deadline = 1739193681000 -- 2025-02-10 21:21:21, Asia/Singapore
} end

Handlers.add(
  "Share",
  function(msg)
    if msg.From ==   and msg.Action=="Share" then return true else return false end
  end,
  function(msg)
    xpcall(function(msg)
      assert(msg.Member ~= nil, "missed member tag.")
      assert(type(msg.Member)== "string", "invaild member address.")
      assert(#msg.Member == 44, "invaild member address length.")
      assert(msg.Timestamp <= State.deadline, "faucet expired.")
      assert(State.available == true, "faucet forbiden.")
      assert(utils.includes(msg.Member,BlackList) == false, "this address has been blacklisted.")
      local member = Members[msg.Member]
      assert(member == nil or member.getted == 0, "this address has already distributed.")
      local order = #utils.keys(Members)
      local message = {
        Target = TOKEN.Process,
        Action = "Transfer",
        Quantity = tostring(State.current_quantity),
        Recipient = msg.Member,
        [const.Actions.x_faucet_order] = tostring((order or 0)+1),
        [const.Actions.x_transfer_type] = "Faucet"
      }
      ao.send(message)
    end,function(err)
      print(err)
    end,msg)
  end
)

Handlers.add(
  "_faucet_debit",
  function(msg)
    if msg.From == TOKEN.Process and msg.Tags.Action == "Debit-Notice" and msg.Tags[const.Actions.x_transfer_type] == "Faucet" then return true else return false end
  end,
  function(msg)
    xpcall(function(msg)
      local member = {
        user_id = msg.Recipient,
        msg_id = msg.Id,
        eval_id = msg.Tags['Pushed-For'],
        getted = tonumber(msg.Tags.Quantity),
        timestamp = msg.Timestamp,
        order = msg.Tags[const.Actions.x_faucet_order]
      }
      Members[msg.Recipient] = member
      local message = {
        Target = Owner,
        Action = "Distributed",
        Data = json.encode(member)
      }
      ao.send(message)
    end,function(err)
      print(err)
    end,msg)
  end
)

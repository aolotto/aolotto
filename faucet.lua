local const = require("modules.const")
local utils = require(".utils")
local json = require("json")
local token_config = {
  Ticker = Inbox[1].Ticker or "ALT",
  Process = Inbox[1].Token or "sdqQuIU6WNT1zVNculn814nVhol2XXhDxqgCrUpCtlA",
  Denomination =  tonumber(Inbox[1].Denomination) or 3,
  Name = Inbox[1].Tokenname or "altoken"
}
if not TOKEN then TOKEN = token_config end
if not Members then Members = {} end
if not Initial_Supply then Initial_Supply = 210000000000 * 0.1 end
if not Supplied then Supplied = 0 end
if not BlackList then BlackList = {} end
if not Logs then Logs = {} end
if not State then State = {
  current_quantity = math.floor(Initial_Supply * 0.0001),
  available = true,
  deadline = 1739193681000 -- 2025-02-10 21:21:21, Asia/Singapore
} end

function resetQuantuty(serial)
  assert(serial % 10 == 0, "The serial number does not match the reset conditions")
  State.current_quantity = math.floor((Initial_Supply-Supplied) * 0.0001)
end

Handlers.add(
  "Share",
  function(msg)
    if msg.From == Owner and msg.Action=="Share" then return true else return false end
  end,
  function(msg)
    xpcall(function(msg)
      assert(msg.User ~= nil, "missed user tag.")
      assert(msg.Account ~= nil, "missed address id.")
      assert(type(msg.Account)== "string", "invaild wallet address.")
      assert(#msg.Account == 43, "invaild wallet address length.")
      assert(State.available == true, "faucet forbiden.")
      assert(utils.includes(msg.Account,BlackList) == false, "this address has been blacklisted.")
      local member = Members[msg.User]
      assert(member == nil or member.getted == 0, "this address has already distributed.")
      local order = #utils.keys(Members)
      
      local message = {
        Target = TOKEN.Process,
        Action = "Transfer",
        Quantity = tostring(State.current_quantity),
        Recipient = msg.Account,
        [const.Actions.x_faucet_order] = tostring((order or 0)+1),
        [const.Actions.x_transfer_type] = "Faucet",
        [const.Actions.x_user] = msg.User
      }
      print(message)
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
        user_id = msg.Tags[const.Actions.x_user],
        user_address = msg.Recipient,
        msg_id = msg.Id,
        eval_id = msg.Tags['Pushed-For'],
        getted = tonumber(msg.Tags.Quantity),
        timestamp = msg.Timestamp,
        order = msg.Tags[const.Actions.x_faucet_order]
      }
      local log = {
        id = msg.Id,
        quantity = tonumber(msg.Tags.Quantity),
        to = msg.Recipient,
        type = "debit",
        timestamp = msg.Timestamp
      }
      Members[msg.Tags[const.Actions.x_user]] = member
      Supplied = Supplied + tonumber(msg.Tags.Quantity)
      table.insert(Logs,log)
      if tonumber(msg.Tags[const.Actions.x_faucet_order]) % 10 == 0 then
        resetQuantuty(tonumber(msg.Tags[const.Actions.x_faucet_order]))
      end
      -- local message = {
      --   Target = Owner,
      --   Action = "Distributed",
      --   Data = json.encode(member)
      -- }
      -- ao.send(message)
    end,function(err)
      print(err)
    end,msg)
  end
)

Handlers.add(
  "GetMemberBalance",
  Handlers.utils.hasMatchingTag("Action","GetMemberBalance"),
  function(msg)
    xpcall(function(msg)
      assert(msg.User ~= nil, "missed member tag.")
      local member = Members[msg.User]
      if member then
        Handlers.utils.reply(json.encode(member))(msg)
      end
    end,function(err)
      print(err)
    end,msg)
  end
)

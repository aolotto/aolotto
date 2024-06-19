utils = require(".utils")
json = require("json")
if not AGENT then AGENT = "PYit0XUH1X9GlCWGDg7AIDmHhiRQLziMng0BkRfVe4Q" end

if not ALT then ALT = {data={}} end
ao.authorities = {AGENT,ao.id}
-- function ALT:listArchivedRounds()
--   local utils = utils or require(".utils")
--   local msgs = utils.filter(function (m)
--     return m.Action == "Archive-Round"
--   end,Inbox)
--   local result = {}
--   if #msgs > 0  then
--     utils.map(function (val, key)
--       table.insert(result,val.Id)
--     end,msgs)
--   end
--   return result
-- end

-- function ALT:printArchivedRound(id)
--   local msg = self:qureyArchives(id)
--   if msg then
--     local json = json or require("json")
--     local data = json.decode(msg.Data)
--     return data.draw_info
--   else
--     return "Round msgs not exist"
--   end
-- end

-- function ALT:qureyArchives(id)
--   local utils = utils or require(".utils")
--   return utils.find(
--     function (val) return val.Id == id end,
--     Inbox
--   )
-- end

-- function ALT:processArchivedRound(id)
--   local msg = self:qureyArchives(id)
--   if msg then
--     local json = json or require("json")
--     local data = json.decode(msg.Data)
--     local message = {}
--     -- return data.draw_info
--   end
-- end

function ALT:createArchiveProcess(caller,data)
  local json = json or require("json")
  Spawn(ao._module,{
    Name = "aolotto_round_archive",
    Round = tostring(data.draw_info.round),
    Start = tostring(data.draw_info.raw_round_data.start_time),
    End = tostring(data.draw_info.raw_round_data.end_time),
    Authority = caller,
    Agent = caller,
    Data = json.encode(data)
  })
end

function ALT:sendWinMessage(winner,round)
  local message = {
    Target = winner.id,
    Action="Win-Notice",
    Reawards = tostring(winner.rewards),
    Numbers = tostring(winner.matched),
    Round = tostring(round),
    Data = json.encode(winner)
  }
  ao.send(message)
end

function ALT:noticeWinnners(data)
  local draw_info = data.draw_info
  local winners = draw_info.winners
  assert(#winners>0,"no winners to notice")
  for _, winner in ipairs(winners) do
    self:sendWinMessage(winner,data.draw_info.round)
  end
end

function ALT:sendProcessToAgent(round)
  local utils = utils or require(".utils")
  local processes = round and utils.filter(function (val)
    return val.message.Round == tostring(round)
  end,_processes) or _processes

  if #processes > 0 then
    for i, v in ipairs(processes) do
      _processes[i].notice_count = (_processes[i].notice_count or 0) + 1
      ao.send(v.message)
      if i >= #processes then
        return print(i.." processes have been noticed to the agent!")
      end
    end
  else
    return print("no process to notice.")
  end
end

function ALT:eval(code,process)
  local processes = {}
  if process then
    table.insert(processes,process)
  else
    if #_processes < 1 then return print("no process to eval") end
    for i, v in ipairs(_processes) do
      _processes[i].eval_count = (_processes[i].eval_count or 0) + 1
      table.insert(processes,v.message.ProcessID)
    end
  end
  if #processes > 0 then
    for i, v in ipairs(processes) do

      local message = {
        Target = v,
        Action = "Eval",
        Data = code
      }
      ao.send(message)
      if i >= #processes then
        return print(i.." processes have been evaluated.")
      end
    end
  end
end


function ALT:createAgent(data)
  data = data or {}
  Spawn('z9iaKddl-rIBinPG7_3-oLAdgIujPPPCbUul5mBSIOk', {
    Name = data.Name or "aolotto",
    Operator = ao.id,
    Version = data.Version or "dev",
    Duration = "86400000",
    ["Token-Process"] = data["Token-Process"] or "zQ0DmjTbCEGNoJRcjdwdZTHt0UBorTeWbb_dnc6g41E",
    ["Token-Name"] = data["Token-Name"] or "AlottoToken",
    ["Token-Ticker"] = data["Token-Ticker"] or "ALT",
    ["Cron-Interval"] = "1-minute",
    ["Cron-Tag-Action"] = "Cron"
  })
end


Handlers.add(
  "_archive_round",
  function (msg)
    if ao.isTrusted(msg) and msg.Tags.Action=="Archive-Round" then return true else return false end
  end,
  function (msg)
    xpcall(function (msg)
      local json = json or require("json")
      local caller = msg.From == ao.id and AGENT or msg.From
      print("Archive Round for "..caller)
      local data = json.decode(msg.Data)
      ALT:createArchiveProcess(caller,data)
      ALT.archives = ALT.archives or {}
      ALT.archives[caller] = data
      if #data.draw_info.winners > 0 then
        ALT:noticeWinnners(data)
      end
    end,function (err)
      print("Got an error in _archive_round")
      print(err)
    end,msg)
  end
)


Handlers.add(
  "_spawned_round",
  function (msg)
    if msg.Tags.Action=="Spawned" and msg.Tags.Round then return true else return false end
  end,
  function (msg)
    xpcall(function (msg)
      _processes = _processes or {}
     
      local message = {
        Target = msg.Tags.Agent,
        Action = "Round-Spawned",
        ProcessID = msg.Process,
        Round = msg.Tags.Round
      }
      Send(message)
      table.insert(_processes,{message=message})
      ALT.archives[msg.Tags.Agent] = nil
    end,function (err)
      print("Error in _spawned_round:")
      print(err)
    end,msg)
  end
)
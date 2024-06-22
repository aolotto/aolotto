local const = require("modules.const")
local json = require("json")
local Archives = {} 

function Archives:add(no,data)
  self.repo = self.repo or {}
  self.repo[tostring(no)] =  json.encode(data)
end

function Archives:remove(no)
  if self.repo then
    self.repo[tostring(no)] = nil
  end
end

function Archives:get(no)
  if self.repo[tostring(no)] then return json.decode(self.repo[tostring(no)]) end
end

function Archives:set(no,data)
  self.repo = self.repo or {}
  self.repo[tostring(no)] = type(data) == "string" and data or json.encode(data)
end

function Archives:transfer_data(no,archiver_process,timestamp)
  assert(archiver_process ~= nil,"missed target process to archive.")
  self.repo = self.repo or {}
  self.logs = self.logs or {}
  if self.repo[tostring(no)]~=nil then
    ao.send({
      Target = archiver_process,
      Action = const.Actions.archive_round,
      Round = tostring(no),
      Data = self.repo[tostring(no)]
    })

    table.insert(self.logs ,{round=tostring(no), archiver=archiver_process, timestamp=timestamp})
  end
end 

return Archives
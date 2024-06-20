local const = require("const")
local json = require("json")
local Archives = {} 

function Archives:add(no,data)
  self[tostring(no)] =  json.encode(data)
  local message = {
    Target= self.archiver,
    Action= const.Actions.archive_round,
    Round = tostring(no),
    Data= json.encode(data)
  }
  ao.send(message)
end

function Archives:remove(no)
  self[tostring(no)] = nil
end
crypto = require(".crypto")

getRandomNumber = function (msg,lens)
  local crypto  = crypto or require(".crypto")
  local numbers = {}
  for i = 1, lens or 3 do
    local r = crypto.cipher.issac.getRandom()
    table.insert(numbers,crypto.cipher.issac.random(0, 9, tostring(i)..msg.Timestamp..tostring(r)))
  end
  return numbers
end
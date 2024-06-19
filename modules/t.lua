local t = {}

function t:print()
  return print(self.data or "hellow")
end


function t:save(data)
  self.data = data
end

return t
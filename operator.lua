OP = OP or {}

OP.createPool = function(self, id, tbl)
  self[id] = self[id] or {}
  for k,v in pairs(tbl) do
    self[id][k] = v
  end
end

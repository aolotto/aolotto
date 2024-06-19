local state = {}

function state:set(k,v)
  assert(k~=nil,"Missed key")
  self = self or {}
  self[k] = v
end

function state:get(k)
  return self[k]
end

function state:increasePoolBalance(qty)
  self.total_pool_balance = (self.total_pool_balance or 0) + tonumber(qty)
  self.pool_balance = (self.pool_balance or 0) + tonumber(qty)
end

function state:decreasePoolBalance(qty)
  self.pool_balance = math.max((self.pool_balance or 0) - tonumber(qty))
end

function state:increaseOperatorBalance(qty,rate)
  self.operator_balance = (self.operator_balance or 0) + tonumber(qty) * (rate or self.tax_rete)
  self.total_operator_balance = (self.total_operator_balance or 0) + tonumber(qty) * (rete or self.tax_rete)
end

function state:decreaseOperatorBalance(qty)
  self.operator_balance = math.max((self.operator_balance or 0) - tonumber(qty))
end

function state:increaseClaimPaid(qty)
  self.total_claim_paid = (self.total_claim_paid or 0) + tonumber(qty)
end

function state:increaseWithdraw(qty)
  self.op_withdraw = (self.op_withdraw or 0) + tonumber(qty)
end


return state
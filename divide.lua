if not PenddingDividends then PenddingDividends = {} end

Handlers.add("divide",{
  Action = "Credit-Notice",
  Quantity = "_",
  ['X-Transfer-Type'] = "Divide",
  ['X-Dividend-Snap'] = "_"
},function(msg)
  Handlers.divide(msg['X-Dividend-Snap'], msg.From, msg.Quantity, msg)
end)

Handlers.divide = function(snap_process, assets_process, quantity, m)
  assert(snap_process~=nil,"Missed snap process.")
  assert(assets_process~=nil,"Missed assets process.")
  assert(quantity~=nil,"Missed quantity.")
  Send({
    Target = snap_process,
    Action = "Get-Dividend-Snap",
  }).onReply(function(msg)

    print(msg.Total)
    
    local unit_amount = tonumber(quantity) / tonumber(msg.Total)
    local shared = 0
    local count = 0
    for k,v in pairs(msg.Data) do
      local amount = math.floor(tonumber(v) * unit_amount)
      print(k.." : "..amount)
      PenddingDividends[msg.Id .. "-" .. k] = {
        assets_process = assets_process,
        unit_amount = unit_amount,
        amount = string.format("%.0f",amount),
        snap_id = msg.Id,
        total_dividends = tonumber(quantity),
        recipient = k
      }
      Send({
        Target = assets_process,
        Recipient = k,
        Quantity = string.format("%.0f",amount),
        ['X-Dividend-Id'] = m.Id,
        ['X-Dividends'] = quantity,
        ['X-Dividend-Asset'] = assets_process,
        ['X-Dividend-Snap-Id'] = msg.Id,
        ['X-Dividend-Unit'] = tostring(unit_amount),
        ['X-Divident-Trigger'] = m.From,
        ['Pushed-For'] = msg['Pushed-For']
      })
      shared = shared + amount
      count = count + 1 
    end
    
    print(count .. " address shared : ".. shared)
  end)
end
pause = false
subscriber = "pgMXPlpSxmp2r6EqIRkpv0M1c7WlRZZm77CoEdUP1VA"
AOLOTTO = "wqwklmuSqSPGaeMR7dHuciyvBDtt1UjmziAoWu-pKuI"


Handlers.add(
  "CronTick",
  Handlers.utils.hasMatchingTag("Action", "Cron"),
  function (msg)
    if subscriber and pause == false then
      local short_time = tostring(msg.Timestamp)
      ao.send({
        Target = subscriber,
        Action = "1m_shoot",
        ShootTime = short_time,
        Data = short_time,
      })
    end
  end
)

Handlers.add(
  "changeSubscriber",
  function (msg)
    if msg.From == AOLOTTO and msg.Action == "ChangeSubscriber" then
      return true
    else
      return false
    end
  end,
  function (msg)
    subscriber = msg.Data
  end
)

Handlers.add(
  "pause",
  function (msg)
    if msg.From == AOLOTTO and msg.Action == "Pause" then
      return true
    else
      return false
    end
  end,
  function (msg)
    pause = true
  end
)


Handlers.add(
  "start",
  function (msg)
    if msg.From == AOLOTTO and msg.Action == "Start" then
      return true
    else
      return false
    end
  end,
  function (msg)
    pause = false
  end
)
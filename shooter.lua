if not pause then pause = false end
if not subscriber then subscriber = "pgMXPlpSxmp2r6EqIRkpv0M1c7WlRZZm77CoEdUP1VA" end
if not AOLOTTO then AOLOTTO = "wqwklmuSqSPGaeMR7dHuciyvBDtt1UjmziAoWu-pKuI" end


Handlers.add(
  "CronTick",
  Handlers.utils.hasMatchingTag("Action", "Cron"),
  function (msg)
    ao.send({
      Target = AOLOTTO,
      Action = "Shoot"
    })
    -- if subscriber and pause == false then
      
    --   print("cron->"..short_time)
    --   local short_time = msg.Timestamp
    --   ao.send({
    --     Target = subscriber,
    --     Action = "1m_shoot",
    --     ShootTime = short_time,
    --     Data = short_time,
    --   })
    -- end
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



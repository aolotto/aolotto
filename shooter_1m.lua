subscriber = "pgMXPlpSxmp2r6EqIRkpv0M1c7WlRZZm77CoEdUP1VA"
AOLOTTO = "wqwklmuSqSPGaeMR7dHuciyvBDtt1UjmziAoWu-pKuI"


Handlers.add(
  "CronTick",
  Handlers.utils.hasMatchingTag("Action", "Cron"),
  function (msg)
    if subscriber then
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
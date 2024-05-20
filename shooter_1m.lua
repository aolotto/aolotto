ACTION_NAME = "1m_shoot"
subscribers = {"wqwklmuSqSPGaeMR7dHuciyvBDtt1UjmziAoWu-pKuI"}


Handlers.add(
  "CronTick",
  Handlers.utils.hasMatchingTag("Action", "Cron"),
  function (msg)
    if #subscribers > 0 then
      local short_time = tostring(msg.Timestamp)
      ao.send({
        Target = ao.id,
        Action = ACTION_NAME,
        ShootTime = short_time,
        Data = short_time,
        Assignments = subscribers
      })
    end
  end
)
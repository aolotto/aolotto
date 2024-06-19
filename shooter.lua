if not pause then pause = false end
if not AOLOTTO then AOLOTTO = "PYit0XUH1X9GlCWGDg7AIDmHhiRQLziMng0BkRfVe4Q" end

if not CONST then CONST = require("modules.const") end

Handlers.add(
  "CronTick",
  Handlers.utils.hasMatchingTag("Action", "Cron"),
  function (msg)
    ao.send({
      Target = AOLOTTO,
      Action = CONST.Actions.shoot
    })
  end
)

-- Handlers.add(
--   "changeSubscriber",
--   function (msg)
--     if msg.From == AOLOTTO and msg.Action == "ChangeSubscriber" then
--       return true
--     else
--       return false
--     end
--   end,
--   function (msg)
--     subscriber = msg.Data
--   end
-- )

-- Handlers.add(
--   "pause",
--   function (msg)
--     if msg.From == AOLOTTO and msg.Action == "Pause" then
--       return true
--     else
--       return false
--     end
--   end,
--   function (msg)
--     pause = true
--   end
-- )


-- Handlers.add(
--   "start",
--   function (msg)
--     if msg.From == AOLOTTO and msg.Action == "Start" then
--       return true
--     else
--       return false
--     end
--   end,
--   function (msg)
--     pause = false
--   end
-- )



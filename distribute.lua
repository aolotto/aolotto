local const = require("modules.const")
local messenger = require("modules.messenger")

--[[ 结束轮次 ]]

Handlers.add(
  "_finish",
  function (msg)
    local is_operator = msg.From == OPERATOR or msg.From == ao.id
    if is_operator and msg.Tags.Action == const.Actions.finish then return true else return false end
  end,
  function (msg)
    xpcall(function (msg)
      assert(CURRENT.bets_amount >= CURRENT.base_rewards, "amount not reached")
      assert(msg.Timestamp >= (CURRENT.start_time + CURRENT.duration), "amount not reached")
      local archive = CURRENT:archive(msg)
      ARCHIVES:add(archive)
      -- 重置轮次信息
      CURRENT:new(msg)
      -- 触发token进程铸造新币
      ao.send({
        Target = TOKEN.Process,
        Action = const.Actions.mint_rewards,
        Round = archive.no
      })

      -- 通知所有用户轮次切换
      local assignments = utils.map(
        function (val, key) return val.id end,
        USERS:queryAllusers()
      )
      messenger:sendRoundSwitchNotice(CURRENT,assignments,TOKEN)
    end,function (err)
      print(err)
    end,msg)
  end
)

-- [[ 铸币分发 ]]

Handlers.add(
  "_minted",
  Handlers.utils.hasMatchingTag("Action",const.Actions.minted),
  function(msg)
    xpcall(function (msg)
      if msg.From == TOKEN.Process then
        assert(type(msg.Quantity)=='string',"Quantity required!")
        assert(tonumber(msg.Quantity) > 0, "Quantity must larger than 0.")
        USERS:increaseAllRewardBalance(tonumber(msg.Quantity), msg.Timestamp)
        STATE:increasePoolBalance(msg.Quantity)
        STATE:increaseOperatorBalance(msg.Quantity)
      end
    end,function (err)
      print(err)
    end,msg)
  end
)
_utils = {}

_utils.sendError = function (err,target)
  ao.send({Target=target,Action="Error",Error=Dump(err),Data="400"})
end
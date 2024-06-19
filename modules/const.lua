local Const = {} 
Const.Actions = {
  lotto_notice = "Lotto-Notice",
  finish = "Finish",
  archive_round = "Archive-Round",
  round_spawned = "Round-Spawned",
  reply_rounds ="Reply-Rounds",
  bets = "Bets",
  reply_user_bets = "Reply-UserBets",
  reply_user_info = "Reply-UserInfo",
  user_info = "UserInfo",
  claim = "Claim",
  OP_withdraw = "OP_withdraw",
  x_transfer_type = "X-Transfer-Type",
  shoot = "Shoot",
  change_shooter = "ChangeShooter",
  change_archiver = "ChangeArchiver",
  round_archived = "Round-Archived",
  pause_round = "Pause-Round",
  round_restart = "Restart-Round"
}

Const.RoundStatus = {
  [-1] = "Canceled",
  [0] = "Ongoing",
  [1] = "Ended",
  [2] = "Paused"
}
Const.ErrorCode = {
  default = "400",
  transfer_error = "Transfer-Error"
}

return Const
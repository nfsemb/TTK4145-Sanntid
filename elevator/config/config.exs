import Config

config :elevator,
  standardElevatorSimPort: 15657,
  standardElevatorSimIP: {127, 0, 0, 1},
  topFloor: 3,
  pollingRate: 200,
  backupRate: 10_000,
  backupRandomInterval: 2_000,
  orderWatchdogWaitingTime: 30_000,
  orderWatchdogRandomInterval: 3_000,
  broadcastRate: 200,
  broadcastIP: {255, 255, 255, 255},
  udpPort: 30_000,
  timeBetweenFloors: 1_500,
  waitTimeOnFloor: 2_000,
  motorTimeout: 4_000

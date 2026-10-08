local config = {}

-- Optional: set the exact peripheral names if more than two monitors are on the network.
-- Example: { "monitor_12", "monitor_13" }
config.MONITOR_NAMES = { nil, nil }

config.TEXT_SCALE = 0.5
config.TICK_RATE = 0.10

config.MIN_RECOMMENDED_WIDTH = 45
config.MIN_RECOMMENDED_HEIGHT = 42

config.ARENA = {
    width = 100,
    height = 160,
    riverTop = 74,
    riverBottom = 86,
    bridgeCenters = { 27, 73 },
    bridgeHalfWidth = 7,
}

config.MUSIC = {
    enabled = true,
    volume = 0.36,
}

config.MATCH = {
    normalTime = 150,
    overtimeTime = 150,
    tiebreakerDamagePerSecond = 300,
    emeraldMax = 10,
    emeraldStart = 5,
    emeraldPerSecond = 1 / 2.8,
    overtimeMultiplier = 2,
    overtimeFinalSeconds = 30,
    overtimeFinalMultiplier = 3,
    countdown = 3,
}

config.DEBUG = false

return config

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

    -- After a Princess Tower falls, only that lane unlocks on the enemy side.
    -- The pocket extends slightly past the old tower line, while a centre gap
    -- prevents dropping troops directly on top of the King Tower.
    enemyPrincessYTop = 28,
    enemyPrincessYBottom = 132,
    pocketPastTower = 4,
    pocketCenterGap = 6,
}

config.MUSIC = {
    enabled = true,
    volume = 0.45,
}

config.BUILDINGS = {
    -- Natural lifetime HP loss. 1.15 = 15% faster than linear lifetime decay.
    lifetimeDecayMultiplier = 1.15,
}

config.TOWERS = {
    -- At 42.5, a lane Princess Tower starts covering a troop roughly two
    -- arena units after it exits the bridge. King range stays intentionally
    -- shorter so both Princess lanes are not covered from the centre.
    princessRange = 42.5,
    kingRange = 27,
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

-- Shared lobby rules. Game.new() copies these defaults into state.ruleset so
-- future match-wide toggles can be added without hard-coding them into the UI.
config.RULESET_DEFAULTS = {
    evolutions = true,
}

config.DEBUG = false

return config

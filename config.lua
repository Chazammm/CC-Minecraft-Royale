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

function config.validate()
    local function positive(name, value)
        if type(value) ~= "number" or value <= 0 then
            error("Invalid config: " .. name .. " must be > 0", 0)
        end
    end

    positive("TEXT_SCALE", config.TEXT_SCALE)
    positive("TICK_RATE", config.TICK_RATE)
    positive("ARENA.width", config.ARENA and config.ARENA.width)
    positive("ARENA.height", config.ARENA and config.ARENA.height)
    positive(
        "BUILDINGS.lifetimeDecayMultiplier",
        config.BUILDINGS and config.BUILDINGS.lifetimeDecayMultiplier
    )
    positive(
        "MATCH.tiebreakerDamagePerSecond",
        config.MATCH and config.MATCH.tiebreakerDamagePerSecond
    )

    -- Arena/tower/bot geometry is intentionally authored for the canonical
    -- 100x160 battlefield. Fail loudly instead of accepting a partially
    -- rescaled configuration with inconsistent hard-coded positions.
    if config.ARENA.width ~= 100 or config.ARENA.height ~= 160 then
        error("Invalid config: arena size is fixed at 100x160", 0)
    end

    if type(config.ARENA.riverTop) ~= "number"
        or type(config.ARENA.riverBottom) ~= "number"
        or config.ARENA.riverTop <= 0
        or config.ARENA.riverBottom >= config.ARENA.height
        or config.ARENA.riverTop >= config.ARENA.riverBottom
    then
        error("Invalid config: river bounds must be ordered inside the arena", 0)
    end

    if type(config.MATCH.emeraldPerSecond) ~= "number"
        or config.MATCH.emeraldPerSecond < 0
    then
        error("Invalid config: MATCH.emeraldPerSecond must be >= 0", 0)
    end

    positive("MATCH.normalTime", config.MATCH.normalTime)
    positive("MATCH.overtimeTime", config.MATCH.overtimeTime)
    positive("MATCH.emeraldMax", config.MATCH.emeraldMax)
    positive("MATCH.overtimeMultiplier", config.MATCH.overtimeMultiplier)
    positive("MATCH.overtimeFinalMultiplier", config.MATCH.overtimeFinalMultiplier)
    return true
end

config.validate()

return config

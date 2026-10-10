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
    httpTimeout = 6,
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

function config.validate(candidate)
    local cfg = candidate or config

    local function finiteNumber(name, value)
        if type(value) ~= "number"
            or value ~= value
            or value == math.huge
            or value == -math.huge
        then
            error("Invalid config: " .. name .. " must be a finite number", 0)
        end
        return value
    end

    local function positive(name, value)
        finiteNumber(name, value)
        if value <= 0 then
            error("Invalid config: " .. name .. " must be > 0", 0)
        end
    end

    local function nonNegative(name, value)
        finiteNumber(name, value)
        if value < 0 then
            error("Invalid config: " .. name .. " must be >= 0", 0)
        end
    end

    positive("TEXT_SCALE", cfg.TEXT_SCALE)
    if cfg.TEXT_SCALE < 0.5 or cfg.TEXT_SCALE > 5
        or math.abs(cfg.TEXT_SCALE * 2 - math.floor(cfg.TEXT_SCALE * 2 + 0.5)) > 1e-9
    then
        error("Invalid config: TEXT_SCALE must be 0.5..5 in 0.5 steps", 0)
    end

    local monitorNames = cfg.MONITOR_NAMES
    if type(monitorNames) ~= "table" then
        error("Invalid config: MONITOR_NAMES must be a table", 0)
    end
    local monitor1, monitor2 = monitorNames[1], monitorNames[2]
    if (monitor1 == nil) ~= (monitor2 == nil) then
        error("Invalid config: MONITOR_NAMES must set both monitors or neither", 0)
    end
    if monitor1 ~= nil then
        if type(monitor1) ~= "string" or monitor1 == ""
            or type(monitor2) ~= "string" or monitor2 == ""
        then
            error("Invalid config: MONITOR_NAMES entries must be non-empty strings", 0)
        end
        if monitor1 == monitor2 then
            error("Invalid config: MONITOR_NAMES must name two different monitors", 0)
        end
    end

    positive("MIN_RECOMMENDED_WIDTH", cfg.MIN_RECOMMENDED_WIDTH)
    positive("MIN_RECOMMENDED_HEIGHT", cfg.MIN_RECOMMENDED_HEIGHT)
    if cfg.MIN_RECOMMENDED_WIDTH ~= math.floor(cfg.MIN_RECOMMENDED_WIDTH)
        or cfg.MIN_RECOMMENDED_HEIGHT ~= math.floor(cfg.MIN_RECOMMENDED_HEIGHT)
    then
        error("Invalid config: recommended monitor dimensions must be integers", 0)
    end

    if type(cfg.RULESET_DEFAULTS) ~= "table"
        or type(cfg.RULESET_DEFAULTS.evolutions) ~= "boolean"
    then
        error("Invalid config: RULESET_DEFAULTS.evolutions must be boolean", 0)
    end
    if type(cfg.DEBUG) ~= "boolean" then
        error("Invalid config: DEBUG must be boolean", 0)
    end

    positive("TICK_RATE", cfg.TICK_RATE)
    if cfg.TICK_RATE > 0.25 then
        error("Invalid config: TICK_RATE must be <= 0.25 seconds", 0)
    end

    positive("ARENA.width", cfg.ARENA and cfg.ARENA.width)
    positive("ARENA.height", cfg.ARENA and cfg.ARENA.height)
    positive("ARENA.bridgeHalfWidth", cfg.ARENA and cfg.ARENA.bridgeHalfWidth)
    positive(
        "BUILDINGS.lifetimeDecayMultiplier",
        cfg.BUILDINGS and cfg.BUILDINGS.lifetimeDecayMultiplier
    )
    positive(
        "MATCH.tiebreakerDamagePerSecond",
        cfg.MATCH and cfg.MATCH.tiebreakerDamagePerSecond
    )

    if cfg.ARENA.width ~= 100 or cfg.ARENA.height ~= 160 then
        error("Invalid config: arena size is fixed at 100x160", 0)
    end

    if type(cfg.ARENA.riverTop) ~= "number"
        or type(cfg.ARENA.riverBottom) ~= "number"
        or cfg.ARENA.riverTop <= 0
        or cfg.ARENA.riverBottom >= cfg.ARENA.height
        or cfg.ARENA.riverTop >= cfg.ARENA.riverBottom
    then
        error("Invalid config: river bounds must be ordered inside the arena", 0)
    end

    if type(cfg.ARENA.bridgeCenters) ~= "table"
        or #cfg.ARENA.bridgeCenters == 0
    then
        error("Invalid config: ARENA.bridgeCenters must contain at least one bridge", 0)
    end

    local previousCenter = nil
    for i, center in ipairs(cfg.ARENA.bridgeCenters) do
        finiteNumber("ARENA.bridgeCenters[" .. i .. "]", center)
        if center - cfg.ARENA.bridgeHalfWidth <= 0
            or center + cfg.ARENA.bridgeHalfWidth >= cfg.ARENA.width
        then
            error("Invalid config: bridge " .. i .. " extends outside the arena", 0)
        end
        if previousCenter
            and center - previousCenter <= cfg.ARENA.bridgeHalfWidth * 2
        then
            error("Invalid config: bridge rectangles must not overlap", 0)
        end
        previousCenter = center
    end

    nonNegative("MATCH.emeraldPerSecond", cfg.MATCH.emeraldPerSecond)
    positive("MATCH.normalTime", cfg.MATCH.normalTime)
    positive("MATCH.overtimeTime", cfg.MATCH.overtimeTime)
    positive("MATCH.emeraldMax", cfg.MATCH.emeraldMax)
    nonNegative("MATCH.emeraldStart", cfg.MATCH.emeraldStart)
    if cfg.MATCH.emeraldStart > cfg.MATCH.emeraldMax then
        error("Invalid config: MATCH.emeraldStart must not exceed emeraldMax", 0)
    end

    positive("MATCH.overtimeMultiplier", cfg.MATCH.overtimeMultiplier)
    positive("MATCH.overtimeFinalMultiplier", cfg.MATCH.overtimeFinalMultiplier)
    nonNegative("MATCH.overtimeFinalSeconds", cfg.MATCH.overtimeFinalSeconds)
    if cfg.MATCH.overtimeFinalSeconds > cfg.MATCH.overtimeTime then
        error("Invalid config: overtimeFinalSeconds must not exceed overtimeTime", 0)
    end
    nonNegative("MATCH.countdown", cfg.MATCH.countdown)

    positive("TOWERS.princessRange", cfg.TOWERS and cfg.TOWERS.princessRange)
    positive("TOWERS.kingRange", cfg.TOWERS and cfg.TOWERS.kingRange)

    if cfg.MUSIC then
        if cfg.MUSIC.enabled ~= nil and type(cfg.MUSIC.enabled) ~= "boolean" then
            error("Invalid config: MUSIC.enabled must be boolean", 0)
        end
        finiteNumber("MUSIC.volume", cfg.MUSIC.volume)
        if cfg.MUSIC.volume < 0 or cfg.MUSIC.volume > 3 then
            error("Invalid config: MUSIC.volume must be between 0 and 3", 0)
        end
        positive("MUSIC.httpTimeout", cfg.MUSIC.httpTimeout)
    end

    return true
end

config.validate()

return config

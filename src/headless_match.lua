local config = require("config")
local Game = require("src.game")
local Bot = require("src.bot")
local util = require("src.util")
local benchmark = require("src.benchmark_utils")
local cards = require("src.cards")

local Runner = {}

local function normalizedGameplaySeed(seed)
    local parsed, err = benchmark.parseSeed(seed, 1)
    if not parsed then error(err, 0) end
    local value = parsed % 2147483647
    if value <= 0 then value = value + 2147483646 end
    return value
end

local function firstBotForTick(tick, orderOffset)
    return (tick + (orderOffset or 0)) % 2 == 0 and 1 or 2
end

local function updateBots(bot1, bot2, state, dt, tick, orderOffset)
    if firstBotForTick(tick, orderOffset) == 1 then
        Bot.update(bot1, state, dt)
        Bot.update(bot2, state, dt)
    else
        Bot.update(bot2, state, dt)
        Bot.update(bot1, state, dt)
    end
end

local function tiebreakerBudgetSeconds(state)
    local highestTowerHp = 0
    for _, entity in ipairs(state.entities) do
        if entity.alive and entity.kind == "tower" then
            highestTowerHp = math.max(
                highestTowerHp,
                entity.maxHp or entity.hp or 0
            )
        end
    end

    local rate = math.max(
        0.000001,
        config.MATCH.tiebreakerDamagePerSecond or 300
    )

    -- The maximum starting tower HP is a safe upper bound even if the real
    -- tiebreaker begins after towers have already taken damage.
    return highestTowerHp / rate + 5
end

function Runner.run(deck1, deck2, options)
    options = options or {}
    for owner = 1, 2 do
        local deck
        if owner == 1 then deck = deck1 else deck = deck2 end
        if deck ~= nil and not cards.isValidDeck(deck) then
            error("Headless player " .. owner .. " deck must contain eight distinct playable cards", 0)
        end
    end
    local dt = tonumber(options.dt == nil and config.TICK_RATE or options.dt)
    if not util.isFiniteNumber(dt) or dt <= 0 or dt > 0.25 then
        error("Headless dt must be > 0 and <= 0.25 seconds", 0)
    end
    local offset = options.botOrderOffset == nil and 0 or tonumber(options.botOrderOffset)
    if not util.isFiniteNumber(offset) then
        error("Bot order offset must be a finite number", 0)
    end
    local botOrderOffset = math.floor(offset) % 2
    local yieldCheckTicks = options.yieldCheckTicks == nil and 50 or tonumber(options.yieldCheckTicks)
    if not util.isFiniteNumber(yieldCheckTicks) or yieldCheckTicks < 0
        or yieldCheckTicks ~= math.floor(yieldCheckTicks)
    then error("Yield interval must be a finite non-negative integer", 0) end
    for _, key in ipairs({"configure", "yieldFn", "onTick"}) do
        if options[key] ~= nil and type(options[key]) ~= "function" then
            error("Headless " .. key .. " must be a function", 0)
        end
    end

    if options.gameplaySeed ~= nil then
        math.randomseed(normalizedGameplaySeed(options.gameplaySeed))
    end

    local state = Game.new(nil, {
        headlessSimulation = true,
    })
    local bot1 = Bot.new(1, deck1)
    local bot2 = Bot.new(2, deck2)

    Bot.prepare(bot1, state)
    Bot.prepare(bot2, state)

    if options.configure then
        options.configure(state, bot1, bot2)
    end

    state.players[1].ready = true
    state.players[2].ready = true

    local started, skippedTicks = Game.startHeadlessBattle(state, dt)
    if not started then
        error(skippedTicks or "Could not start headless battle", 0)
    end

    Bot.beginMatch(bot1)
    Bot.beginMatch(bot2)
    bot1.enabled = true
    bot2.enabled = true

    -- The original live/benchmark driver updates both bots once on the tick
    -- that flips countdown -> battle, after Game.update has returned. Preserve
    -- that exact timer/memory step even though headless mode skips inert
    -- countdown engine updates.
    local transitionTick = math.max(0, skippedTicks - 1)
    updateBots(bot1, bot2, state, dt, transitionTick, botOrderOffset)
    if options.onTick then options.onTick(state, bot1, bot2, skippedTicks) end

    local ticks = skippedTicks
    local maxSimulationSeconds =
        (config.MATCH.countdown or 0)
        + (config.MATCH.normalTime or 0)
        + (config.MATCH.overtimeTime or 0)
        + tiebreakerBudgetSeconds(state)
    local maxTicks = math.ceil(maxSimulationSeconds / dt)

    while state.phase ~= "result" and ticks < maxTicks do
        Game.update(state, dt)
        updateBots(bot1, bot2, state, dt, ticks, botOrderOffset)
        ticks = ticks + 1
        if options.onTick then options.onTick(state, bot1, bot2, ticks) end

        if options.yieldFn
            and yieldCheckTicks > 0
            and ticks % yieldCheckTicks == 0
        then
            options.yieldFn(false)
        end
    end

    if options.yieldFn then options.yieldFn(false) end

    if state.phase ~= "result" then
        -- A defensive-budget timeout is a failed simulation, not a genuine
        -- draw. Never let benchmark aggregators silently score it as 0.5.
        error(options.timeoutReason or "HEADLESS MATCH TIMEOUT", 0)
    end

    return state, bot1, bot2, ticks
end

function Runner.debugFirstBotForTick(tick, orderOffset)
    return firstBotForTick(tick, orderOffset)
end

return Runner

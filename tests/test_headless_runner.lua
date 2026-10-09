-- Prove the shared benchmark driver preserves the original tick/update order.

colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768,
}

package.path = "./?.lua;./?/init.lua;" .. package.path

local config = require("config")
local Game = require("src.game")
local Bot = require("src.bot")
local Runner = require("src.headless_match")

local function assertEq(actual, expected, message)
    if actual ~= expected then
        error((message or "assertEq failed")
            .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual))
    end
end

local function updateBots(bot1, bot2, state, tick)
    if tick % 2 == 0 then
        Bot.update(bot1, state, config.TICK_RATE)
        Bot.update(bot2, state, config.TICK_RATE)
    else
        Bot.update(bot2, state, config.TICK_RATE)
        Bot.update(bot1, state, config.TICK_RATE)
    end
end

local function legacyRun(deck1, deck2, seed)
    math.randomseed(seed)

    local state = Game.new(nil, { headlessSimulation = true })
    local bot1 = Bot.new(1, deck1)
    local bot2 = Bot.new(2, deck2)
    Bot.prepare(bot1, state)
    Bot.prepare(bot2, state)

    state.players[1].ready = true
    state.players[2].ready = true
    local started, skippedTicks = Game.startHeadlessBattle(
        state,
        config.TICK_RATE
    )
    assert(started, skippedTicks)

    Bot.beginMatch(bot1)
    Bot.beginMatch(bot2)
    bot1.enabled = true
    bot2.enabled = true

    updateBots(bot1, bot2, state, math.max(0, skippedTicks - 1))

    local ticks = skippedTicks
    local maxTicks = math.ceil(
        (
            config.MATCH.countdown
            + config.MATCH.normalTime
            + config.MATCH.overtimeTime
            + 30
        ) / config.TICK_RATE
    )

    while state.phase ~= "result" and ticks < maxTicks do
        Game.update(state, config.TICK_RATE)
        updateBots(bot1, bot2, state, ticks)
        ticks = ticks + 1
    end

    if state.phase ~= "result" then
        Game.finish(state, nil, "LEGACY TEST TIMEOUT")
    end

    return state, bot1, bot2
end

local deck1 = Bot.defaultDeck()
local deck2 = {
    "skeleton", "iron_golem", "bat_swarm", "creeper",
    "slime", "witch", "spider", "wolf",
}
local seed = 90210

local legacy, legacyBot1, legacyBot2 = legacyRun(deck1, deck2, seed)
local shared, sharedBot1, sharedBot2 = Runner.run(deck1, deck2, {
    dt = config.TICK_RATE,
    gameplaySeed = seed,
    timeoutReason = "LEGACY TEST TIMEOUT",
})

assertEq(shared.phase, legacy.phase, "Shared runner must preserve phase")
assertEq(shared.winner, legacy.winner, "Shared runner must preserve winner")
assertEq(
    shared.resultReason,
    legacy.resultReason,
    "Shared runner must preserve result reason"
)
assertEq(shared.timeLeft, legacy.timeLeft, "Shared runner must preserve clock")
assertEq(
    shared.combatTick,
    legacy.combatTick,
    "Shared runner must preserve combat tick count"
)
assertEq(
    shared.stats.elapsed,
    legacy.stats.elapsed,
    "Shared runner must preserve elapsed telemetry"
)
assertEq(sharedBot1.actions, legacyBot1.actions, "Shared runner P1 actions")
assertEq(sharedBot2.actions, legacyBot2.actions, "Shared runner P2 actions")
assertEq(
    sharedBot1.decisionCount,
    legacyBot1.decisionCount,
    "Shared runner P1 decisions"
)
assertEq(
    sharedBot2.decisionCount,
    legacyBot2.decisionCount,
    "Shared runner P2 decisions"
)

for playerId = 1, 2 do
    local a = shared.players[playerId]
    local b = legacy.players[playerId]
    assertEq(a.emeralds, b.emeralds, "Shared runner Emeralds P" .. playerId)
    assertEq(
        a.towersDestroyed,
        b.towersDestroyed,
        "Shared runner tower score P" .. playerId
    )

    local sa = shared.stats.players[playerId]
    local sb = legacy.stats.players[playerId]
    assertEq(sa.cardsPlayed, sb.cardsPlayed, "Shared runner cards played")
    assertEq(sa.emeraldSpent, sb.emeraldSpent, "Shared runner Emerald spend")
    assertEq(sa.unitDamage, sb.unitDamage, "Shared runner unit damage")
    assertEq(sa.towerDamage, sb.towerDamage, "Shared runner tower damage")
end

assertEq(
    #shared.entities,
    #legacy.entities,
    "Shared runner must preserve final entity count"
)
for i = 1, #legacy.entities do
    local a = shared.entities[i]
    local b = legacy.entities[i]
    assertEq(a.id, b.id, "Shared runner entity id")
    assertEq(a.owner, b.owner, "Shared runner entity owner")
    assertEq(a.name, b.name, "Shared runner entity identity")
    assertEq(a.hp, b.hp, "Shared runner entity HP")
    assertEq(a.x, b.x, "Shared runner entity X")
    assertEq(a.y, b.y, "Shared runner entity Y")
    assertEq(a.targetId, b.targetId, "Shared runner target")
    assertEq(a.lockedTargetId, b.lockedTargetId, "Shared runner target lock")
end

print("Headless runner parity tests passed")

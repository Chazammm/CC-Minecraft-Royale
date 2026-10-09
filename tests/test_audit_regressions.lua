-- Regression tests added by the full-project technical audit.
-- Kept separate from test_v1.lua so that legacy smoke coverage does not keep
-- approaching Lua's per-chunk local-variable limit.

colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768,
}

package.path = "./?.lua;./?/init.lua;" .. package.path

local config = require("config")
local cards = require("src.cards")
local arena = require("src.arena")
local Game = require("src.game")
local Bot = require("src.bot")
local util = require("src.util")

local function assertEq(actual, expected, message)
    if actual ~= expected then
        error((message or "assertEq failed")
            .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual))
    end
end

local function assertNear(actual, expected, epsilon, message)
    if math.abs(actual - expected) > (epsilon or 1e-9) then
        error((message or "assertNear failed")
            .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual))
    end
end

local function assertTrue(value, message)
    if not value then error(message or "assertTrue failed") end
end

local function findEntity(state, predicate)
    for _, entity in ipairs(state.entities) do
        if predicate(entity) then return entity end
    end
    return nil
end

do
    -- Counterpush detection must be rotationally symmetric. Backline units
    -- are not "advanced" for either P1 or P2.
    local p1 = Game.new()
    Game.debugLoadScenario(p1, "empty")
    assertTrue(Game.debugSpawnCard(p1, 1, "iron_golem", 25, 145))
    local p1Golem = findEntity(p1, function(e)
        return e.owner == 1 and e.sourceCardId == "iron_golem"
    end)
    assertTrue(p1Golem ~= nil, "P1 counterpush test needs Iron Golem")
    local lane = Bot.debugCounterpushLane(p1, 1)
    assertEq(lane, nil, "P1 backline unit must not count as counterpush")
    p1Golem.y = 100
    lane = Bot.debugCounterpushLane(p1, 1)
    assertEq(lane, 25, "Advanced P1 unit must expose its lane")

    local p2 = Game.new()
    Game.debugLoadScenario(p2, "empty")
    assertTrue(Game.debugSpawnCard(p2, 2, "iron_golem", 75, 15))
    local p2Golem = findEntity(p2, function(e)
        return e.owner == 2 and e.sourceCardId == "iron_golem"
    end)
    assertTrue(p2Golem ~= nil, "P2 counterpush test needs Iron Golem")
    lane = Bot.debugCounterpushLane(p2, 2)
    assertEq(lane, nil, "P2 backline unit must not count as counterpush")
    p2Golem.y = 60
    lane = Bot.debugCounterpushLane(p2, 2)
    assertEq(lane, 75, "Advanced P2 unit must expose its lane")
end

do
    -- Bot.prepare must never inherit a valid-but-stale human Evolution choice.
    local state = Game.new()
    state.players[2].evolutionCardId = "endermite"
    local deck = {
        "zombie", "cannon", "arrows", "enderman",
        "villager", "endermite", "blaze", "skeleton",
    }
    local bot = Bot.new(2, deck)
    Bot.prepare(bot, state)
    assertEq(
        state.players[2].evolutionCardId,
        "villager",
        "Bot Evolution choice must be derived from its own deck order"
    )
end

do
    -- A ground attacker which can reach a water-only target by range must
    -- navigate to the closest legal bank/bridge point, not walk into water.
    local attacker = {
        x = 50,
        y = 120,
        flying = false,
        waterOnly = false,
    }
    local guardian = {
        x = 50,
        y = (config.ARENA.riverTop + config.ARENA.riverBottom) / 2,
        waterOnly = true,
    }
    local nx, ny = arena.navigationPoint(attacker, guardian)
    assertTrue(
        arena.isWalkable(attacker, nx, ny),
        "Water-target navigation point must be ground-walkable"
    )
    assertNear(
        util.distance(nx, ny, guardian.x, guardian.y),
        arena.distanceToGroundReach(guardian.x, guardian.y),
        0.02,
        "Water-target navigation must stop at minimum reachable distance"
    )
end

do
    -- Scenario loads are deterministic regardless of how many ticks the
    -- previous admin experiment happened to run.
    local state = Game.new()
    state.combatTick = 99
    Game.debugLoadScenario(state, "full")
    assertEq(state.combatTick, 0, "Admin scenario load must reset combat tick")
end

do
    -- A Diamond Golem stomp snapshots its victims. If it kills a Slime, the
    -- newborn Mini Slimes must not be damaged by the same historical pulse.
    local state = Game.new()
    Game.debugLoadScenario(state, "empty")
    assertTrue(Game.debugSpawnCard(state, 1, "evo:iron_golem", 50, 110))
    assertTrue(Game.debugSpawnCard(state, 2, "slime", 50, 103))

    local golem = findEntity(state, function(e)
        return e.owner == 1 and e.name == "Diamond Golem"
    end)
    local slime = findEntity(state, function(e)
        return e.owner == 2 and e.sourceCardId == "slime"
    end)
    assertTrue(golem and slime, "Stomp/split regression needs Golem and Slime")

    golem.groundPulseTimer = 0.01
    slime.hp = 1
    Game.debugSetPaused(state, false)
    Game.update(state, 0.10)

    local miniTemplate = cards.getInternalUnit("mini_slime")
    local minis = {}
    for _, entity in ipairs(state.entities) do
        if entity.alive and entity.owner == 2 and entity.name == "Mini Slime" then
            minis[#minis + 1] = entity
        end
    end

    assertEq(#minis, 2, "Lethal stomp must still split Slime into two minis")
    for _, mini in ipairs(minis) do
        assertNear(
            mini.hp,
            miniTemplate.maxHp,
            1e-9,
            "Newborn Mini Slime must not be hit by the same stomp"
        )
    end
end

do
    -- Terminal AoE telemetry counts only targets actually processed before a
    -- King-Tower result stops further damage.
    local state = Game.new(nil, { headlessSimulation = true })
    state.players[1].deck = cards.defaultDeck()
    state.players[2].deck = cards.defaultDeck()
    assertTrue(Game.startHeadlessBattle(state, config.TICK_RATE))

    local king, princess
    local kingIndex, princessIndex
    for i, entity in ipairs(state.entities) do
        if entity.owner == 2 and entity.kind == "tower" then
            if entity.towerType == "king" then
                king, kingIndex = entity, i
            elseif not princess then
                princess, princessIndex = entity, i
            end
        end
    end
    assertTrue(king and princess, "Terminal AoE telemetry test needs towers")

    state.entities[kingIndex], state.entities[princessIndex]
        = state.entities[princessIndex], state.entities[kingIndex]
    king.x, king.y = 50, 50
    princess.x, princess.y = 50, 50
    king.hp = 1

    state.players[1].emeralds = state.players[1].maxEmeralds
    state.players[1].hand[1] = "arrows"
    assertTrue(Game.playCardFromSlot(state, 1, 1, 50, 50))
    assertEq(state.phase, "result", "Lethal Arrow Volley must end match")
    assertEq(
        state.stats.players[1].cards.arrows.targetsHit,
        1,
        "Terminal AoE must count only the King hit processed before result"
    )
end

do
    -- Negative damage is invalid input, not healing.
    local state = Game.new()
    Game.debugLoadScenario(state, "empty")
    assertTrue(Game.debugSpawnCard(state, 1, "zombie", 50, 100))
    assertTrue(Game.debugSpawnCard(state, 2, "zombie", 50, 102))

    local attacker = findEntity(state, function(e)
        return e.owner == 1 and e.name == "Zombie"
    end)
    local target = findEntity(state, function(e)
        return e.owner == 2 and e.name == "Zombie"
    end)
    assertTrue(attacker and target, "Negative-damage test needs two Zombies")

    attacker.damage = -50
    attacker.attackCooldownLeft = 0
    local hpBefore = target.hp
    Game.debugSetPaused(state, false)
    Game.update(state, 0.10)
    assertEq(target.hp, hpBefore, "Negative damage must never heal a target")
end

do
    -- An aura which expires earlier in the entity traversal must stop slowing
    -- later entities in that same tick.
    local state = Game.new()
    Game.debugLoadScenario(state, "empty")
    assertTrue(Game.debugSpawnCard(state, 1, "villager", 50, 110))
    assertTrue(Game.debugSpawnCard(state, 2, "zombie", 50, 100))

    local source = findEntity(state, function(e)
        return e.owner == 1 and e.sourceCardId == "villager"
    end)
    local enemy = findEntity(state, function(e)
        return e.owner == 2 and e.sourceCardId == "zombie"
    end)
    assertTrue(source and enemy, "Aura expiry regression needs two entities")

    source.globalEnemyMoveSlow = 0.50
    source.remainingLifetime = 0.01
    state.globalMovementAuraDirty = true

    Game.debugSetPaused(state, false)
    Game.update(state, 0.10)

    assertTrue(not source.alive, "Temporary aura source must expire")
    assertNear(
        enemy.globalMoveSpeedFactor,
        1,
        1e-9,
        "Expired aura must be removed before later same-tick movement"
    )
end

do
    -- Periodic ground summons falling into river water use the summoner's
    -- valid position instead of silently disappearing.
    local state = Game.new()
    Game.debugLoadScenario(state, "empty")
    assertTrue(Game.debugSpawnCard(state, 1, "evoker", 50, 87))
    local summoner = findEntity(state, function(e)
        return e.owner == 1 and e.sourceCardId == "evoker"
    end)
    assertTrue(summoner ~= nil, "Periodic-spawn fallback needs Evoker")

    summoner.periodicSpawn = {
        template = "baby_zombie",
        interval = 10,
        initialDelay = 0.01,
        count = 3,
        radius = 4,
        maxAlive = 3,
    }
    summoner.periodicSpawnTimer = 0.01
    Game.debugSetPaused(state, false)
    Game.update(state, 0.02)

    local count = 0
    local usedFallback = false
    for _, entity in ipairs(state.entities) do
        if entity.summonerId == summoner.id then
            count = count + 1
            if math.abs(entity.x - summoner.x) < 1e-9
                and math.abs(entity.y - summoner.y) < 1e-9
            then
                usedFallback = true
            end
        end
    end
    assertEq(count, 3, "All periodic ground summons must spawn")
    assertTrue(usedFallback, "River offset must use summoner fallback")
end

do
    local state = Game.new()
    state.phase = "result"
    local layout = {
        resultButtons = {
            rematch = { x1 = 1, y1 = 1, x2 = 3, y2 = 3 },
            deck = { x1 = 4, y1 = 1, x2 = 6, y2 = 3 },
            exit = { x1 = 7, y1 = 1, x2 = 9, y2 = 3 },
        },
    }
    Game.handleTouch(state, 1, 8, 2, layout)
    assertTrue(state.exitRequested, "EXIT must request outer-loop termination")
    assertEq(state.phase, "result", "EXIT must not masquerade as lobby reset")
end

print("Audit regression tests passed")

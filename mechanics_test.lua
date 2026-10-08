local config = require("config")
local Game = require("src.game")
local cards = require("src.cards")
local Bot = require("src.bot")
local util = require("src.util")
local arena = require("src.arena")

local SUITE_VERSION = 4
local REPORT_FILE = "mechanics_report.txt"
local DEFAULT_DT = 0.05
local EPSILON = 0.000001

local results = {}
local suiteStarted = os.clock()

local function fmt(value)
    if type(value) == "number" then
        return string.format("%.4f", value)
    end
    if type(value) == "boolean" then
        return value and "true" or "false"
    end
    if value == nil then
        return "nil"
    end
    return tostring(value):gsub("[\r\n|]", " ")
end

local function addData(data, key, value)
    data[#data + 1] = tostring(key) .. "=" .. fmt(value)
end

local function distance(a, b)
    return util.distance(a.x, a.y, b.x, b.y)
end

local function findEntity(state, predicate)
    for _, entity in ipairs(state.entities) do
        if predicate(entity) then return entity end
    end
    return nil
end

local function countEntities(state, predicate)
    local count = 0
    for _, entity in ipairs(state.entities) do
        if predicate(entity) then count = count + 1 end
    end
    return count
end

local function step(state, seconds, dt, onTick)
    dt = dt or DEFAULT_DT
    local elapsed = 0

    while elapsed + 1e-9 < seconds do
        local slice = math.min(dt, seconds - elapsed)
        Game.update(state, slice)
        elapsed = elapsed + slice
        if onTick then onTick(state, elapsed) end
    end

    return elapsed
end

local function waitUntil(state, timeout, predicate, dt, onTick)
    dt = dt or DEFAULT_DT
    local elapsed = 0

    if predicate() then return true, elapsed end

    while elapsed + 1e-9 < timeout do
        local slice = math.min(dt, timeout - elapsed)
        Game.update(state, slice)
        elapsed = elapsed + slice
        if onTick then onTick(state, elapsed) end
        if predicate() then return true, elapsed end
    end

    return predicate(), elapsed
end

local function newAdminState(scenario)
    local state = Game.new()
    Game.debugLoadScenario(state, scenario or "empty")
    Game.debugSetPaused(state, false)
    return state
end

-- Pick a roomy ground patch dynamically so diagnostics do not silently become
-- water/bridge tests if arena dimensions or river placement change later.
local function findSafeGroundAnchor()
    local ground = { flying = false }
    local preferredY = math.min(
        config.ARENA.height - 20,
        config.ARENA.riverBottom + 24
    )
    local preferredX = math.floor(config.ARENA.width / 2)

    local offsets = {
        { 0, 0 },
        { -5, 0 }, { 5, 0 },
        { 0, -12 }, { 0, 12 },
        { -5, -5 }, { 5, -5 },
        { -5, 5 }, { 5, 5 },
    }

    local function patchWorks(x, y)
        for _, offset in ipairs(offsets) do
            if not arena.isWalkable(ground, x + offset[1], y + offset[2]) then
                return false
            end
        end
        return true
    end

    if patchWorks(preferredX, preferredY) then
        return preferredX, preferredY
    end

    for y = config.ARENA.riverBottom + 12, config.ARENA.height - 16, 2 do
        for x = 14, config.ARENA.width - 14, 4 do
            if patchWorks(x, y) then return x, y end
        end
    end

    error("Mechanics test could not find a safe walkable ground patch")
end

local SAFE_X, SAFE_Y = findSafeGroundAnchor()

local function runTest(id, title, fn)
    write(("[%-24s] "):format(id))

    local ok, passed, message, data = pcall(fn)
    local status

    if not ok then
        local err = passed
        passed = false
        data = { "error=" .. fmt(err) }
        message = "Lua error while running test"
        status = "ERROR"
    else
        status = passed and "PASS" or "FAIL"
    end

    print(status)

    results[#results + 1] = {
        id = id,
        title = title,
        status = status,
        message = message or "",
        data = data or {},
    }
end

runTest("boot_deck", "Lobby boots with empty human decks", function()
    local state = Game.new()
    local p1Empty = #state.players[1].deck == 0
        and #state.players[1].hand == 0
        and #state.players[1].queue == 0
    local p2Empty = #state.players[2].deck == 0
        and #state.players[2].hand == 0
        and #state.players[2].queue == 0
    local valid = cards.isValidDeck(state.players[1].deck)

    local data = {}
    addData(data, "p1_deck_cards", #state.players[1].deck)
    addData(data, "p2_deck_cards", #state.players[2].deck)
    addData(data, "empty_deck_is_valid", valid)

    return p1Empty and p2Empty and not valid,
        "Human players should build/load/randomize an 8-card deck before READY.",
        data
end)

runTest("evolution_cycle", "Evolution Slot charges twice and evolves third play", function()
    local base = cards.get("zombie")
    local oldEvolution = base.evolution
    base.evolution = {
        cycles = 2,
        name = "Evolved Zombie",
        unit = {
            multipliers = {
                damage = 1.50,
                maxHp = 1.10,
            },
        },
    }

    local data = {}
    local state = Game.new()
    state.players[1].deck = cards.defaultDeck()
    state.players[2].deck = cards.defaultDeck()

    local selected = Game.setEvolutionCard(state, 1, "zombie")
    local rejectedNonEvo = not Game.setEvolutionCard(state, 2, "skeleton")

    Game.startCountdown(state)
    waitUntil(
        state,
        config.MATCH.countdown + 1,
        function() return state.phase == "battle" end,
        0.10
    )

    local normalPlays = true
    local evolvedThird = false
    local progressSequence = {}

    local function newestZombie()
        local newest = nil
        for _, entity in ipairs(state.entities) do
            if entity.owner == 1 and entity.sourceCardId == "zombie" then
                if not newest or entity.id > newest.id then newest = entity end
            end
        end
        return newest
    end

    for playIndex = 1, 3 do
        state.players[1].hand[1] = "zombie"
        state.players[1].emeralds = 10

        local ok = Game.playCardFromSlot(state, 1, 1, SAFE_X - 10 + playIndex * 3, SAFE_Y)
        if not ok then
            base.evolution = oldEvolution
            return false, "Evolution test could not play Zombie " .. tostring(playIndex), data
        end

        local entity = newestZombie()
        progressSequence[#progressSequence + 1] = state.players[1].evolutionProgress or -1

        if playIndex < 3 then
            normalPlays = normalPlays
                and entity ~= nil
                and entity.isEvolution ~= true
                and math.abs((entity.damage or 0) - 80) <= EPSILON
        else
            evolvedThird = entity ~= nil
                and entity.isEvolution == true
                and entity.name == "Evolved Zombie"
                and math.abs((entity.damage or 0) - 120) <= EPSILON
                and state.players[1].evolutionProgress == 0
        end
    end

    local telemetry = state.stats.players[1].evolutionPlays == 1
        and state.stats.players[1].cards.zombie
        and state.stats.players[1].cards.zombie.evolutionPlays == 1

    addData(data, "eligible_selected", selected)
    addData(data, "non_evolution_rejected", rejectedNonEvo)
    addData(data, "progress_after_play_1", progressSequence[1])
    addData(data, "progress_after_play_2", progressSequence[2])
    addData(data, "progress_after_play_3", progressSequence[3])
    addData(data, "first_two_normal", normalPlays)
    addData(data, "third_play_evolved", evolvedThird)
    addData(data, "evolution_telemetry", telemetry)

    base.evolution = oldEvolution

    return selected
        and rejectedNonEvo
        and normalPlays
        and evolvedThird
        and progressSequence[1] == 1
        and progressSequence[2] == 2
        and progressSequence[3] == 0
        and telemetry,
        "Only eligible deck cards may use the Evolution Slot; two normal plays charge it and the third evolves.",
        data
end)

runTest("target_lock", "Pull before attack, lock after attack", function()
    local data = {}

    local pullState = newAdminState("full")
    local pullGolemY = SAFE_Y
    local pullCannonY = math.max(12, config.ARENA.riverTop - 6)
    Game.debugSpawnCard(pullState, 1, "iron_golem", SAFE_X, pullGolemY)
    Game.debugSpawnCard(pullState, 2, "cannon", SAFE_X, pullCannonY)

    local golem = findEntity(pullState, function(e)
        return e.alive and e.owner == 1 and e.name == "Iron Golem"
    end)
    local cannon = findEntity(pullState, function(e)
        return e.alive and e.owner == 2 and e.name == "Cannon"
    end)
    local enemyTower
    for _, entity in ipairs(pullState.entities) do
        if entity.alive and entity.owner == 2 and entity.kind == "tower" then
            if not enemyTower
                or distance(golem, entity) < distance(golem, enemyTower)
            then
                enemyTower = entity
            end
        end
    end

    if not golem or not cannon or not enemyTower then
        return false, "Could not create Golem/Cannon/tower pull scenario.", data
    end

    golem.targetId = enemyTower.id
    local pulledBeforeHit, pullElapsed = waitUntil(
        pullState,
        0.50,
        function() return golem.targetId == cannon.id end,
        DEFAULT_DT
    )
    local stillUnlocked = golem.lockedTargetId == nil
    addData(data, "golem_pulled_before_hit", pulledBeforeHit)
    addData(data, "golem_pull_time_s", pullElapsed)
    addData(data, "golem_locked_before_hit", golem.lockedTargetId ~= nil)

    local lockState = newAdminState("king")
    Game.debugSpawnCard(lockState, 1, "zombie", SAFE_X, SAFE_Y)

    local zombie = findEntity(lockState, function(e)
        return e.alive and e.owner == 1 and e.name == "Zombie"
    end)
    local king = findEntity(lockState, function(e)
        return e.alive and e.owner == 2
            and e.kind == "tower" and e.towerType == "king"
    end)

    if not zombie or not king then
        return false, "Could not create Zombie/King lock scenario.", data
    end

    zombie.x = king.x
    zombie.y = king.y + 2

    local lockedAfterHit, lockElapsed = waitUntil(
        lockState,
        0.50,
        function() return zombie.lockedTargetId == king.id end,
        DEFAULT_DT
    )
    addData(data, "zombie_locked_after_first_hit", lockedAfterHit)
    addData(data, "zombie_lock_time_s", lockElapsed)

    Game.debugSpawnCard(lockState, 2, "endermite", zombie.x + 1, zombie.y)
    step(lockState, 0.30)

    local ignoredNewDistractor = zombie.targetId == king.id
        and zombie.lockedTargetId == king.id
    addData(data, "new_unit_failed_to_steal_aggro", ignoredNewDistractor)

    king.hp = 1
    zombie.attackCooldownLeft = 0
    local releasedAfterDeath, releaseElapsed = waitUntil(
        lockState,
        0.50,
        function() return zombie.lockedTargetId ~= king.id end,
        DEFAULT_DT
    )
    addData(data, "lock_released_after_target_death", releasedAfterDeath)
    addData(data, "lock_release_time_s", releaseElapsed)

    local passed = pulledBeforeHit
        and stillUnlocked
        and lockedAfterHit
        and ignoredNewDistractor
        and releasedAfterDeath

    return passed,
        "Golem must remain pullable before commitment; attacked targets must stay locked until death.",
        data
end)

runTest("building_decay", "Building HP decays continuously", function()
    local state = newAdminState("empty")
    Game.debugSpawnCard(state, 1, "cannon", SAFE_X, SAFE_Y)

    local cannon = findEntity(state, function(e)
        return e.alive and e.owner == 1 and e.name == "Cannon"
    end)
    if not cannon then
        return false, "Cannon did not spawn.", {}
    end

    local data = {}
    local initialHp = cannon.hp
    local lifetime = cannon.lifetime
    local multiplier = (config.BUILDINGS and config.BUILDINGS.lifetimeDecayMultiplier) or 1
    local expectedLife = lifetime / multiplier
    local expectedHp10 = initialHp - (initialHp / lifetime) * multiplier * 10

    step(state, 5.0)
    local hp5 = cannon.hp
    step(state, 5.0)
    local hp10 = cannon.hp
    step(state, 10.0)
    local hp20 = cannon.hp

    local died, extraElapsed = waitUntil(
        state,
        math.max(0, expectedLife - 20) + 1,
        function() return not cannon.alive end,
        DEFAULT_DT
    )
    local measuredDeath = 20 + extraElapsed

    addData(data, "initial_hp", initialHp)
    addData(data, "hp_at_5s", hp5)
    addData(data, "hp_at_10s", hp10)
    addData(data, "hp_at_20s", hp20)
    addData(data, "expected_hp_at_10s", expectedHp10)
    addData(data, "expected_natural_life_s", expectedLife)
    addData(data, "measured_death_time_s", measuredDeath)

    local monotonic = initialHp > hp5 and hp5 > hp10 and hp10 > hp20
    local hpAccurate = math.abs(hp10 - expectedHp10) <= 1.0
    local lifetimeAccurate = died
        and math.abs(measuredDeath - expectedLife) <= DEFAULT_DT * 3.5

    return monotonic and hpAccurate and lifetimeAccurate,
        "Cannon HP should drain smoothly at the configured lifetime multiplier.",
        data
end)

runTest("nether_portal", "Portal spawn cadence and effective lifetime", function()
    local state = newAdminState("empty")
    Game.debugSpawnCard(state, 1, "nether_portal", SAFE_X, SAFE_Y)

    local portal = findEntity(state, function(e)
        return e.alive and e.owner == 1 and e.name == "Nether Portal"
    end)
    if not portal then
        return false, "Nether Portal did not spawn.", {}
    end

    local card = cards.get("nether_portal")
    local spec = card.building.periodicSpawn
    local multiplier = (config.BUILDINGS and config.BUILDINGS.lifetimeDecayMultiplier) or 1
    local effectiveLife = card.building.lifetime / multiplier
    local first = spec.initialDelay or spec.interval
    local interval = spec.interval
    local expectedSpawns = 0

    if first < effectiveLife then
        expectedSpawns = 1 + math.floor(
            math.max(0, effectiveLife - first - 0.000001) / interval
        )
    end

    local seen = {}
    local spawnTimes = {}
    local elapsed = 0

    while elapsed < effectiveLife + 1 and portal.alive do
        local slice = math.min(DEFAULT_DT, effectiveLife + 1 - elapsed)
        Game.update(state, slice)
        elapsed = elapsed + slice

        for _, entity in ipairs(state.entities) do
            if entity.owner == 1 and entity.name == "Piglin" and not seen[entity.id] then
                seen[entity.id] = true
                spawnTimes[#spawnTimes + 1] = elapsed
            end
        end
    end

    local timingOk = #spawnTimes == expectedSpawns
    local timingTolerance = math.max(DEFAULT_DT * 3, 0.15)

    for i, observed in ipairs(spawnTimes) do
        local expected = first + (i - 1) * interval
        if math.abs(observed - expected) > timingTolerance then
            timingOk = false
        end
    end

    local data = {}
    addData(data, "test_anchor_x", SAFE_X)
    addData(data, "test_anchor_y", SAFE_Y)
    addData(data, "expected_effective_life_s", effectiveLife)
    addData(data, "measured_portal_death_s", elapsed)
    addData(data, "portal_alive_after_window", portal.alive)
    addData(data, "expected_piglins", expectedSpawns)
    addData(data, "observed_piglins", #spawnTimes)
    for i, t in ipairs(spawnTimes) do
        addData(data, "piglin_" .. tostring(i) .. "_spawn_s", t)
    end

    return timingOk
        and not portal.alive
        and math.abs(elapsed - effectiveLife) <= DEFAULT_DT * 3.5,
        "Portal should produce the scheduled Piglins on walkable ground and die from natural HP decay.",
        data
end)

runTest("magma_split", "Magma Cube splits into exactly two minis", function()
    local state = newAdminState("empty")
    Game.debugSpawnCard(state, 1, "magma_cube", SAFE_X, SAFE_Y)
    Game.debugSpawnCard(state, 2, "zombie", SAFE_X, SAFE_Y)

    local magma = findEntity(state, function(e)
        return e.alive and e.owner == 1 and e.name == "Magma Cube"
    end)
    local zombie = findEntity(state, function(e)
        return e.alive and e.owner == 2 and e.name == "Zombie"
    end)
    if not magma or not zombie then
        return false, "Could not create Magma Cube split scenario.", {}
    end

    magma.hp = 1
    magma.moveSpeed = 0
    magma.attackCooldownLeft = 999
    magma.targetId = zombie.id

    zombie.moveSpeed = 0
    zombie.damage = magma.maxHp + 100
    zombie.attackCooldownLeft = 0
    zombie.targetId = magma.id

    local parentDied, deathElapsed = waitUntil(
        state,
        0.75,
        function() return not magma.alive end,
        DEFAULT_DT
    )

    local splitAppeared, splitElapsed = waitUntil(
        state,
        0.25,
        function()
            return countEntities(state, function(e)
                return e.alive and e.owner == 1 and e.name == "Mini Magma Cube"
            end) == 2
        end,
        DEFAULT_DT
    )

    local minis = countEntities(state, function(e)
        return e.alive and e.owner == 1 and e.name == "Mini Magma Cube"
    end)

    local data = {}
    addData(data, "parent_died", parentDied)
    addData(data, "parent_death_time_s", deathElapsed)
    addData(data, "split_detected", splitAppeared)
    addData(data, "split_detection_extra_s", splitElapsed)
    addData(data, "mini_magma_cubes", minis)

    return parentDied and splitAppeared and minis == 2,
        "A lethal real combat hit on Magma Cube should create exactly two Mini Magma Cubes.",
        data
end)

runTest("anvil_aoe", "Falling Anvil delay and air+ground AoE", function()
    local state = newAdminState("empty")
    local anvil = cards.get("falling_anvil")
    local delay = anvil.spell.delay

    Game.debugSpawnCard(state, 2, "zombie", SAFE_X, SAFE_Y)
    Game.debugSpawnCard(state, 2, "bat_swarm", SAFE_X, SAFE_Y)
    Game.debugSpawnCard(state, 1, "falling_anvil", SAFE_X, SAFE_Y)

    local targetPredicate = function(e)
        return e.alive and e.owner == 2 and e.kind == "unit"
    end

    local before = countEntities(state, targetPredicate)
    local preImpactTime = math.max(0, delay - DEFAULT_DT * 3)
    step(state, preImpactTime)
    local beforeImpact = countEntities(state, targetPredicate)

    local impacted, afterWait = waitUntil(
        state,
        DEFAULT_DT * 8,
        function() return countEntities(state, targetPredicate) == 0 end,
        DEFAULT_DT
    )
    local afterImpact = countEntities(state, targetPredicate)
    local measuredImpactTime = preImpactTime + afterWait

    local data = {}
    addData(data, "configured_delay_s", delay)
    addData(data, "targets_initial", before)
    addData(data, "targets_alive_before_impact", beforeImpact)
    addData(data, "targets_alive_after_impact", afterImpact)
    addData(data, "measured_impact_time_s", measuredImpactTime)

    return before == 4
        and beforeImpact == 4
        and impacted
        and afterImpact == 0
        and measuredImpactTime + DEFAULT_DT >= delay,
        "Anvil must respect its warning delay, then hit the clustered ground unit and all three flying Bats.",
        data
end)

runTest("creeper_fuse", "Creeper fuse delay, lock and explosion", function()
    local state = newAdminState("empty")
    Game.debugSpawnCard(state, 1, "creeper", SAFE_X, SAFE_Y)
    Game.debugSpawnCard(state, 2, "zombie", SAFE_X + 3, SAFE_Y)

    local creeper = findEntity(state, function(e)
        return e.alive and e.owner == 1 and e.name == "Creeper"
    end)
    local zombie = findEntity(state, function(e)
        return e.alive and e.owner == 2 and e.name == "Zombie"
    end)
    if not creeper or not zombie then
        return false, "Could not create Creeper fuse scenario.", {}
    end

    zombie.attackCooldownLeft = 999
    zombie.moveSpeed = 0
    local zombieStartHp = zombie.hp
    local spec = cards.get("creeper").unit.proximityExplosion

    local fuseStarted, armElapsed = waitUntil(
        state,
        0.50,
        function() return creeper.fuseRemaining ~= nil end,
        DEFAULT_DT
    )
    local locked = creeper.lockedTargetId == zombie.id

    local safeFuseWindow = math.max(0, spec.fuseTime - DEFAULT_DT * 2)
    step(state, safeFuseWindow)
    local aliveBeforeFuse = creeper.alive

    local exploded, explosionWait = waitUntil(
        state,
        DEFAULT_DT * 6,
        function() return not creeper.alive end,
        DEFAULT_DT
    )
    local damage = zombieStartHp - zombie.hp

    local data = {}
    addData(data, "fuse_started", fuseStarted)
    addData(data, "arm_time_s", armElapsed)
    addData(data, "locked_target_on_fuse", locked)
    addData(data, "alive_before_fuse_finished", aliveBeforeFuse)
    addData(data, "exploded", exploded)
    addData(data, "explosion_wait_after_safe_window_s", explosionWait)
    addData(data, "zombie_damage_taken", damage)
    addData(data, "expected_explosion_damage", spec.damage)

    return fuseStarted
        and locked
        and aliveBeforeFuse
        and exploded
        and math.abs(damage - spec.damage) <= EPSILON,
        "Creeper should arm and lock, survive until the fuse window ends, then explode for configured damage.",
        data
end)

runTest("skeleton_kite", "Skeleton attacks while backing away", function()
    local state = newAdminState("empty")
    Game.debugSpawnCard(state, 1, "skeleton", SAFE_X, SAFE_Y)
    Game.debugSpawnCard(state, 2, "zombie", SAFE_X, SAFE_Y + 4)

    local skeleton = findEntity(state, function(e)
        return e.alive and e.owner == 1 and e.name == "Skeleton"
    end)
    local zombie = findEntity(state, function(e)
        return e.alive and e.owner == 2 and e.name == "Zombie"
    end)
    if not skeleton or not zombie then
        return false, "Could not create Skeleton kiting scenario.", {}
    end

    zombie.moveSpeed = 0
    zombie.attackCooldownLeft = 999

    local startDistance = distance(skeleton, zombie)
    local startHp = zombie.hp

    local behaviorSeen, elapsed = waitUntil(
        state,
        1.25,
        function()
            local damage = startHp - zombie.hp
            local retreat = distance(skeleton, zombie) - startDistance
            return damage >= (skeleton.damage or 0) - EPSILON
                and retreat >= 0.50
        end,
        DEFAULT_DT
    )

    local endDistance = distance(skeleton, zombie)
    local damage = startHp - zombie.hp

    local data = {}
    addData(data, "behavior_detected", behaviorSeen)
    addData(data, "detection_time_s", elapsed)
    addData(data, "distance_before", startDistance)
    addData(data, "distance_after", endDistance)
    addData(data, "retreat_distance", endDistance - startDistance)
    addData(data, "zombie_damage_taken", damage)
    addData(data, "attack_range", skeleton.attackRange)
    addData(data, "preferred_min_range", skeleton.preferredMinRange)
    addData(data, "retreat_speed_multiplier", skeleton.retreatSpeedMultiplier)

    return behaviorSeen,
        "Skeleton should land a ranged hit and measurably create distance while the enemy is inside kite range.",
        data
end)

runTest("outpost_anti_air", "Pillager Outpost attacks flying units", function()
    local state = newAdminState("empty")
    Game.debugSpawnCard(state, 1, "pillager_outpost", SAFE_X, SAFE_Y)
    Game.debugSpawnCard(state, 2, "bat_swarm", SAFE_X, SAFE_Y - 10)

    local batPredicate = function(e)
        return e.alive and e.owner == 2 and e.name == "Bat Swarm"
    end

    local batsBefore = countEntities(state, batPredicate)

    for _, entity in ipairs(state.entities) do
        if entity.owner == 2 and entity.name == "Bat Swarm" then
            entity.moveSpeed = 0
            entity.attackCooldownLeft = 999
        end
    end

    local hitAir, elapsed = waitUntil(
        state,
        3.0,
        function() return countEntities(state, batPredicate) < batsBefore end,
        DEFAULT_DT
    )
    local batsAfter = countEntities(state, batPredicate)

    local data = {}
    addData(data, "bats_before", batsBefore)
    addData(data, "bats_after_first_kill", batsAfter)
    addData(data, "first_air_kill_time_s", elapsed)
    addData(data, "can_attack_air", cards.get("pillager_outpost").building.canAttackAir)

    return batsBefore == 3 and hitAir and batsAfter < batsBefore,
        "Outpost should acquire stationary airborne Bats and kill at least one via its projectile attack.",
        data
end)

runTest("match_flow", "Regulation, overtime multipliers and tiebreaker", function()
    local state = Game.new()
    state.players[1].deck = cards.defaultDeck()
    state.players[2].deck = cards.defaultDeck()

    Game.startCountdown(state)
    local enteredBattle, countdownElapsed = waitUntil(
        state,
        config.MATCH.countdown + 1,
        function() return state.phase == "battle" end,
        0.10
    )

    local towers = countEntities(state, function(e)
        return e.alive and e.kind == "tower"
    end)

    -- Jump close to the regulation boundary. This tests the real transition
    -- without spending hundreds of diagnostic ticks doing nothing.
    state.timeLeft = 0.25
    Game.update(state, 0.25)
    local enteredOvertime = state.phase == "battle" and state.overtime

    state.timeLeft = 60
    state.players[1].emeralds = 0
    step(state, 2.8, 0.05)
    local overtimeEmeralds = state.players[1].emeralds

    state.timeLeft = config.MATCH.overtimeFinalSeconds
    state.players[1].emeralds = 0
    step(state, 2.8, 0.05)
    local final30Emeralds = state.players[1].emeralds

    state.timeLeft = 0.25
    Game.update(state, 0.25)
    local enteredTiebreaker = state.phase == "battle" and state.tiebreaker

    local sampleTower = findEntity(state, function(e)
        return e.alive and e.kind == "tower" and e.towerType == "princess"
    end)
    local beforeDrain = sampleTower and sampleTower.hp or 0

    step(state, 1.0, 0.25)
    local afterDrain = sampleTower and sampleTower.hp or 0
    local drained = beforeDrain - afterDrain

    local data = {}
    addData(data, "countdown_to_battle_s", countdownElapsed)
    addData(data, "entered_battle", enteredBattle)
    addData(data, "tower_count", towers)
    addData(data, "entered_overtime", enteredOvertime)
    addData(data, "emeralds_after_2_8s_at_2x", overtimeEmeralds)
    addData(data, "emeralds_after_2_8s_at_3x", final30Emeralds)
    addData(data, "entered_tiebreaker", enteredTiebreaker)
    addData(data, "tower_hp_drain_in_1s", drained)
    addData(data, "expected_tiebreaker_drain", config.MATCH.tiebreakerDamagePerSecond)

    local multiplierOk = math.abs(overtimeEmeralds - 2.0) <= 0.02
        and math.abs(final30Emeralds - 3.0) <= 0.02
    local drainOk = math.abs(drained - config.MATCH.tiebreakerDamagePerSecond) <= 0.01

    return enteredBattle
        and towers == 6
        and enteredOvertime
        and multiplierOk
        and enteredTiebreaker
        and drainOk,
        "Real phase transitions must produce 2x/3x Emerald generation and the configured equal-HP Tiebreaker drain.",
        data
end)

runTest("bot_smoke", "Normal bot can play through the real card API", function()
    local state = Game.new()
    state.gameMode = "bot"
    state.botPlayerId = 2
    state.players[1].deck = cards.defaultDeck()

    local bot = Bot.new(2)
    Bot.prepare(bot, state)
    Game.startCountdown(state)

    local enteredBattle = false
    local countdownElapsed = 0
    while countdownElapsed < config.MATCH.countdown + 1 do
        Game.update(state, 0.10)
        countdownElapsed = countdownElapsed + 0.10
        if state.phase == "battle" then
            enteredBattle = true
            break
        end
    end

    if not enteredBattle then
        return false, "Bot smoke test never entered battle.", {}
    end

    Bot.beginMatch(bot)
    bot.enabled = true

    local elapsed = 0
    while elapsed < 30 and state.phase == "battle" and bot.actions < 3 do
        Game.update(state, 0.10)
        Bot.update(bot, state, 0.10)
        elapsed = elapsed + 0.10
    end

    local stats = Game.getMatchStats(state, 2)
    local data = {}
    addData(data, "simulated_seconds", elapsed)
    addData(data, "bot_actions", bot.actions)
    addData(data, "bot_last_action", bot.lastAction)
    addData(data, "recorded_cards_played", stats and stats.cardsPlayed or -1)
    addData(data, "bot_emeralds", state.players[2].emeralds)

    return bot.actions > 0
        and stats ~= nil
        and stats.cardsPlayed == bot.actions,
        "Bot should spend real Emeralds and register every successful play in normal match telemetry.",
        data
end)

local passCount = 0
local failCount = 0
local errorCount = 0
for _, result in ipairs(results) do
    if result.status == "PASS" then
        passCount = passCount + 1
    elseif result.status == "ERROR" then
        errorCount = errorCount + 1
    else
        failCount = failCount + 1
    end
end

local skeleton = cards.get("skeleton")
local bats = cards.get("bat_swarm")

local report = {}
report[#report + 1] = "CC-MINECRAFT-ROYALE MECHANICS REPORT"
report[#report + 1] = "FORMAT_VERSION|" .. tostring(SUITE_VERSION)
report[#report + 1] = "GENERATED_EPOCH_MS|" .. tostring(os.epoch and os.epoch("utc") or "unavailable")
report[#report + 1] = "OS_VERSION|" .. fmt(os.version and os.version() or "unknown")
report[#report + 1] = "CARD_COUNT|" .. tostring(#cards.list)
report[#report + 1] = string.format(
    "HARNESS|condition_waits=true|dt=%.3f|safe_x=%.1f|safe_y=%.1f",
    DEFAULT_DT,
    SAFE_X,
    SAFE_Y
)
report[#report + 1] = string.format(
    "CONFIG|tick=%.3f|normal=%s|overtime=%s|emerald_rate=%.6f|building_decay=%.3f",
    config.TICK_RATE,
    tostring(config.MATCH.normalTime),
    tostring(config.MATCH.overtimeTime),
    config.MATCH.emeraldPerSecond,
    (config.BUILDINGS and config.BUILDINGS.lifetimeDecayMultiplier) or 1
)
report[#report + 1] = string.format(
    "BALANCE_SNAPSHOT|skeleton_range=%.2f|skeleton_retreat=%.2f|bat_damage=%.2f",
    skeleton.unit.attackRange,
    skeleton.unit.retreatSpeedMultiplier,
    bats.unit.damage
)
report[#report + 1] = string.format(
    "SUMMARY|pass=%d|fail=%d|error=%d|total=%d|runtime_cpu_s=%.4f",
    passCount,
    failCount,
    errorCount,
    #results,
    os.clock() - suiteStarted
)

for _, result in ipairs(results) do
    report[#report + 1] = ""
    report[#report + 1] = table.concat({
        "RESULT",
        result.id,
        result.status,
        result.title,
        result.message,
    }, "|")

    for _, datum in ipairs(result.data) do
        report[#report + 1] = "DATA|" .. result.id .. "|" .. datum
    end
end

report[#report + 1] = ""
report[#report + 1] = "END_OF_REPORT"

local reportText = table.concat(report, "\n") .. "\n"
local handle = fs.open(REPORT_FILE, "w")
if not handle then
    error("Could not write " .. REPORT_FILE, 0)
end
handle.write(reportText)
handle.close()

print("")
print(("Mechanics tests complete: %d PASS / %d FAIL / %d ERROR"):format(
    passCount,
    failCount,
    errorCount
))
print("Report written to: " .. REPORT_FILE)

local syncLoaded, ReportSync = pcall(require, "src.report_sync")
if syncLoaded and ReportSync.isConfigured() then
    print("Syncing mechanics report to GitHub...")
    local synced, syncResult = ReportSync.autoUpload("mechanics", REPORT_FILE)
    if synced then
        print("GitHub sync OK: " .. syncResult.latestPath)
    else
        print("GitHub sync FAILED: " .. tostring(syncResult))
        print("Local report is still safe at: " .. REPORT_FILE)
    end
elseif syncLoaded then
    print("GitHub auto-sync not configured. Run once: report_sync setup")
else
    print("GitHub auto-sync unavailable: " .. tostring(ReportSync))
end

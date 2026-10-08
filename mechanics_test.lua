local config = require("config")
local Game = require("src.game")
local cards = require("src.cards")
local Bot = require("src.bot")
local util = require("src.util")

local SUITE_VERSION = 1
local REPORT_FILE = "mechanics_report.txt"
local DEFAULT_DT = 0.05

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

local function newAdminState(scenario)
    local state = Game.new()
    Game.debugLoadScenario(state, scenario or "empty")
    Game.debugSetPaused(state, false)
    return state
end

local function runTest(id, title, fn)
    write(("[%-24s] "):format(id))

    local ok, passed, message, data = pcall(fn)
    if not ok then
        local err = passed
        passed = false
        data = { "error=" .. fmt(err) }
        message = "Lua error while running test"
    end

    local status = passed and "PASS" or "FAIL"
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

runTest("target_lock", "Pull before attack, lock after attack", function()
    local data = {}

    local pullState = newAdminState("full")
    Game.debugSpawnCard(pullState, 1, "iron_golem", 50, 105)
    Game.debugSpawnCard(pullState, 2, "cannon", 50, 68)

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
                or math.abs(entity.x - 50) < math.abs(enemyTower.x - 50)
            then
                enemyTower = entity
            end
        end
    end

    if not golem or not cannon or not enemyTower then
        return false, "Could not create Golem/Cannon/tower pull scenario.", data
    end

    golem.targetId = enemyTower.id
    Game.update(pullState, 0.10)

    local pulledBeforeHit = golem.targetId == cannon.id
    local stillUnlocked = golem.lockedTargetId == nil
    addData(data, "golem_pulled_before_hit", pulledBeforeHit)
    addData(data, "golem_locked_before_hit", golem.lockedTargetId ~= nil)

    local lockState = newAdminState("king")
    Game.debugSpawnCard(lockState, 1, "zombie", 50, 100)

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
    Game.update(lockState, 0.10)

    local lockedAfterHit = zombie.lockedTargetId == king.id
    addData(data, "zombie_locked_after_first_hit", lockedAfterHit)

    Game.debugSpawnCard(lockState, 2, "endermite", zombie.x + 1, zombie.y)
    Game.update(lockState, 0.10)

    local ignoredNewDistractor = zombie.targetId == king.id
        and zombie.lockedTargetId == king.id
    addData(data, "new_unit_failed_to_steal_aggro", ignoredNewDistractor)

    king.hp = 1
    zombie.attackCooldownLeft = 0
    Game.update(lockState, 0.10)
    Game.update(lockState, 0.10)

    local releasedAfterDeath = zombie.lockedTargetId ~= king.id
    addData(data, "lock_released_after_target_death", releasedAfterDeath)

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
    Game.debugSpawnCard(state, 1, "cannon", 50, 80)

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

    local elapsed = 20.0
    while cannon.alive and elapsed < expectedLife + 2 do
        Game.update(state, DEFAULT_DT)
        elapsed = elapsed + DEFAULT_DT
    end

    addData(data, "initial_hp", initialHp)
    addData(data, "hp_at_5s", hp5)
    addData(data, "hp_at_10s", hp10)
    addData(data, "hp_at_20s", hp20)
    addData(data, "expected_hp_at_10s", expectedHp10)
    addData(data, "expected_natural_life_s", expectedLife)
    addData(data, "measured_death_time_s", elapsed)

    local monotonic = initialHp > hp5 and hp5 > hp10 and hp10 > hp20
    local hpAccurate = math.abs(hp10 - expectedHp10) <= 1.0
    local lifetimeAccurate = not cannon.alive
        and math.abs(elapsed - expectedLife) <= DEFAULT_DT * 2.5

    return monotonic and hpAccurate and lifetimeAccurate,
        "Cannon HP should drain smoothly at the configured lifetime multiplier.",
        data
end)

runTest("nether_portal", "Portal spawn cadence and effective lifetime", function()
    local state = newAdminState("empty")
    Game.debugSpawnCard(state, 1, "nether_portal", 50, 80)

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

    while elapsed < effectiveLife + 0.5 do
        Game.update(state, DEFAULT_DT)
        elapsed = elapsed + DEFAULT_DT

        for _, entity in ipairs(state.entities) do
            if entity.owner == 1 and entity.name == "Piglin" and not seen[entity.id] then
                seen[entity.id] = true
                spawnTimes[#spawnTimes + 1] = elapsed
            end
        end
    end

    local timingOk = #spawnTimes == expectedSpawns
    for i, observed in ipairs(spawnTimes) do
        local expected = first + (i - 1) * interval
        if math.abs(observed - expected) > DEFAULT_DT * 2.5 then
            timingOk = false
        end
    end

    local data = {}
    addData(data, "expected_effective_life_s", effectiveLife)
    addData(data, "portal_alive_after_window", portal.alive)
    addData(data, "expected_piglins", expectedSpawns)
    addData(data, "observed_piglins", #spawnTimes)
    for i, t in ipairs(spawnTimes) do
        addData(data, "piglin_" .. tostring(i) .. "_spawn_s", t)
    end

    return timingOk and not portal.alive,
        "Portal should naturally decay before a fourth scheduled Piglin.",
        data
end)

runTest("magma_split", "Magma Cube splits into exactly two minis", function()
    local state = newAdminState("empty")
    Game.debugSpawnCard(state, 1, "magma_cube", 50, 80)
    Game.debugSpawnCard(state, 2, "zombie", 50, 80)

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
    magma.attackCooldownLeft = 999
    zombie.attackCooldownLeft = 0

    Game.update(state, 0.10)

    local minis = countEntities(state, function(e)
        return e.alive and e.owner == 1 and e.name == "Mini Magma Cube"
    end)

    local data = {}
    addData(data, "parent_alive_after_lethal_hit", magma.alive)
    addData(data, "mini_magma_cubes", minis)

    return not magma.alive and minis == 2,
        "A lethal hit on Magma Cube should create two Mini Magma Cubes in the same combat tick.",
        data
end)

runTest("anvil_aoe", "Falling Anvil delay and air+ground AoE", function()
    local state = newAdminState("empty")
    Game.debugSpawnCard(state, 2, "zombie", 50, 80)
    Game.debugSpawnCard(state, 2, "bat_swarm", 50, 80)
    Game.debugSpawnCard(state, 1, "falling_anvil", 50, 80)

    local before = countEntities(state, function(e)
        return e.alive and e.owner == 2 and e.kind == "unit"
    end)

    step(state, 2.60)
    local beforeImpact = countEntities(state, function(e)
        return e.alive and e.owner == 2 and e.kind == "unit"
    end)

    step(state, 0.15)
    local afterImpact = countEntities(state, function(e)
        return e.alive and e.owner == 2 and e.kind == "unit"
    end)

    local data = {}
    addData(data, "targets_initial", before)
    addData(data, "targets_alive_at_2_60s", beforeImpact)
    addData(data, "targets_alive_after_2_75s", afterImpact)

    return before == 4 and beforeImpact == 4 and afterImpact == 0,
        "Anvil should not hit early, then should hit the clustered Zombie and all three flying Bats.",
        data
end)

runTest("creeper_fuse", "Creeper fuse delay, lock and explosion", function()
    local state = newAdminState("empty")
    Game.debugSpawnCard(state, 1, "creeper", 50, 80)
    Game.debugSpawnCard(state, 2, "zombie", 53, 80)

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

    Game.update(state, DEFAULT_DT)
    local fuseStarted = creeper.fuseRemaining ~= nil
    local locked = creeper.lockedTargetId == zombie.id

    step(state, 0.50)
    local aliveBeforeFuse = creeper.alive

    step(state, 0.20)
    local damage = zombieStartHp - zombie.hp

    local data = {}
    addData(data, "fuse_started", fuseStarted)
    addData(data, "locked_target_on_fuse", locked)
    addData(data, "alive_before_fuse_finished", aliveBeforeFuse)
    addData(data, "creeper_alive_after_explosion", creeper.alive)
    addData(data, "zombie_damage_taken", damage)
    addData(data, "expected_explosion_damage", cards.get("creeper").unit.proximityExplosion.damage)

    local expectedDamage = cards.get("creeper").unit.proximityExplosion.damage
    return fuseStarted
        and locked
        and aliveBeforeFuse
        and not creeper.alive
        and math.abs(damage - expectedDamage) <= 0.001,
        "Creeper should arm, remain alive during the fuse, then explode for its configured damage.",
        data
end)

runTest("skeleton_kite", "Skeleton attacks while backing away", function()
    local state = newAdminState("empty")
    Game.debugSpawnCard(state, 1, "skeleton", 50, 80)
    Game.debugSpawnCard(state, 2, "zombie", 50, 84)

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
    step(state, 0.60)
    local endDistance = distance(skeleton, zombie)
    local damage = startHp - zombie.hp

    local data = {}
    addData(data, "distance_before", startDistance)
    addData(data, "distance_after_0_60s", endDistance)
    addData(data, "zombie_damage_taken", damage)
    addData(data, "preferred_min_range", skeleton.preferredMinRange)

    return endDistance > startDistance + 1
        and damage >= (skeleton.damage or 0),
        "Skeleton should fire once and create distance when an enemy is inside its preferred minimum range.",
        data
end)

runTest("outpost_anti_air", "Pillager Outpost attacks flying units", function()
    local state = newAdminState("empty")
    Game.debugSpawnCard(state, 1, "pillager_outpost", 50, 80)
    Game.debugSpawnCard(state, 2, "bat_swarm", 50, 70)

    local batsBefore = countEntities(state, function(e)
        return e.alive and e.owner == 2 and e.name == "Bat Swarm"
    end)

    for _, entity in ipairs(state.entities) do
        if entity.owner == 2 and entity.name == "Bat Swarm" then
            entity.moveSpeed = 0
            entity.attackCooldownLeft = 999
        end
    end

    step(state, 2.50)

    local batsAfter = countEntities(state, function(e)
        return e.alive and e.owner == 2 and e.name == "Bat Swarm"
    end)

    local data = {}
    addData(data, "bats_before", batsBefore)
    addData(data, "bats_after_2_50s", batsAfter)
    addData(data, "bats_killed", batsBefore - batsAfter)

    return batsBefore == 3 and batsAfter < batsBefore,
        "Outpost should acquire airborne Bats and kill at least one with crossbow projectiles.",
        data
end)

runTest("match_flow", "Regulation, overtime multipliers and tiebreaker", function()
    local state = Game.new()
    state.players[1].deck = cards.defaultDeck()
    state.players[2].deck = cards.defaultDeck()

    Game.startCountdown(state)
    step(state, config.MATCH.countdown, 0.25)

    local enteredBattle = state.phase == "battle"
    local towers = countEntities(state, function(e)
        return e.alive and e.kind == "tower"
    end)

    step(state, config.MATCH.normalTime, 0.25)
    local enteredOvertime = state.phase == "battle" and state.overtime

    state.players[1].emeralds = 0
    step(state, 2.8, 0.05)
    local overtimeEmeralds = state.players[1].emeralds

    local toFinal30 = math.max(0, state.timeLeft - config.MATCH.overtimeFinalSeconds)
    step(state, toFinal30, 0.25)

    state.players[1].emeralds = 0
    step(state, 2.8, 0.05)
    local final30Emeralds = state.players[1].emeralds

    if state.timeLeft > 0 then
        step(state, state.timeLeft, 0.25)
    end

    local enteredTiebreaker = state.phase == "battle" and state.tiebreaker
    local sampleTower = findEntity(state, function(e)
        return e.alive and e.kind == "tower" and e.towerType == "princess"
    end)
    local beforeDrain = sampleTower and sampleTower.hp or 0

    step(state, 1.0, 0.25)
    local afterDrain = sampleTower and sampleTower.hp or 0
    local drained = beforeDrain - afterDrain

    local data = {}
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
        "A no-damage match should reach OT, use 2x/3x Emerald generation, then start equal-HP Tiebreaker drain.",
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
    step(state, config.MATCH.countdown, 0.25)

    Bot.beginMatch(bot)
    bot.enabled = true

    local elapsed = 0
    while elapsed < 30 and state.phase == "battle" do
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
        "Bot should spend real Emeralds and register its plays in normal match telemetry.",
        data
end)

local passCount = 0
local failCount = 0
for _, result in ipairs(results) do
    if result.status == "PASS" then
        passCount = passCount + 1
    else
        failCount = failCount + 1
    end
end

local report = {}
report[#report + 1] = "CC-MINECRAFT-ROYALE MECHANICS REPORT"
report[#report + 1] = "FORMAT_VERSION|" .. tostring(SUITE_VERSION)
report[#report + 1] = "GENERATED_EPOCH_MS|" .. tostring(os.epoch and os.epoch("utc") or "unavailable")
report[#report + 1] = "OS_VERSION|" .. fmt(os.version and os.version() or "unknown")
report[#report + 1] = "CARD_COUNT|" .. tostring(#cards.list)
report[#report + 1] = string.format(
    "CONFIG|tick=%.3f|normal=%s|overtime=%s|emerald_rate=%.6f|building_decay=%.3f",
    config.TICK_RATE,
    tostring(config.MATCH.normalTime),
    tostring(config.MATCH.overtimeTime),
    config.MATCH.emeraldPerSecond,
    (config.BUILDINGS and config.BUILDINGS.lifetimeDecayMultiplier) or 1
)
report[#report + 1] = string.format(
    "SUMMARY|pass=%d|fail=%d|total=%d|runtime_cpu_s=%.4f",
    passCount,
    failCount,
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
print(("Mechanics tests complete: %d PASS / %d FAIL"):format(passCount, failCount))
print("Report written to: " .. REPORT_FILE)
print("Send me the entire file contents and I can analyze the failures/metrics.")

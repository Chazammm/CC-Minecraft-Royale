local config = require("config")
local Game = require("src.game")
local cards = require("src.cards")
local Bot = require("src.bot")
local util = require("src.util")
local arena = require("src.arena")

local SUITE_VERSION = 19
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

runTest("evolution_cycle", "Evolution timing, cost, stats and abilities", function()
    local base = cards.get("zombie")
    local oldEvolution = base.evolution
    base.evolution = {
        cycles = 3,
        cost = { delta = 1 },
        name = "Evolved Zombie",
        statMultipliers = {
            damage = 1.50,
            maxHp = 1.10,
        },
        abilities = {
            canAttackAir = true,
            onHitSlow = {
                factor = 0.75,
                duration = 2.0,
            },
        },
    }

    local function restore()
        base.evolution = oldEvolution
    end

    local data = {}
    local state = Game.new()
    state.players[1].deck = cards.defaultDeck()
    state.players[2].deck = cards.defaultDeck()

    local selected = Game.setEvolutionCard(state, 1, "zombie")
    local rejectedNonEvo = not Game.setEvolutionCard(state, 2, "skeleton")
    local configuredCycles = cards.evolutionCycles("zombie")
    local configuredEvoCost = cards.evolutionCost("zombie")

    Game.startCountdown(state)
    local enteredBattle = waitUntil(
        state,
        config.MATCH.countdown + 1,
        function() return state.phase == "battle" end,
        0.10
    )

    if not enteredBattle then
        restore()
        return false, "Evolution test never entered battle.", data
    end

    local normalPlays = true
    local evolvedFourth = false
    local abilitiesApplied = false
    local progressSequence = {}
    local normalCostOk = true

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

        local ok = Game.playCardFromSlot(
            state,
            1,
            1,
            SAFE_X - 12 + playIndex * 4,
            SAFE_Y
        )

        if not ok then
            restore()
            return false, "Evolution test could not play normal Zombie " .. tostring(playIndex), data
        end

        local entity = newestZombie()
        progressSequence[#progressSequence + 1] = state.players[1].evolutionProgress or -1
        normalCostOk = normalCostOk and math.abs(state.players[1].emeralds - 7) <= EPSILON

        normalPlays = normalPlays
            and entity ~= nil
            and entity.isEvolution ~= true
            and math.abs((entity.damage or 0) - 80) <= EPSILON
    end

    -- Evolution is ready here and costs 4E. A 3E attempt must fail without
    -- consuming charge or Emeralds.
    state.players[1].hand[1] = "zombie"
    state.players[1].emeralds = 3
    local rejectedForCost = not Game.playCardFromSlot(
        state,
        1,
        1,
        SAFE_X,
        SAFE_Y
    )
    local preservedReadyCharge = state.players[1].evolutionProgress == 3
        and math.abs(state.players[1].emeralds - 3) <= EPSILON

    state.players[1].hand[1] = "zombie"
    state.players[1].emeralds = 10
    local evolvedOk = Game.playCardFromSlot(
        state,
        1,
        1,
        SAFE_X + 10,
        SAFE_Y
    )
    local evolved = newestZombie()
    progressSequence[#progressSequence + 1] = state.players[1].evolutionProgress or -1

    if evolvedOk and evolved then
        evolvedFourth = evolved.isEvolution == true
            and evolved.name == "Evolved Zombie"
            and math.abs((evolved.damage or 0) - 120) <= EPSILON
            and math.abs((evolved.maxHp or 0) - 575.3) <= EPSILON
            and math.abs(state.players[1].emeralds - 6) <= EPSILON
            and state.players[1].evolutionProgress == 0

        abilitiesApplied = evolved.canAttackAir == true
            and evolved.onHitSlow ~= nil
            and math.abs((evolved.onHitSlow.factor or 0) - 0.75) <= EPSILON
            and math.abs((evolved.onHitSlow.duration or 0) - 2.0) <= EPSILON
    end

    local telemetry = state.stats.players[1].evolutionPlays == 1
        and state.stats.players[1].cards.zombie
        and state.stats.players[1].cards.zombie.evolutionPlays == 1
        and math.abs((state.stats.players[1].cards.zombie.emeraldSpent or 0) - 13) <= EPSILON

    addData(data, "eligible_selected", selected)
    addData(data, "non_evolution_rejected", rejectedNonEvo)
    addData(data, "configured_normal_plays", configuredCycles)
    addData(data, "configured_evo_cost", configuredEvoCost)
    addData(data, "progress_after_play_1", progressSequence[1])
    addData(data, "progress_after_play_2", progressSequence[2])
    addData(data, "progress_after_play_3", progressSequence[3])
    addData(data, "progress_after_evolution", progressSequence[4])
    addData(data, "normal_cost_ok", normalCostOk)
    addData(data, "insufficient_evo_cost_rejected", rejectedForCost)
    addData(data, "ready_charge_preserved_on_failed_play", preservedReadyCharge)
    addData(data, "first_three_normal", normalPlays)
    addData(data, "fourth_play_evolved", evolvedFourth)
    addData(data, "evolution_abilities_applied", abilitiesApplied)
    addData(data, "evolution_telemetry", telemetry)

    restore()

    return selected
        and rejectedNonEvo
        and configuredCycles == 3
        and math.abs((configuredEvoCost or 0) - 4) <= EPSILON
        and normalPlays
        and normalCostOk
        and rejectedForCost
        and preservedReadyCharge
        and evolvedFourth
        and abilitiesApplied
        and progressSequence[1] == 1
        and progressSequence[2] == 2
        and progressSequence[3] == 3
        and progressSequence[4] == 0
        and telemetry,
        "Each Evolution may define its own charge count, Emerald cost, stats and existing engine abilities.",
        data
end)

runTest("evolution_ruleset", "Ruleset OFF fully disables Evolution gameplay", function()
    local state = Game.new()
    state.players[1].deck = {
        "zombie",
        "skeleton",
        "iron_golem",
        "bat_swarm",
        "cannon",
        "arrows",
        "creeper",
        "endermite",
    }
    state.players[2].deck = cards.defaultDeck()

    local selected = Game.setEvolutionCard(state, 1, "creeper")
    local disabled = Game.setRulesetRule(state, "evolutions", false, 1)

    Game.startCountdown(state)
    local enteredBattle = waitUntil(
        state,
        config.MATCH.countdown + 1,
        function() return state.phase == "battle" end,
        0.10
    )

    if not selected or not disabled or not enteredBattle then
        return false, "Could not start Evolution-disabled Ruleset scenario.", {}
    end

    -- Deliberately inject a ready-looking counter. Ruleset OFF must still
    -- force the base card and must not charge/consume this value.
    state.players[1].evolutionProgress = 2
    state.players[1].hand[1] = "creeper"
    state.players[1].emeralds = 10

    local cost = Game.getCardPlayCost(state, 1, "creeper")
    local played = Game.playCardFromSlot(state, 1, 1, SAFE_X, SAFE_Y)
    local spawned = findEntity(state, function(e)
        return e.alive
            and e.owner == 1
            and e.sourceCardId == "creeper"
    end)

    local data = {}
    addData(data, "ruleset_evolutions_enabled", Game.rulesetEnabled(state, "evolutions"))
    addData(data, "saved_evolution_card", state.players[1].evolutionCardId)
    addData(data, "play_cost", cost)
    addData(data, "spawned_name", spawned and spawned.name)
    addData(data, "spawned_is_evolution", spawned and spawned.isEvolution == true)
    addData(data, "progress_after_play", state.players[1].evolutionProgress)
    addData(data, "telemetry_evolution_plays", state.stats.players[1].evolutionPlays)

    return played
        and not Game.rulesetEnabled(state, "evolutions")
        and state.players[1].evolutionCardId == "creeper"
        and math.abs((cost or 0) - cards.get("creeper").cost) <= EPSILON
        and spawned ~= nil
        and spawned.name == "Creeper"
        and spawned.isEvolution ~= true
        and state.players[1].evolutionProgress == 2
        and state.stats.players[1].evolutionPlays == 0,
        "Ruleset OFF must preserve the selected Evo card but make every battle play use the untouched base form.",
        data
end)

runTest("admin_evolution_spawn", "Admin directly spawns Evolution forms", function()
    local state = newAdminState("empty")

    local chargedOk = Game.debugSpawnCard(
        state,
        1,
        "evo:creeper",
        SAFE_X - 10,
        SAFE_Y
    )
    local portalOk = Game.debugSpawnCard(
        state,
        1,
        "evo:nether_portal",
        SAFE_X,
        SAFE_Y
    )
    local miteOk = Game.debugSpawnCard(
        state,
        1,
        "evo:endermite",
        SAFE_X + 10,
        SAFE_Y
    )
    local elderOk = Game.debugSpawnCard(
        state,
        1,
        "evo:guardian",
        50,
        (config.ARENA.riverTop + config.ARENA.riverBottom) / 2
    )
    local bankOk = Game.debugSpawnCard(
        state,
        1,
        "evo:villager",
        SAFE_X + 18,
        SAFE_Y
    )
    local diamondOk = Game.debugSpawnCard(
        state,
        1,
        "evo:iron_golem",
        SAFE_X - 18,
        SAFE_Y
    )

    local charged = findEntity(state, function(e)
        return e.alive and e.name == "Charged Creeper"
    end)
    local portal = findEntity(state, function(e)
        return e.alive and e.name == "Ghast Portal"
    end)
    local mite = findEntity(state, function(e)
        return e.alive and e.name == "Mega Mite"
    end)
    local elder = findEntity(state, function(e)
        return e.alive and e.name == "Elder Guardian"
    end)
    local bank = findEntity(state, function(e)
        return e.alive and e.name == "Emerald Bank"
    end)
    local diamond = findEntity(state, function(e)
        return e.alive and e.name == "Diamond Golem"
    end)

    local catalog = cards.adminSpawnCards()
    local evoEntries = 0
    for _, entry in ipairs(catalog) do
        if entry.isEvolution then evoEntries = evoEntries + 1 end
    end

    local data = {}
    addData(data, "admin_catalog_entries", #catalog)
    addData(data, "admin_evolution_entries", evoEntries)
    addData(data, "charged_creeper_spawned", charged ~= nil)
    addData(data, "ghast_portal_spawned", portal ~= nil)
    addData(data, "mega_mite_spawned", mite ~= nil)
    addData(data, "elder_guardian_spawned", elder ~= nil)
    addData(data, "emerald_bank_spawned", bank ~= nil)
    addData(data, "diamond_golem_spawned", diamond ~= nil)
    addData(data, "all_marked_evolution",
        charged and portal and mite and elder and bank and diamond
        and charged.isEvolution == true
        and portal.isEvolution == true
        and mite.isEvolution == true
        and elder.isEvolution == true
        and bank.isEvolution == true
        and diamond.isEvolution == true
    )

    return chargedOk
        and portalOk
        and miteOk
        and elderOk
        and bankOk
        and diamondOk
        and evoEntries == #cards.evolutionCards(true)
        and charged ~= nil
        and portal ~= nil
        and mite ~= nil
        and elder ~= nil
        and bank ~= nil
        and diamond ~= nil
        and charged.isEvolution == true
        and portal.isEvolution == true
        and mite.isEvolution == true
        and elder.isEvolution == true
        and bank.isEvolution == true
        and diamond.isEvolution == true,
        "Admin card pages must include every Evolution as a direct sandbox spawn, bypassing cycles and Emerald cost.",
        data
end)

runTest("evo_diamond_golem", "Diamond Golem stomps only while walking", function()
    local state = newAdminState("empty")

    local diamondOk = Game.debugSpawnCard(
        state,
        1,
        "evo:iron_golem",
        SAFE_X,
        SAFE_Y
    )
    local cannonOk = Game.debugSpawnCard(
        state,
        2,
        "cannon",
        SAFE_X,
        SAFE_Y - 20
    )
    local zombieOk = Game.debugSpawnCard(
        state,
        2,
        "zombie",
        SAFE_X + 2,
        SAFE_Y - 4
    )
    local blazeOk = Game.debugSpawnCard(
        state,
        2,
        "blaze",
        SAFE_X - 2,
        SAFE_Y - 4
    )

    local diamond = findEntity(state, function(e)
        return e.alive and e.owner == 1 and e.name == "Diamond Golem"
    end)
    local cannon = findEntity(state, function(e)
        return e.alive and e.owner == 2 and e.name == "Cannon"
    end)
    local zombie = findEntity(state, function(e)
        return e.alive and e.owner == 2 and e.name == "Zombie"
    end)
    local blaze = findEntity(state, function(e)
        return e.alive and e.owner == 2 and e.name == "Blaze"
    end)

    if not diamondOk or not cannonOk or not zombieOk or not blazeOk
        or not diamond or not cannon or not zombie or not blaze
    then
        return false, "Could not create Diamond Golem stomp scenario.", {}
    end

    cannon.damage = 0
    zombie.moveSpeed = 0
    zombie.damage = 0
    zombie.attackCooldownLeft = 999
    blaze.moveSpeed = 0
    blaze.damage = 0
    blaze.attackCooldownLeft = 999

    local zombieStart = zombie.hp
    local blazeStart = blaze.hp

    -- The Golem is walking toward the Cannon. Its 2-second stomp timer must
    -- advance only during that real movement time.
    step(state, 1.90, DEFAULT_DT)
    local beforeFirstPulse = zombieStart - zombie.hp

    step(state, 0.20, DEFAULT_DT)
    local afterFirstPulse = zombieStart - zombie.hp
    local blazeAfterFirstPulse = blazeStart - blaze.hp

    local quakeVisible = false
    for _, effect in ipairs(state.effects) do
        if effect.kind == "diamond_quake" then
            quakeVisible = true
            break
        end
    end

    -- Put the Golem directly in melee range of its building target. It now
    -- stands still and attacks; the freshly reset stomp timer must pause.
    diamond.x = cannon.x
    diamond.y = cannon.y + 2.5
    diamond.targetId = cannon.id
    diamond.lockedTargetId = cannon.id
    zombie.x = diamond.x + 2
    zombie.y = diamond.y
    local stationaryZombieHp = zombie.hp
    local stationaryTimerBefore = diamond.groundPulseTimer

    step(state, 2.30, DEFAULT_DT)

    local stationaryDamage = stationaryZombieHp - zombie.hp
    local stationaryTimerAfter = diamond.groundPulseTimer

    local base = cards.get("iron_golem")
    local evolved = cards.evolvedCopy("iron_golem")
    local data = {}
    addData(data, "configured_cycles", cards.evolutionCycles("iron_golem"))
    addData(data, "base_hp", base.unit.maxHp)
    addData(data, "diamond_hp", evolved and evolved.unit.maxHp)
    addData(data, "stomp_interval_s", diamond.groundPulse and diamond.groundPulse.interval)
    addData(data, "stomp_damage", diamond.groundPulse and diamond.groundPulse.damage)
    addData(data, "stomp_radius", diamond.groundPulse and diamond.groundPulse.radius)
    addData(data, "ground_damage_before_2s_walk", beforeFirstPulse)
    addData(data, "ground_damage_after_first_walk_pulse", afterFirstPulse)
    addData(data, "flying_damage_after_first_pulse", blazeAfterFirstPulse)
    addData(data, "quake_effect_visible", quakeVisible)
    addData(data, "stationary_damage_over_2_3s", stationaryDamage)
    addData(data, "stationary_timer_before", stationaryTimerBefore)
    addData(data, "stationary_timer_after", stationaryTimerAfter)

    return cards.evolutionCycles("iron_golem") == 2
        and evolved
        and math.abs(evolved.unit.maxHp - base.unit.maxHp * 1.05) <= EPSILON
        and diamond.visualVariant == "diamond_golem"
        and math.abs(beforeFirstPulse) <= EPSILON
        and math.abs(afterFirstPulse - 20) <= EPSILON
        and math.abs(blazeAfterFirstPulse) <= EPSILON
        and quakeVisible
        and math.abs(stationaryDamage) <= EPSILON
        and math.abs((stationaryTimerAfter or 0) - (stationaryTimerBefore or 0)) <= EPSILON,
        "Diamond Golem must charge/stomp only from real walking time; standing still to hit a building or tower must pause the stomp timer.",
        data
end)

runTest("guardian_targeting", "Unreachable ground troops ignore Guardian and Elder Guardian", function()
    local riverY = (config.ARENA.riverTop + config.ARENA.riverBottom) / 2
    local attackerY = config.ARENA.riverTop - 6

    local function checkForm(spawnId, expectedName)
        local state = newAdminState("empty")
        local waterOk = Game.debugSpawnCard(state, 1, spawnId, 50, riverY)
        local guardian = findEntity(state, function(e)
            return e.alive and e.owner == 1 and e.name == expectedName
        end)

        if not waterOk or not guardian then
            return nil, "Could not create " .. expectedName .. " targeting scenario."
        end

        guardian.passive = true
        guardian.targetMode = "none"

        local zombieOk = Game.debugSpawnCard(state, 2, "zombie", 50, attackerY)
        Game.update(state, 0.10)
        local zombie = findEntity(state, function(e)
            return e.alive and e.owner == 2 and e.name == "Zombie"
        end)
        local zombieIgnored = zombie and zombie.targetId == nil

        local skeletonOk = Game.debugSpawnCard(state, 2, "skeleton", 50, attackerY)
        Game.update(state, 0.10)
        local skeleton = findEntity(state, function(e)
            return e.alive and e.owner == 2 and e.name == "Skeleton"
        end)
        local skeletonTargets = skeleton and skeleton.targetId == guardian.id

        return {
            state = state,
            guardian = guardian,
            waterOk = waterOk,
            zombieOk = zombieOk,
            zombieIgnored = zombieIgnored,
            skeletonOk = skeletonOk,
            skeletonTargets = skeletonTargets,
            requiredReach = arena.distanceToGroundReach(guardian.x, guardian.y),
        }
    end

    local placementState = newAdminState("empty")
    local landOk, landReason = Game.debugSpawnCard(
        placementState,
        1,
        "guardian",
        SAFE_X,
        SAFE_Y
    )
    local elderLandOk, elderLandReason = Game.debugSpawnCard(
        placementState,
        1,
        "evo:guardian",
        SAFE_X,
        SAFE_Y
    )
    local bridgeOk = Game.debugSpawnCard(
        placementState,
        1,
        "guardian",
        config.ARENA.bridgeCenters[1],
        riverY
    )
    local elderBridgeOk = Game.debugSpawnCard(
        placementState,
        1,
        "evo:guardian",
        config.ARENA.bridgeCenters[1],
        riverY
    )

    local guardianResult, guardianErr = checkForm("guardian", "Guardian")
    local elderResult, elderErr = checkForm("evo:guardian", "Elder Guardian")

    if not guardianResult or not elderResult then
        return false, guardianErr or elderErr or "Guardian form check failed.", {}
    end

    local elderCard = cards.evolvedCopy("guardian")
    local data = {}
    addData(data, "guardian_admin_land_rejected", not landOk)
    addData(data, "guardian_land_reason", landReason)
    addData(data, "elder_admin_land_rejected", not elderLandOk)
    addData(data, "elder_land_reason", elderLandReason)
    addData(data, "guardian_bridge_rejected", not bridgeOk)
    addData(data, "elder_bridge_rejected", not elderBridgeOk)
    addData(data, "guardian_water_only_flag", guardianResult.guardian.waterOnly == true)
    addData(data, "elder_water_only_flag", elderResult.guardian.waterOnly == true)
    addData(data, "evolved_card_water_only_flag", elderCard and elderCard.unit.waterOnly == true)
    addData(data, "distance_to_ground_reach", guardianResult.requiredReach)
    addData(data, "zombie_attack_range", cards.get("zombie").unit.attackRange)
    addData(data, "guardian_ignored_by_zombie", guardianResult.zombieIgnored)
    addData(data, "elder_ignored_by_zombie", elderResult.zombieIgnored)
    addData(data, "skeleton_attack_range", cards.get("skeleton").unit.attackRange)
    addData(data, "guardian_targeted_by_skeleton", guardianResult.skeletonTargets)
    addData(data, "elder_targeted_by_skeleton", elderResult.skeletonTargets)

    return not landOk
        and landReason == "WATER ONLY - PLACE IN OPEN RIVER"
        and not elderLandOk
        and elderLandReason == "WATER ONLY - PLACE IN OPEN RIVER"
        and not bridgeOk
        and not elderBridgeOk
        and guardianResult.guardian.waterOnly == true
        and elderResult.guardian.waterOnly == true
        and elderCard
        and elderCard.unit.waterOnly == true
        and guardianResult.zombieOk
        and guardianResult.zombieIgnored
        and elderResult.zombieOk
        and elderResult.zombieIgnored
        and guardianResult.skeletonOk
        and guardianResult.skeletonTargets
        and elderResult.skeletonOk
        and elderResult.skeletonTargets,
        "Guardian and Elder Guardian must share the same water-only targeting contract: unreachable ground melee ignores them, while ranged ground units that can physically reach them may target them.",
        data
end)

runTest("guardian_beam", "Guardian water beam ramps and resists disruption", function()
    local riverY = (config.ARENA.riverTop + config.ARENA.riverBottom) / 2
    local guardianX = config.ARENA.bridgeCenters[1]
        + config.ARENA.bridgeHalfWidth
        + 3
    local bridgeX = config.ARENA.bridgeCenters[1] + 4

    local state = newAdminState("empty")
    local waterAllowed = arena.placementAllowed(1, guardianX, riverY, "water", state)
    local landRejected = not arena.placementAllowed(1, SAFE_X, SAFE_Y, "water", state)
    local bridgeRejected = not arena.placementAllowed(
        1,
        config.ARENA.bridgeCenters[1],
        riverY,
        "water",
        state
    )

    local guardianOk = Game.debugSpawnCard(state, 1, "guardian", guardianX, riverY)
    local golemOk = Game.debugSpawnCard(state, 2, "iron_golem", bridgeX, riverY)
    local guardian = findEntity(state, function(e)
        return e.alive and e.owner == 1 and e.name == "Guardian"
    end)
    local golem = findEntity(state, function(e)
        return e.alive and e.owner == 2 and e.name == "Iron Golem"
    end)

    if not guardianOk or not golemOk or not guardian or not golem then
        return false, "Could not create Guardian beam scenario.", {}
    end

    local hp0 = golem.hp
    step(state, 1.0, DEFAULT_DT)
    local damageFirstSecond = hp0 - golem.hp
    local hp1 = golem.hp
    step(state, 1.0, DEFAULT_DT)
    local damageSecondSecond = hp1 - golem.hp
    local chargeBeforeSkeleton = guardian.beamCharge or 0

    local skeletonOk = Game.debugSpawnCard(
        state,
        2,
        "skeleton",
        config.ARENA.bridgeCenters[1],
        riverY
    )

    local disrupted, disruptElapsed = waitUntil(
        state,
        1.5,
        function()
            return guardian.lastBeamChargeBeforeHit ~= nil
        end,
        DEFAULT_DT
    )

    local beforeHit = guardian.lastBeamChargeBeforeHit
    local afterHit = guardian.lastBeamChargeAfterHit
    local exactTwentyPercent = disrupted
        and beforeHit
        and afterHit
        and beforeHit > 0
        and math.abs(afterHit - beforeHit * 0.80) <= EPSILON
        and afterHit > 0

    local beamVisible = false
    for _, effect in ipairs(state.effects) do
        if effect.kind == "guardian_beam" then
            beamVisible = true
            break
        end
    end

    local spikeState = newAdminState("empty")
    Game.debugSpawnCard(spikeState, 1, "guardian", guardianX, riverY)
    Game.debugSpawnCard(spikeState, 2, "blaze", guardianX, riverY - 15)

    local spikeGuardian = findEntity(spikeState, function(e)
        return e.alive and e.owner == 1 and e.name == "Guardian"
    end)
    local blaze = findEntity(spikeState, function(e)
        return e.alive and e.owner == 2 and e.name == "Blaze"
    end)

    -- Isolate spike reflection from Guardian beam damage. With the improved
    -- 18 range the Guardian can now reach this Blaze, so leaving its offense
    -- enabled would mix beam damage into the reflected-damage measurement.
    if spikeGuardian then
        spikeGuardian.passive = true
        spikeGuardian.targetMode = "none"
        spikeGuardian.targetId = nil
        spikeGuardian.lockedTargetId = nil
    end

    local blazeStartHp = blaze and blaze.hp or 0
    local spikeHit, spikeElapsed = waitUntil(
        spikeState,
        1.5,
        function()
            return spikeGuardian and spikeGuardian.hp < spikeGuardian.maxHp
        end,
        DEFAULT_DT
    )
    local reflected = blaze and (blazeStartHp - blaze.hp) or 0

    local card = cards.get("guardian")
    local data = {}
    addData(data, "water_allowed", waterAllowed)
    addData(data, "land_rejected", landRejected)
    addData(data, "bridge_rejected", bridgeRejected)
    addData(data, "guardian_hp", card.unit.maxHp)
    addData(data, "skeleton_arrow_damage", cards.get("skeleton").unit.damage)
    addData(data, "beam_base_dps", card.unit.beam.baseDps)
    addData(data, "beam_max_dps", card.unit.beam.maxDps)
    addData(data, "damage_first_second", damageFirstSecond)
    addData(data, "damage_second_second", damageSecondSecond)
    addData(data, "charge_before_skeleton_spawn", chargeBeforeSkeleton)
    addData(data, "disruption_detected", disrupted)
    addData(data, "disruption_time_s", disruptElapsed)
    addData(data, "charge_before_hit", beforeHit)
    addData(data, "charge_after_hit", afterHit)
    addData(data, "beam_visible", beamVisible)
    addData(data, "spike_hit_detected", spikeHit)
    addData(data, "spike_hit_time_s", spikeElapsed)
    addData(data, "flying_damage_reflected", reflected)

    return waterAllowed
        and landRejected
        and bridgeRejected
        and card.cost == 6
        and card.unit.maxHp == cards.get("skeleton").unit.damage * 3
        and damageFirstSecond > 0
        and damageSecondSecond > damageFirstSecond
        and skeletonOk
        and exactTwentyPercent
        and beamVisible
        and spikeHit
        and math.abs(reflected - 64 * 0.05) <= 0.01,
        "Guardian must live only in open river water, ramp its locked beam, keep 80% charge when hit and reflect 5% of flying attack damage.",
        data
end)

runTest("evo_elder_guardian", "Benched Elder Guardian remains fully functional in dev mode", function()
    local riverY = (config.ARENA.riverTop + config.ARENA.riverBottom) / 2
    local guardianX = config.ARENA.bridgeCenters[1]
        + config.ARENA.bridgeHalfWidth
        + 3

    local lobbyState = Game.new()
    lobbyState.players[1].deck = cards.defaultDeck()
    local deckAddRejected = not Game.toggleDeckCard(
        lobbyState,
        1,
        "guardian"
    )

    lobbyState.players[1].deck[8] = "guardian"
    local evoSelectionRejected = not Game.setEvolutionCard(
        lobbyState,
        1,
        "guardian"
    )

    local state = newAdminState("empty")
    local elderOk = Game.debugSpawnCard(
        state,
        1,
        "evo:guardian",
        guardianX,
        riverY
    )

    local elder = findEntity(state, function(e)
        return e.alive and e.owner == 1 and e.name == "Elder Guardian"
    end)

    local zombieOk = Game.debugSpawnCard(
        state,
        2,
        "zombie",
        guardianX,
        riverY - 17
    )
    local zombie = findEntity(state, function(e)
        return e.alive and e.owner == 2 and e.name == "Zombie"
    end)

    if not elderOk or not elder or not zombieOk or not zombie then
        return false, "Could not create dev-only Elder Guardian scenario.", {}
    end

    zombie.passive = true
    zombie.targetMode = "none"
    zombie.damage = 0

    local zombieStartHp = zombie.hp
    step(state, 0.35, DEFAULT_DT)
    local slowedFactor = zombie.globalMoveSpeedFactor
    local elderAcquiredAt17 = elder.targetId == zombie.id
    local beamDamageAt17 = zombieStartHp - zombie.hp

    elder.alive = false
    Game.update(state, DEFAULT_DT)
    local restoredFactor = zombie.globalMoveSpeedFactor

    local base = cards.get("guardian")
    local evolved = cards.evolvedCopy("guardian")
    local data = {}
    addData(data, "guardian_dev_only", base and base.devOnly == true)
    addData(data, "guardian_normal_deck_add_rejected", deckAddRejected)
    addData(data, "guardian_normal_evo_selection_rejected", evoSelectionRejected)
    addData(data, "public_evolution_count", #cards.evolutionCards())
    addData(data, "dev_evolution_count", #cards.evolutionCards(true))
    addData(data, "elder_admin_spawned", elderOk)
    addData(data, "elder_is_evolution", elder.isEvolution == true)
    addData(data, "elder_range", elder.attackRange)
    addData(data, "elder_hp", elder.maxHp)
    addData(data, "global_slow", elder.globalEnemyMoveSlow)
    addData(data, "enemy_move_factor_with_elder", slowedFactor)
    addData(data, "elder_acquired_target_at_17", elderAcquiredAt17)
    addData(data, "beam_damage_at_17", beamDamageAt17)
    addData(data, "enemy_move_factor_after_elder_death", restoredFactor)

    return base
        and base.devOnly == true
        and not cards.isSelectable("guardian")
        and deckAddRejected
        and evoSelectionRejected
        and #cards.evolutionCards() == 5
        and #cards.evolutionCards(true) == 6
        and elder.isEvolution == true
        and evolved
        and elder.attackRange == 18
        and elder.aggroRange == 18
        and elder.maxHp == base.unit.maxHp * 2
        and math.abs((slowedFactor or 0) - 0.95) <= EPSILON
        and elderAcquiredAt17
        and beamDamageAt17 > 0
        and math.abs((restoredFactor or 0) - 1.0) <= EPSILON,
        "Guardian/Elder must be unavailable to normal deck/Evo selection while remaining fully functional through admin/dev spawns.",
        data
end)

runTest("evo_emerald_bank", "Emerald Bank keeps production and lasts 20s longer", function()
    local state = Game.new()
    state.players[1].deck = {
        "zombie",
        "skeleton",
        "iron_golem",
        "bat_swarm",
        "cannon",
        "arrows",
        "villager",
        "wolf",
    }
    state.players[2].deck = cards.defaultDeck()

    local selected = Game.setEvolutionCard(state, 1, "villager")
    Game.startCountdown(state)
    local enteredBattle = waitUntil(
        state,
        config.MATCH.countdown + 1,
        function() return state.phase == "battle" end,
        0.10
    )

    if not selected or not enteredBattle then
        return false, "Could not start Emerald Bank evolution scenario.", {}
    end

    state.players[1].evolutionProgress = 3
    state.players[1].hand[1] = "villager"
    state.players[1].emeralds = 10

    local played = Game.playCardFromSlot(state, 1, 1, SAFE_X, SAFE_Y)
    local bank = findEntity(state, function(e)
        return e.alive and e.owner == 1 and e.name == "Emerald Bank"
    end)

    if not played or not bank then
        return false, "Emerald Bank did not deploy on its ready play.", {}
    end

    local initialLifetime = bank.remainingLifetime
    local initialHp = bank.maxHp
    state.players[1].emeralds = 0
    state.players[2].emeralds = 0

    Game.update(state, 0.25)

    local baseGain = config.MATCH.emeraldPerSecond * 0.25
    local expectedGain = baseGain * (1 + cards.get("villager").unit.emeraldBoost)
    local realizedGain = state.players[1].emeralds

    local data = {}
    addData(data, "configured_cycles", cards.evolutionCycles("villager"))
    addData(data, "bank_hp", initialHp)
    addData(data, "base_villager_hp", cards.get("villager").unit.maxHp)
    addData(data, "bank_lifetime_s", initialLifetime)
    addData(data, "base_villager_lifetime_s", cards.get("villager").unit.lifetime)
    addData(data, "bank_emerald_boost", bank.emeraldBoost)
    addData(data, "expected_emerald_gain_0_25s", expectedGain)
    addData(data, "realized_emerald_gain_0_25s", realizedGain)

    return cards.evolutionCycles("villager") == 3
        and math.abs(initialHp - cards.get("villager").unit.maxHp * 1.05) <= EPSILON
        and math.abs(initialLifetime - (cards.get("villager").unit.lifetime + 20)) <= EPSILON
        and math.abs(bank.emeraldBoost - cards.get("villager").unit.emeraldBoost) <= EPSILON
        and math.abs(realizedGain - expectedGain) <= 0.001,
        "Emerald Bank must preserve Villager economy output while gaining 5% HP and exactly 20 seconds of lifetime.",
        data
end)

runTest("evo_charged_creeper", "Charged Creeper has larger blue blast", function()
    local state = Game.new()
    state.players[1].deck = cards.defaultDeck()
    state.players[2].deck = cards.defaultDeck()

    local selected = Game.setEvolutionCard(state, 1, "creeper")
    Game.startCountdown(state)
    local enteredBattle = waitUntil(
        state,
        config.MATCH.countdown + 1,
        function() return state.phase == "battle" end,
        0.10
    )

    if not selected or not enteredBattle then
        return false, "Could not start Charged Creeper evolution scenario.", {}
    end

    -- Isolate Creeper blast damage from normal Crown Tower fire. Without
    -- this, the farther control target can receive 80-damage Princess Tower
    -- shots while the fuse is running and produce a false FAIL.
    for _, entity in ipairs(state.entities) do
        if entity.kind == "tower" then
            entity.damage = 0
            entity.attackRange = 0
            entity.attackCooldownLeft = 999
            entity.targetId = nil
            entity.lockedTargetId = nil
            entity.passive = true
            entity.targetMode = "none"
        end
    end
    state.projectiles = {}

    state.players[1].evolutionProgress = 2
    state.players[1].hand[1] = "creeper"
    state.players[1].emeralds = 10

    local played = Game.playCardFromSlot(state, 1, 1, SAFE_X, SAFE_Y)
    local charged = findEntity(state, function(e)
        return e.alive and e.owner == 1 and e.name == "Charged Creeper"
    end)

    if not played or not charged then
        return false, "Charged Creeper did not deploy on its ready play.", {}
    end

    local function debugSpawnEnemy(cardId, x, y)
        state.adminMode = true
        local ok = Game.debugSpawnCard(state, 2, cardId, x, y)
        state.adminMode = false
        if not ok then return nil end

        local newest = nil
        for _, entity in ipairs(state.entities) do
            if entity.alive and entity.owner == 2 and entity.sourceCardId == cardId then
                if not newest or entity.id > newest.id then newest = entity end
            end
        end
        return newest
    end

    local nearZombie = debugSpawnEnemy("zombie", SAFE_X, SAFE_Y + 3)
    local farZombie = debugSpawnEnemy("zombie", SAFE_X, SAFE_Y + 10)
    if not nearZombie or not farZombie then
        return false, "Could not create Charged Creeper blast targets.", {}
    end

    for _, zombie in ipairs({ nearZombie, farZombie }) do
        zombie.moveSpeed = 0
        zombie.damage = 0
        zombie.attackCooldownLeft = 999
    end

    local nearStart = nearZombie.hp
    local farStart = farZombie.hp

    local exploded, elapsed = waitUntil(
        state,
        1.50,
        function() return not charged.alive end,
        DEFAULT_DT
    )

    local chargedEffect = false
    for _, effect in ipairs(state.effects) do
        if effect.kind == "charged_explosion" then
            chargedEffect = true
            break
        end
    end

    local nearDamage = nearStart - nearZombie.hp
    local farDamage = farStart - farZombie.hp
    local spec = charged.proximityExplosion

    local data = {}
    addData(data, "configured_cycles", cards.evolutionCycles("creeper"))
    addData(data, "base_radius", cards.get("creeper").unit.proximityExplosion.radius)
    addData(data, "charged_radius", spec and spec.radius)
    addData(data, "charged_visual_radius", spec and spec.visualRadius)
    addData(data, "visual_variant", charged.visualVariant)
    addData(data, "exploded", exploded)
    addData(data, "explosion_time_s", elapsed)
    addData(data, "near_target_damage", nearDamage)
    addData(data, "far_target_distance", 10)
    addData(data, "far_target_damage", farDamage)
    addData(data, "charged_effect_visible", chargedEffect)

    return cards.evolutionCycles("creeper") == 2
        and charged.visualVariant == "charged_creeper"
        and spec
        and spec.radius == 12
        and (spec.visualRadius or 0) > spec.radius
        and exploded
        and chargedEffect
        and math.abs(nearDamage - 580) <= EPSILON
        and math.abs(farDamage - 580) <= EPSILON,
        "Charged Creeper must deal double base damage, expand gameplay AoE from 8 to 12 and use the large blue explosion effect.",
        data
end)

runTest("evo_ghast_portal", "Ghast Portal spawns exactly two artillery Ghasts", function()
    local state = Game.new()
    state.players[1].deck = {
        "zombie",
        "skeleton",
        "iron_golem",
        "bat_swarm",
        "cannon",
        "arrows",
        "creeper",
        "nether_portal",
    }
    state.players[2].deck = cards.defaultDeck()

    local selected = Game.setEvolutionCard(state, 1, "nether_portal")
    Game.startCountdown(state)
    local enteredBattle = waitUntil(
        state,
        config.MATCH.countdown + 1,
        function() return state.phase == "battle" end,
        0.10
    )

    if not selected or not enteredBattle then
        return false, "Could not start Ghast Portal evolution scenario.", {}
    end

    -- Towers stay as targetable objectives but cannot kill the fragile Ghasts
    -- while this diagnostic verifies their artillery behavior.
    for _, entity in ipairs(state.entities) do
        if entity.kind == "tower" then entity.damage = 0 end
    end

    state.players[1].evolutionProgress = 2
    state.players[1].hand[1] = "nether_portal"
    state.players[1].emeralds = 10

    local played = Game.playCardFromSlot(state, 1, 1, SAFE_X, SAFE_Y)
    local portal = findEntity(state, function(e)
        return e.alive and e.owner == 1 and e.name == "Ghast Portal"
    end)

    if not played or not portal then
        return false, "Ghast Portal did not deploy on its ready play.", {}
    end

    local firstGhastReady, firstSpawnElapsed = waitUntil(
        state,
        3.5,
        function()
            return findEntity(state, function(e)
                return e.alive and e.owner == 1 and e.name == "Ghast"
            end) ~= nil
        end,
        DEFAULT_DT
    )

    local ghast = findEntity(state, function(e)
        return e.alive and e.owner == 1 and e.name == "Ghast"
    end)

    if not firstGhastReady or not ghast then
        return false, "Ghast Portal did not produce its first Ghast.", {}
    end

    ghast.moveSpeed = 0
    ghast.attackCooldownLeft = 0

    local function debugSpawnEnemy(cardId, x, y)
        state.adminMode = true
        local ok = Game.debugSpawnCard(state, 2, cardId, x, y)
        state.adminMode = false
        if not ok then return nil end

        local newest = nil
        for _, entity in ipairs(state.entities) do
            if entity.alive and entity.owner == 2 and entity.sourceCardId == cardId then
                if not newest or entity.id > newest.id then newest = entity end
            end
        end
        return newest
    end

    local blaze = debugSpawnEnemy("blaze", ghast.x, ghast.y + 8)
    local splashZombie = debugSpawnEnemy("zombie", ghast.x + 2, ghast.y + 8)

    if not blaze or not splashZombie then
        return false, "Could not create Ghast artillery targets.", {}
    end

    blaze.passive = true
    blaze.targetMode = "none"
    blaze.damage = 0
    blaze.attackCooldownLeft = 999
    splashZombie.passive = true
    splashZombie.targetMode = "none"
    splashZombie.damage = 0
    splashZombie.attackCooldownLeft = 999

    local blazeStart = blaze.hp
    local zombieStart = splashZombie.hp

    ghast.targetId = blaze.id
    ghast.lockedTargetId = nil
    ghast.attackCooldownLeft = 0

    local firstHit, firstHitElapsed = waitUntil(
        state,
        1.5,
        function() return blaze.hp < blazeStart end,
        DEFAULT_DT
    )

    local blazeAfterFirst = blaze.hp
    local zombieAfterFirst = splashZombie.hp
    local primarySlowed = (blaze.slowRemaining or 0) > 0
        and (blaze.slowFactor or 1) < 1
    local splashNotSlowed = (splashZombie.slowRemaining or 0) <= EPSILON
        and math.abs((splashZombie.slowFactor or 1) - 1) <= EPSILON

    ghast.attackCooldownLeft = 0
    local killedInSecondHit, secondHitElapsed = waitUntil(
        state,
        1.5,
        function() return not blaze.alive end,
        DEFAULT_DT
    )

    -- Continue until the portal has completed its natural lifetime. Track
    -- every Ghast ID so a killed first summon cannot make the total look lower.
    local seenGhasts = {}
    for _, entity in ipairs(state.entities) do
        if entity.name == "Ghast" then seenGhasts[entity.id] = true end
    end

    local extraElapsed = 0
    while portal.alive and extraElapsed < 22 do
        Game.update(state, DEFAULT_DT)
        extraElapsed = extraElapsed + DEFAULT_DT
        for _, entity in ipairs(state.entities) do
            if entity.name == "Ghast" then seenGhasts[entity.id] = true end
        end
    end

    local uniqueGhasts = 0
    for _ in pairs(seenGhasts) do uniqueGhasts = uniqueGhasts + 1 end

    local template = cards.getInternalUnit("ghast")
    local data = {}
    addData(data, "configured_cycles", cards.evolutionCycles("nether_portal"))
    addData(data, "portal_visual_variant", portal.visualVariant)
    addData(data, "first_ghast_spawn_s", firstSpawnElapsed)
    addData(data, "portal_spawn_total", portal.periodicSpawnTotal)
    addData(data, "unique_ghasts_seen", uniqueGhasts)
    addData(data, "ghast_hp", template and template.maxHp)
    addData(data, "ghast_damage", template and template.damage)
    addData(data, "ghast_range", template and template.attackRange)
    addData(data, "ghast_cooldown", template and template.attackCooldown)
    addData(data, "first_hit_time_s", firstHitElapsed)
    addData(data, "blaze_hp_after_first_hit", blazeAfterFirst)
    addData(data, "splash_zombie_damage_first_hit", zombieStart - zombieAfterFirst)
    addData(data, "primary_target_slowed", primarySlowed)
    addData(data, "splash_target_not_slowed", splashNotSlowed)
    addData(data, "blaze_killed_by_second_hit", killedInSecondHit)
    addData(data, "second_hit_time_s", secondHitElapsed)

    return cards.evolutionCycles("nether_portal") == 2
        and portal.visualVariant == "ghast_portal"
        and portal.periodicSpawn
        and portal.periodicSpawn.maxTotal == 2
        and portal.periodicSpawnTotal == 2
        and uniqueGhasts == 2
        and firstHit
        and math.abs((blazeStart - blazeAfterFirst) - 130) <= EPSILON
        and math.abs((zombieStart - zombieAfterFirst) - 130) <= EPSILON
        and primarySlowed
        and splashNotSlowed
        and killedInSecondHit,
        "Ghast Portal must emit exactly two fragile long-range Ghasts; their 130-damage splash fireballs two-hit Blaze and slow only the primary target.",
        data
end)

runTest("evo_mega_mite", "Mega Mite keeps all stats except five-times HP", function()
    local state = Game.new()
    state.players[1].deck = {
        "zombie",
        "skeleton",
        "iron_golem",
        "bat_swarm",
        "cannon",
        "arrows",
        "creeper",
        "endermite",
    }
    state.players[2].deck = cards.defaultDeck()

    local selected = Game.setEvolutionCard(state, 1, "endermite")
    Game.startCountdown(state)
    local enteredBattle = waitUntil(
        state,
        config.MATCH.countdown + 1,
        function() return state.phase == "battle" end,
        0.10
    )

    if not selected or not enteredBattle then
        return false, "Could not start Mega Mite evolution scenario.", {}
    end

    state.players[1].evolutionProgress = 4
    state.players[1].hand[1] = "endermite"
    state.players[1].emeralds = 10

    local played = Game.playCardFromSlot(state, 1, 1, SAFE_X, SAFE_Y)
    local mega = findEntity(state, function(e)
        return e.alive and e.owner == 1 and e.name == "Mega Mite"
    end)
    local base = cards.get("endermite").unit

    local data = {}
    addData(data, "configured_cycles", cards.evolutionCycles("endermite"))
    addData(data, "base_hp", base.maxHp)
    addData(data, "mega_hp", mega and mega.maxHp)
    addData(data, "base_damage", base.damage)
    addData(data, "mega_damage", mega and mega.damage)
    addData(data, "base_speed", base.moveSpeed)
    addData(data, "mega_speed", mega and mega.moveSpeed)
    addData(data, "base_cooldown", base.attackCooldown)
    addData(data, "mega_cooldown", mega and mega.attackCooldown)
    addData(data, "visual_variant", mega and mega.visualVariant)
    addData(data, "emeralds_after_play", state.players[1].emeralds)

    return played
        and mega ~= nil
        and cards.evolutionCycles("endermite") == 4
        and math.abs(mega.maxHp - base.maxHp * 5) <= EPSILON
        and math.abs(mega.damage - base.damage) <= EPSILON
        and math.abs(mega.moveSpeed - base.moveSpeed) <= EPSILON
        and math.abs(mega.attackRange - base.attackRange) <= EPSILON
        and math.abs(mega.attackCooldown - base.attackCooldown) <= EPSILON
        and mega.visualVariant == "mega_mite"
        and math.abs(state.players[1].emeralds - 9) <= EPSILON,
        "Mega Mite must cost the normal 1E and preserve every Endermite combat stat except max HP, which is exactly 5x.",
        data
end)

runTest("tower_bridge_range", "Princess Tower engages just after bridge exit", function()
    local state = newAdminState("full")
    local laneX = config.ARENA.bridgeCenters[1]
    local tower = findEntity(state, function(e)
        return e.alive
            and e.owner == 2
            and e.kind == "tower"
            and e.towerType == "princess"
            and e.x < config.ARENA.width / 2
    end)

    if not tower then
        return false, "Could not find top-left Princess Tower.", {}
    end

    -- Isolate one Princess Tower so the test measures only its coverage.
    for _, entity in ipairs(state.entities) do
        if entity.kind == "tower" and entity.id ~= tower.id then
            entity.passive = true
            entity.targetMode = "none"
        end
    end

    local bridgeExitY = config.ARENA.riverTop - 2
    local engageY = config.ARENA.riverTop - 4

    local zombieOk = Game.debugSpawnCard(
        state,
        1,
        "zombie",
        laneX,
        bridgeExitY
    )
    local zombie = findEntity(state, function(e)
        return e.alive and e.owner == 1 and e.name == "Zombie"
    end)

    if not zombieOk or not zombie then
        return false, "Could not spawn bridge-range target.", {}
    end

    zombie.passive = true
    zombie.targetMode = "none"
    zombie.moveSpeed = 0

    Game.update(state, 0.10)
    local ignoredAtExit = tower.targetId == nil

    zombie.y = engageY
    tower.targetId = nil
    tower.lockedTargetId = nil
    Game.update(state, 0.10)
    local acquiredJustPastBridge = tower.targetId == zombie.id

    local exitDistance = util.distance(tower.x, tower.y, laneX, bridgeExitY)
    local engageDistance = util.distance(tower.x, tower.y, laneX, engageY)

    local data = {}
    addData(data, "princess_range", tower.attackRange)
    addData(data, "bridge_exit_y", bridgeExitY)
    addData(data, "distance_at_bridge_exit", exitDistance)
    addData(data, "ignored_at_bridge_exit", ignoredAtExit)
    addData(data, "engage_y", engageY)
    addData(data, "distance_just_past_bridge", engageDistance)
    addData(data, "acquired_just_past_bridge", acquiredJustPastBridge)
    addData(data, "king_range", config.TOWERS and config.TOWERS.kingRange)

    return math.abs(tower.attackRange - 42.5) <= EPSILON
        and ignoredAtExit
        and acquiredJustPastBridge
        and math.abs(((config.TOWERS and config.TOWERS.kingRange) or 0) - 27) <= EPSILON,
        "Princess Tower should stay off while a troop is at the bridge exit, then acquire it roughly two arena units into its lane; King range stays unchanged.",
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
    "EVOLUTION_SNAPSHOT|creeper_cycles=%d|portal_cycles=%d|mite_cycles=%d|guardian_cycles=%d|villager_cycles=%d|golem_cycles=%d|ghast_damage=%.1f|ghast_range=%.1f",
    cards.evolutionCycles("creeper") or -1,
    cards.evolutionCycles("nether_portal") or -1,
    cards.evolutionCycles("endermite") or -1,
    cards.evolutionCycles("guardian") or -1,
    cards.evolutionCycles("villager") or -1,
    cards.evolutionCycles("iron_golem") or -1,
    (cards.getInternalUnit("ghast") or {}).damage or -1,
    (cards.getInternalUnit("ghast") or {}).attackRange or -1
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

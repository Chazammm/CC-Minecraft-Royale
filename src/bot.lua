local config = require("config")
local cards = require("src.cards")
local arena = require("src.arena")
local Game = require("src.game")

local Bot = {}

local DIFFICULTIES = {
    easy = {
        think = 1.05,
        lateThink = 0.80,
        overtimeThink = 0.65,
        defenseOffset = 0.8,
        arrowThreshold = 3.4,
        saveForPower = false,
        minPlayScore = 2.8,
        cycleMemory = false,
        counterpush = false,
    },
    normal = {
        think = 0.65,
        lateThink = 0.42,
        overtimeThink = 0.32,
        defenseOffset = 0,
        arrowThreshold = 2.4,
        saveForPower = true,
        minPlayScore = 2.0,
        cycleMemory = true,
        counterpush = true,
    },
    hard = {
        think = 0.42,
        lateThink = 0.30,
        overtimeThink = 0.22,
        defenseOffset = -0.45,
        arrowThreshold = 1.9,
        saveForPower = true,
        minPlayScore = 1.5,
        cycleMemory = true,
        counterpush = true,
    },
}

local function difficultyConfig(bot)
    return DIFFICULTIES[bot.mode or "normal"] or DIFFICULTIES.normal
end

local NORMAL_DECK = {
    "zombie",
    "cannon",
    "arrows",
    "enderman",
    "snow_golem",
    "villager",
    "endermite",
    "blaze",
}

local ARROW_CARD = cards.get("arrows")
local ANVIL_CARD = cards.get("falling_anvil")

-- Static scoring tables are shared between decisions instead of being
-- allocated again for every card evaluation.
local POWER_PRIORITY = {
    iron_golem = 9,
    guardian = 8.5,
    villager = 8,
    witch = 7,
    evoker = 7.2,
    enderman = 6,
    creeper = 5.5,
    blaze = 5,
}

local OFFENSE_SCORE = {
    iron_golem = 7,
    witch = 6,
    evoker = 6.2,
    enderman = 5.5,
    blaze = 5,
    zombie = 4.5,
    wither_skeleton = 4.7,
    slime = 4.5,
    magma_cube = 4.7,
    spider = 4,
    wolf = 4,
    snow_golem = 3.5,
    skeleton = 3.5,
    bat_swarm = 4,
    endermite = 2,
    cannon = 1,
    pillager_outpost = 1.3,
    nether_portal = 5.0,
    guardian = 1.4,
}

local function otherPlayer(playerId)
    return playerId == 1 and 2 or 1
end

local function copyDeck(deck)
    local out = {}
    for i, id in ipairs(deck or NORMAL_DECK) do out[i] = id end
    return out
end

local function deckStyleSeed(deck)
    -- Stable bot personality derived only from deck contents/order. The same
    -- deck must make the same deterministic micro-decisions on P1 and P2.
    local hash = 17
    for i, cardId in ipairs(deck or NORMAL_DECK) do
        hash = (hash * 131 + i * 17) % 2147483647
        cardId = tostring(cardId or "")
        for j = 1, #cardId do
            hash = (hash * 33 + cardId:byte(j)) % 2147483647
        end
    end
    return hash
end

local function newMemory()
    return {
        observedPlays = {},
        observedHistoryCount = 0,
        knownCards = {},
        lastSeenPlayIndex = {},
        enemyPlayIndex = 0,
        enemyEmeralds = config.MATCH.emeraldStart,
    }
end

local function resetMemory(bot)
    bot.memory = newMemory()
end

local function observeOpponent(bot, state)
    if not bot.memory then resetMemory(bot) end

    local enemyId = otherPlayer(bot.playerId)
    local stats = state.stats and state.stats.players and state.stats.players[enemyId]
    if not stats then return end

    -- This is information a human could track from visible plays: which cards
    -- were used, how many cards have cycled since then, and an Emerald estimate.
    bot.memory.enemyEmeralds = math.max(
        0,
        math.min(
            config.MATCH.emeraldMax,
            config.MATCH.emeraldStart
                + (stats.emeraldGenerated or 0)
                - (stats.emeraldSpent or 0)
        )
    )

    local history = stats.playHistory or {}
    local seenHistory = bot.memory.observedHistoryCount or 0

    if #history > seenHistory then
        for i = seenHistory + 1, #history do
            local cardId = history[i]
            bot.memory.enemyPlayIndex = bot.memory.enemyPlayIndex + 1
            bot.memory.lastSeenPlayIndex[cardId] = bot.memory.enemyPlayIndex
            bot.memory.knownCards[cardId] = true
            bot.memory.observedPlays[cardId] =
                (bot.memory.observedPlays[cardId] or 0) + 1
        end
        bot.memory.observedHistoryCount = #history
    end
end

local function enemyCardKnown(bot, cardId)
    return bot.memory and bot.memory.knownCards[cardId] == true
end

local function enemyCardLikelyReady(bot, cardId)
    if not enemyCardKnown(bot, cardId) then return false end
    local last = bot.memory.lastSeenPlayIndex[cardId] or -999
    return (bot.memory.enemyPlayIndex - last) >= 4
end

local function enemyCardDefinitelyCycling(bot, cardId)
    if not enemyCardKnown(bot, cardId) then return false end
    local last = bot.memory.lastSeenPlayIndex[cardId] or -999
    local since = bot.memory.enemyPlayIndex - last
    return since >= 0 and since < 4
end

local function enemyCanAfford(bot, state, cardId)
    local card = cards.get(cardId)
    if not card then return false end

    local enemyId = otherPlayer(bot.playerId)
    local cost = Game.getCardPlayCost(state, enemyId, cardId) or card.cost
    return (bot.memory and bot.memory.enemyEmeralds or 0) + 0.25 >= cost
end

function Bot.defaultDeck()
    return copyDeck(NORMAL_DECK)
end

function Bot.prepare(bot, state)
    local player = state.players[bot.playerId]
    bot.styleSeed = deckStyleSeed(bot.deck)
    player.deck = copyDeck(bot.deck)

    player.hand = {}
    player.queue = {}
    for i = 1, 4 do player.hand[i] = player.deck[i] end
    for i = 5, #player.deck do table.insert(player.queue, player.deck[i]) end

    player.selectedSlot = nil
    player.ready = false
    player.rematch = false
    player.emeralds = config.MATCH.emeraldStart
    player.evolutionProgress = 0
    player.evolutionSelecting = false

    -- Bot Evolution choice must depend only on its own deck, not on a
    -- previous human selection left on that player slot in the lobby.
    player.evolutionCardId = nil
    for _, cardId in ipairs(player.deck) do
        if cards.isSelectable(cardId) and cards.hasEvolution(cardId) then
            player.evolutionCardId = cardId
            break
        end
    end

    bot.thinkTimer = 0.75
    bot.decisionCount = 0
    bot.actions = 0
    bot.lastAction = "NONE"
    resetMemory(bot)
end

local function handHasCard(player, cardId)
    for slot = 1, 4 do
        if player.hand[slot] == cardId then return true end
    end
    return false
end

-- A bot decision used to rescan state.entities independently for threat
-- analysis, Arrow targeting, Anvil targeting, towers, and Villagers. Build
-- those stable views once per decision while preserving the original entity
-- order, so every scorer sees exactly the same candidates as before.
local function buildDecisionView(state, playerId)
    local view = {
        enemyEntities = {},
        enemyUnits = {},
        enemyNonTowers = {},
        enemyTowers = {},
        ownTowers = {},
        ownVillagerCount = 0,
        ownTowerHp = 0,
        enemyTowerHp = 0,
        weakestEnemyPrincess = nil,
        weakestEnemyPrincessRatio = math.huge,
        counterpushLane = nil,
        counterpushScore = 0,
    }

    for _, entity in ipairs(state.entities) do
        if entity.alive then
            if entity.owner == playerId then
                if entity.kind == "tower" then
                    view.ownTowers[#view.ownTowers + 1] = entity
                    view.ownTowerHp = view.ownTowerHp
                        + entity.hp / math.max(1, entity.maxHp)
                elseif entity.kind == "unit" and not entity.passive then
                    local advanced =
                        (playerId == 1 and entity.y <= 112)
                        or (playerId == 2 and entity.y >= 48)
                    if advanced then
                        local hpRatio = (entity.hp or 0)
                            / math.max(1, entity.maxHp or 1)
                        local dps = 0
                        if entity.damage and entity.damage > 0 then
                            dps = entity.damage
                                / math.max(0.25, entity.attackCooldown or 1)
                        end
                        local score = hpRatio * ((entity.maxHp or 100) / 220)
                            + dps / 45
                        if score > view.counterpushScore then
                            view.counterpushScore = score
                            view.counterpushLane = entity.x < 50 and 25 or 75
                        end
                    end
                end

                if entity.sourceCardId == "villager" and entity.emeraldBoost then
                    view.ownVillagerCount = view.ownVillagerCount + 1
                end
            else
                view.enemyEntities[#view.enemyEntities + 1] = entity
                if entity.kind == "tower" then
                    view.enemyTowers[#view.enemyTowers + 1] = entity
                    local ratio = entity.hp / math.max(1, entity.maxHp)
                    view.enemyTowerHp = view.enemyTowerHp + ratio
                    if entity.towerType == "princess"
                        and ratio < view.weakestEnemyPrincessRatio
                    then
                        view.weakestEnemyPrincessRatio = ratio
                        view.weakestEnemyPrincess = entity
                    end
                else
                    view.enemyNonTowers[#view.enemyNonTowers + 1] = entity
                end
                if entity.kind == "unit" then
                    view.enemyUnits[#view.enemyUnits + 1] = entity
                end
            end
        end
    end

    return view
end

local function ownEmeraldBoost(state, playerId)
    local boost = 0
    for _, entity in ipairs(state.entities) do
        if entity.alive and entity.owner == playerId and entity.emeraldBoost then
            boost = boost + entity.emeraldBoost
        end
    end
    return boost
end

local function unitDps(entity)
    if not entity.damage or entity.damage <= 0 then return 0 end
    return entity.damage / math.max(0.25, entity.attackCooldown or 1)
end

local function nearestOwnTowerDistance(view, entity)
    local bestSq = math.huge
    for _, candidate in ipairs(view.ownTowers) do
        local dx = candidate.x - entity.x
        local dy = candidate.y - entity.y
        local d2 = dx * dx + dy * dy
        if d2 < bestSq then bestSq = d2 end
    end
    return bestSq < math.huge and math.sqrt(bestSq) or math.huge
end

local function isApproachingHalf(playerId, y)
    if playerId == 1 then
        return y >= config.ARENA.riverTop - 12
    end
    return y <= config.ARENA.riverBottom + 12
end

local function threatScore(state, playerId, entity, view)
    if not entity.alive or entity.owner == playerId or entity.kind ~= "unit" then return -math.huge end
    if entity.passive then return 0 end
    if not isApproachingHalf(playerId, entity.y) then return 0 end

    local score = (entity.maxHp or 100) / 260 + unitDps(entity) / 35
    local towerDistance = nearestOwnTowerDistance(view, entity)

    if towerDistance < math.huge then
        score = score + math.max(0, (65 - towerDistance) / 10)
    end

    if entity.sourceCardId == "iron_golem" then score = score + 4 end
    if entity.sourceCardId == "creeper" then score = score + 3.5 end
    if entity.sourceCardId == "enderman" then score = score + 2.5 end
    if entity.flying then score = score + 1 end

    return score
end

local function battlefield(state, playerId, view)
    local ctx = {
        enemies = view.enemyUnits,
        primaryThreat = nil,
        primaryThreatScore = 0,
        nearbyThreats = 0,
    }

    for _, entity in ipairs(view.enemyUnits) do
        local score = threatScore(state, playerId, entity, view)

        if score > 1.5 then ctx.nearbyThreats = ctx.nearbyThreats + 1 end
        if score > ctx.primaryThreatScore then
            ctx.primaryThreat = entity
            ctx.primaryThreatScore = score
        end
    end

    return ctx
end

local function bestArrowTarget(state, playerId, view)
    local arrow = ARROW_CARD
    local radius = arrow and arrow.spell and arrow.spell.radius or 12
    local radiusSq = radius * radius
    local best, bestScore = nil, 0

    for _, center in ipairs(view.enemyNonTowers) do
        local score = 0

        for _, target in ipairs(view.enemyNonTowers) do
            local dx = center.x - target.x
            local dy = center.y - target.y
            if dx * dx + dy * dy <= radiusSq then
                if target.sourceCardId == "villager" and target.emeraldBoost then
                    score = score + 9
                elseif target.name == "Bat Swarm" then
                    score = score + 1.4
                elseif target.name == "Endermite" or target.name == "Baby Zombie" then
                    score = score + 1.0
                elseif (target.hp or 9999) <= 185 then
                    score = score + 1.25
                else
                    score = score + 0.35
                end
            end
        end

        if score > bestScore then
            bestScore = score
            best = center
        end
    end

    local towerDamage = arrow and arrow.spell
        and (arrow.spell.damage or 0) * (arrow.spell.towerMultiplier or 1)
        or 0

    -- A spell that can end a tower should not be ignored just because there
    -- is no troop cluster nearby.
    for _, tower in ipairs(view.enemyTowers) do
        if towerDamage > 0
            and tower.hp <= towerDamage + 0.001
        then
            local score = tower.towerType == "king" and 80 or 35
            if state.overtime then score = score + 25 end

            if score > bestScore then
                bestScore = score
                best = tower
            end
        end
    end

    if best then
        return best.x, best.y, bestScore
    end
    return nil, nil, bestScore
end

local function botEntityById(state, id)
    if not id then return nil end
    if state.entityById then
        local entity = state.entityById[id]
        return entity and entity.alive and entity or nil
    end
    for _, entity in ipairs(state.entities) do
        if entity.id == id and entity.alive then return entity end
    end
    return nil
end

local function predictedAnvilPosition(state, entity, delay)
    local x, y = entity.x, entity.y

    if entity.kind ~= "unit"
        or entity.passive
        or (entity.moveSpeed or 0) <= 0
    then
        return x, y, 1.0
    end

    local speed = entity.moveSpeed or 0
    if entity.slowRemaining and entity.slowRemaining > 0 then
        speed = speed * (entity.slowFactor or 1)
    end
    speed = speed * (entity.globalMoveSpeedFactor or 1)

    local target = botEntityById(state, entity.targetId)
    if not target then
        -- Freshly spawned / currently untargeted troops still generally move
        -- toward the enemy side. Keep this fallback conservative because the
        -- real lane objective may acquire during the Anvil warning.
        local direction = entity.owner == 1 and -1 or 1
        y = y + direction * speed * delay * 0.55
        y = math.max(3, math.min(config.ARENA.height - 3, y))
        return x, y, 0.55
    end

    local attackRange = entity.attackRange or 0
    if entity.hybridAttack and not target.flying then
        attackRange = entity.hybridAttack.meleeRange or attackRange
    end

    local initialDx = target.x - x
    local initialDy = target.y - y
    local attackStop = attackRange + 0.75

    -- A troop already fighting is much more likely to still be near its
    -- current position than a marching troop. This is especially useful for
    -- tanks/buildings being stalled at a bridge or tower.
    if initialDx * initialDx + initialDy * initialDy <= attackStop * attackStop then
        return x, y, 0.90
    end

    -- Simulate several small pathing steps using the same bridge navigation
    -- helper as live gameplay. This predicts lateral movement toward bridges,
    -- unlike the old Y-only lead which frequently missed entire lanes.
    local probe = {
        x = x,
        y = y,
        owner = entity.owner,
        flying = entity.flying,
    }
    local steps = 6
    local stepTime = delay / steps

    for _ = 1, steps do
        local tx, ty = arena.navigationPoint(probe, target)
        local dx = tx - probe.x
        local dy = ty - probe.y
        local length = math.sqrt(dx * dx + dy * dy)

        if length < 0.001 then break end

        local distanceToTarget = math.sqrt(
            (target.x - probe.x)^2 + (target.y - probe.y)^2
        )
        local travelBudget = math.max(0, distanceToTarget - attackRange)
        if travelBudget <= 0 then break end

        local step = math.min(length, speed * stepTime, travelBudget)
        probe.x = probe.x + dx / length * step
        probe.y = probe.y + dy / length * step
    end

    return probe.x, probe.y, 0.82
end

local function anvilOverlapsPending(state, playerId, x, y, radius)
    local overlapRadius = radius * 1.25
    local overlapSq = overlapRadius * overlapRadius

    for _, pending in ipairs(state.pendingSpells or {}) do
        if pending.owner == playerId
            and pending.kind == "falling_anvil"
        then
            local dx = pending.x - x
            local dy = pending.y - y
            if dx * dx + dy * dy <= overlapSq then return true end
        end
    end
    return false
end

local function bestAnvilTarget(state, playerId, view)
    local card = ANVIL_CARD
    local spell = card and card.spell or nil
    if not spell then return nil, nil, 0 end

    local radius = spell.radius or 5.5
    local delay = spell.delay or 2.7
    local damage = spell.damage or 0
    local radiusSq = radius * radius
    local bestX, bestY, bestScore = nil, nil, 0

    local predicted = {}
    for _, entity in ipairs(view.enemyEntities) do
        local px, py, confidence = predictedAnvilPosition(state, entity, delay)
            predicted[entity.id] = {
                x = px,
                y = py,
                confidence = confidence,
        }
    end

    for _, center in ipairs(view.enemyEntities) do
        local centerPrediction = predicted[center.id]
            local cx = centerPrediction and centerPrediction.x or center.x
            local cy = centerPrediction and centerPrediction.y or center.y

            if not anvilOverlapsPending(state, playerId, cx, cy, radius) then
                local score = 0
                local hitCount = 0
                local reliableHits = 0
                local lethalTower = false

                for _, target in ipairs(view.enemyEntities) do
                    local targetPrediction = predicted[target.id]
                        local tx = targetPrediction and targetPrediction.x or target.x
                        local ty = targetPrediction and targetPrediction.y or target.y
                        local confidence = targetPrediction
                            and targetPrediction.confidence
                            or 1

                        local dx = cx - tx
                        local dy = cy - ty
                        if dx * dx + dy * dy <= radiusSq then
                            hitCount = hitCount + 1
                            if confidence >= 0.80 then
                                reliableHits = reliableHits + 1
                            end

                            local hitDamage = damage
                            if target.kind == "tower" then
                                hitDamage = hitDamage * (spell.towerMultiplier or 1)
                                score = score + math.min(hitDamage, target.hp) / 90
                                if target.hp <= hitDamage + 0.001 then
                                    lethalTower = true
                                    score = score
                                        + (target.towerType == "king" and 60 or 25)
                                end
                            else
                                score = score + math.min(hitDamage, target.hp or 0) / 100
                                if (target.hp or 0) <= hitDamage then
                                    score = score + 2.5
                                end
                                if target.sourceCardId == "villager" and target.emeraldBoost then
                                    score = score + 4
                                end
                                if target.kind == "building" or target.passive then
                                    score = score + 1.0
                                end
                            end
                    end
                end

                -- The old bot was happy to spend Anvil on a single moving
                -- tank, which explains sub-1.0 Hits/Play in benchmarks.
                -- Strongly prefer clusters; single-target casts are reserved
                -- for stable/high-value targets or a lethal Crown Tower.
                if hitCount >= 2 then
                    score = score + (hitCount - 1) * 3.0
                    if reliableHits >= 2 then score = score + 1.5 end
                elseif hitCount == 1 and not lethalTower then
                    local confidence = centerPrediction
                        and centerPrediction.confidence
                        or 1
                    if center.kind == "unit"
                        and not center.passive
                        and (center.moveSpeed or 0) > 0
                    then
                        score = score * (confidence >= 0.85 and 0.72 or 0.52)
                    end
                end

                if score > bestScore then
                    bestScore = score
                    bestX, bestY = cx, cy
                end
        end
    end

    return bestX, bestY, bestScore
end

local function backDirection(playerId)
    return playerId == 1 and 1 or -1
end

local function clampOwnPlacement(playerId, x, y)
    x = math.max(4, math.min(config.ARENA.width - 4, x))

    if playerId == 1 then
        y = math.max(config.ARENA.riverBottom + 4, math.min(config.ARENA.height - 4, y))
    else
        y = math.max(4, math.min(config.ARENA.riverTop - 4, y))
    end

    return x, y
end

local function guardianWaterPlacement(laneX)
    local left = (laneX or 50) < config.ARENA.width / 2
    local center = left
        and config.ARENA.bridgeCenters[1]
        or config.ARENA.bridgeCenters[#config.ARENA.bridgeCenters]
    local offset = (config.ARENA.bridgeHalfWidth or 7) + 3
    local x = left and (center + offset) or (center - offset)
    local y = (config.ARENA.riverTop + config.ARENA.riverBottom) / 2
    return x, y
end

local function defensivePlacement(bot, card, threat)
    local playerId = bot.playerId
    local back = backDirection(playerId)

    if card.id == "guardian" then
        return guardianWaterPlacement(threat and threat.x or 50)
    end

    if card.id == "cannon"
        or card.id == "pillager_outpost"
        or card.id == "endermite"
    then
        return clampOwnPlacement(playerId, 50, threat.y + back * 10)
    end

    if card.id == "snow_golem"
        or card.id == "skeleton"
        or card.id == "witch"
        or card.id == "evoker"
    then
        return clampOwnPlacement(playerId, threat.x, threat.y + back * 13)
    end

    return clampOwnPlacement(playerId, threat.x, threat.y + back * 7)
end

local function weakestEnemyPrincess(state, playerId, view)
    if view then return view.weakestEnemyPrincess end

    local enemy = otherPlayer(playerId)
    local best, bestRatio = nil, math.huge

    for _, entity in ipairs(state.entities) do
        if entity.alive
            and entity.owner == enemy
            and entity.kind == "tower"
            and entity.towerType == "princess"
        then
            local ratio = entity.hp / math.max(1, entity.maxHp)
            if ratio < bestRatio then
                bestRatio = ratio
                best = entity
            end
        end
    end

    return best
end

local function towerPressureState(state, playerId, view)
    local enemyId = otherPlayer(playerId)
    local ownHp, enemyHp = 0, 0

    if view then
        ownHp = view.ownTowerHp
        enemyHp = view.enemyTowerHp
    else
        for _, entity in ipairs(state.entities) do
            if entity.alive and entity.kind == "tower" then
                local ratio = entity.hp / math.max(1, entity.maxHp)
                if entity.owner == playerId then
                    ownHp = ownHp + ratio
                elseif entity.owner == enemyId then
                    enemyHp = enemyHp + ratio
                end
            end
        end
    end

    local crownDelta = (state.players[playerId].towersDestroyed or 0)
        - (state.players[enemyId].towersDestroyed or 0)

    return crownDelta * 2 + (ownHp - enemyHp) * 0.35
end

local function counterpushLane(state, playerId, view)
    if view then
        if view.counterpushScore >= 1.8 then
            return view.counterpushLane, view.counterpushScore
        end
        return nil, view.counterpushScore
    end

    local bestLane, bestScore = nil, 0

    for _, entity in ipairs(state.entities) do
        if entity.alive
            and entity.owner == playerId
            and entity.kind == "unit"
            and not entity.passive
        then
            local advanced =
                (playerId == 1 and entity.y <= 112)
                or (playerId == 2 and entity.y >= 48)
            if advanced then
                local hpRatio = (entity.hp or 0) / math.max(1, entity.maxHp or 1)
                local score = hpRatio * ((entity.maxHp or 100) / 220)
                    + unitDps(entity) / 45

                if score > bestScore then
                    bestScore = score
                    bestLane = entity.x < 50 and 25 or 75
                end
            end
        end
    end

    if bestScore >= 1.8 then return bestLane, bestScore end
    return nil, bestScore
end

local function offensivePlacement(bot, state, card, view)
    local playerId = bot.playerId
    local cfg = difficultyConfig(bot)
    local targetTower = weakestEnemyPrincess(state, playerId, view)
    local laneX = targetTower and targetTower.x
        or (((bot.decisionCount + (bot.styleSeed or 0)) % 2) == 0 and 25 or 75)
    local lateGame = state.overtime or (state.timeLeft and state.timeLeft <= 60)

    if cfg.counterpush and bot.mode ~= "easy" then
        local pushLane = counterpushLane(state, playerId, view)
        local targetCritical = targetTower
            and targetTower.hp / math.max(1, targetTower.maxHp) <= 0.30

        if pushLane and not targetCritical then
            laneX = pushLane
        end
    end

    if card.id == "guardian" then
        return guardianWaterPlacement(laneX)
    end

    if card.id == "villager" then
        local y = playerId == 1 and 142 or 18
        local x = (bot.decisionCount % 2 == 0) and 38 or 62
        return clampOwnPlacement(playerId, x, y)
    end

    if card.id == "iron_golem" or card.id == "witch" or card.id == "evoker" then
        local y
        if lateGame then
            y = playerId == 1 and 96 or 64
        else
            y = playerId == 1 and 116 or 44
        end
        return clampOwnPlacement(playerId, laneX, y)
    end

    local y
    if lateGame then
        y = playerId == 1 and 94 or 66
    else
        y = playerId == 1 and 103 or 57
    end
    return clampOwnPlacement(playerId, laneX, y)
end

local function shouldSaveForPowerCard(bot, state, ctx, arrowScore, cfg, view)
    cfg = cfg or difficultyConfig(bot)
    if not cfg.saveForPower then return false end

    local player = state.players[bot.playerId]
    local threat = ctx.primaryThreat
    local lateGame = state.overtime or (state.timeLeft and state.timeLeft <= 60)

    if threat and ctx.primaryThreatScore >= (lateGame and 4.5 or 3) then
        return false
    end
    if arrowScore and arrowScore >= cfg.arrowThreshold then
        return false
    end

    local bestCost = nil
    local bestPriority = -math.huge

    for slot = 1, 4 do
        local card = cards.get(player.hand[slot])
        if card then
            local playCost = Game.getCardPlayCost(
                state,
                bot.playerId,
                card.id
            ) or card.cost

            if player.emeralds < playCost then
                local gap = playCost - player.emeralds
                local p = POWER_PRIORITY[card.id] or 0

                if card.id == "villager"
                    and (lateGame or (view and view.ownVillagerCount > 0))
                then
                    p = -math.huge
                end

                -- Only wait a short time; never sit forever on a distant expensive card.
                if gap <= 2.25 and p > bestPriority then
                    bestPriority = p
                    bestCost = playCost
                end
            end
        end
    end

    return bestCost ~= nil
end

local function botDefenseThreshold(bot, state, cfg, view)
    cfg = cfg or difficultyConfig(bot)
    local lateGame = state.overtime or (state.timeLeft and state.timeLeft <= 60)
    local base = state.overtime and 5.0 or (lateGame and 4.2 or 3.0)

    if bot.mode == "hard" and lateGame then
        local advantage = towerPressureState(state, bot.playerId, view)
        if advantage > 0.35 then
            base = base - 0.75 -- protect the lead
        elseif advantage < -0.35 then
            base = base + 0.75 -- accept more risk and push
        end
    end

    return base + cfg.defenseOffset
end

local function scoreCard(
    bot,
    state,
    ctx,
    card,
    slot,
    arrowScore,
    anvilScore,
    cfg,
    defenseThreshold,
    view
)
    local player = state.players[bot.playerId]
    local playCost = Game.getCardPlayCost(state, bot.playerId, card.id) or card.cost
    if player.emeralds + 0.0001 < playCost then return -math.huge end

    cfg = cfg or difficultyConfig(bot)
    local score = 0
    local threat = ctx.primaryThreat
    local lateGame = state.overtime or (state.timeLeft and state.timeLeft <= 60)
    defenseThreshold = defenseThreshold or botDefenseThreshold(bot, state, cfg, view)
    local defending = threat and ctx.primaryThreatScore >= defenseThreshold

    -- Economy cards were effectively never tested because the bot kept
    -- spending cheap cards before reaching 7E. When safe, reserve the last
    -- couple of Emeralds so Villager gets a real chance to enter the match.

    if card.id == "arrows" then
        if arrowScore >= cfg.arrowThreshold then
            score = 8 + arrowScore
        else
            return -math.huge
        end
    elseif card.id == "falling_anvil" then
        local threshold = bot.mode == "hard" and 4.2 or 5.2
        if anvilScore >= threshold then
            score = 6.5 + anvilScore
        else
            return -math.huge
        end
    elseif card.id == "villager" then
        if defending or lateGame or (view and view.ownVillagerCount > 0) then
            return -math.huge
        end
        if player.emeralds >= 7 then
            score = 10 + (player.emeralds - 7) * 0.5
        end
    elseif defending then
        score = 3 + ctx.primaryThreatScore * 0.35

        -- Never answer a flying threat with a card that cannot actually
        -- interact with it. This covers both troops and defensive buildings.
        if threat.flying then
            if card.kind == "unit"
                and not card.unit.canAttackAir
                and not card.unit.passive
            then
                return -math.huge
            end

            if card.kind == "building"
                and not card.building.canAttackAir
            then
                return -math.huge
            end
        end

        -- Passive spawners are pressure/economy tools, not an immediate
        -- emergency answer to a push already threatening a tower.
        if card.kind == "building"
            and (card.building.passive or card.building.targetMode == "none")
        then
            return -math.huge
        end

        if card.id == "guardian" then
            local hp = threat.maxHp or threat.hp or 0
            if hp >= 900 then
                score = score + 9
            elseif hp >= 500 then
                score = score + 6
            else
                score = score + 2
            end

            if threat.targetMode == "buildings" or threat.name == "Iron Golem" then
                score = score + 4
            end
        elseif card.id == "cannon" and not threat.flying then
            score = score + 4
            if threat.targetMode == "buildings" or threat.name == "Iron Golem" then score = score + 5 end
        elseif card.id == "pillager_outpost" then
            score = score + (threat.flying and 5.0 or 3.2)
            if threat.targetMode == "buildings" or threat.name == "Iron Golem" then
                score = score + 3.0
            end
        elseif card.id == "endermite" and not threat.flying then
            score = score + 3
            if threat.name == "Iron Golem" or threat.name == "Creeper" then score = score + 4 end
        elseif card.id == "enderman" and (threat.attackRange or 0) >= 10 then
            score = score + 5
        elseif card.id == "snow_golem" then
            score = score + (threat.flying and 5 or 4)
        elseif card.id == "skeleton" then
            score = score + (threat.flying and 4.5 or 3)
        elseif card.id == "witch" then
            score = score + (threat.flying and 4.5 or 3)
        elseif card.id == "evoker" and not threat.flying then
            score = score + (ctx.nearbyThreats >= 2 and 5.0 or 3.2)
        elseif card.id == "bat_swarm" and not threat.canAttackAir then
            score = score + 5
        elseif card.id == "blaze" then
            score = score + (threat.flying and 4 or 2)
        elseif card.id == "creeper" and ctx.nearbyThreats >= 2 then
            score = score + 5
        elseif card.id == "spider" or card.id == "wolf" then
            score = score + ((threat.attackRange or 0) >= 10 and 4 or 2)
        elseif card.id == "zombie" or card.id == "slime" then
            score = score + 2
        end
    else
        score = OFFENSE_SCORE[card.id] or 2
        if lateGame and card.id ~= "cannon" and card.id ~= "villager" then
            score = score + (state.overtime and 4.5 or 3.0)
        end
    end

    if cfg.cycleMemory and bot.mode == "hard" and not defending then
        -- Exploit a counter which was just used and cannot be back in the
        -- opponent's four-card hand yet.
        if card.id == "bat_swarm" then
            if enemyCardDefinitelyCycling(bot, "arrows") then
                score = score + 3.0
            elseif enemyCardLikelyReady(bot, "arrows")
                and enemyCanAfford(bot, state, "arrows")
            then
                score = score - 3.5
            end
        elseif card.id == "iron_golem" then
            if enemyCardDefinitelyCycling(bot, "cannon") then
                score = score + 2.2
            elseif enemyCardLikelyReady(bot, "cannon")
                and enemyCanAfford(bot, state, "cannon")
            then
                score = score - 2.0
            end
        end

        -- If a known dangerous tank is back in cycle and affordable, avoid
        -- throwing away the best cheap pull before it appears.
        if (card.id == "cannon" or card.id == "endermite")
            and enemyCardLikelyReady(bot, "iron_golem")
            and enemyCanAfford(bot, state, "iron_golem")
        then
            score = score - 2.8
        end
    end

    score = score - playCost * 0.12
    score = score + (((bot.decisionCount * 7 + slot * 3 + (bot.styleSeed or 0)) % 5) * 0.08)
    return score
end

local function choosePlay(bot, state)
    local cfg = difficultyConfig(bot)

    -- EASY intentionally misses some decision windows so it feels human and
    -- gives the player time to exploit openings.
    if bot.mode == "easy" and bot.decisionCount % 4 == 0 then
        return nil
    end

    local player = state.players[bot.playerId]
    local view = buildDecisionView(state, bot.playerId)
    local ctx = battlefield(state, bot.playerId, view)

    local hasArrows = handHasCard(player, "arrows")
    local saveNeedsArrowScore = cfg.saveForPower
    if saveNeedsArrowScore then
        local lateGame = state.overtime or (state.timeLeft and state.timeLeft <= 60)
        if ctx.primaryThreat
            and ctx.primaryThreatScore >= (lateGame and 4.5 or 3)
        then
            -- shouldSaveForPowerCard returns before consulting arrowScore in
            -- this exact situation.
            saveNeedsArrowScore = false
        end
    end

    local arrowX, arrowY, arrowScore = nil, nil, 0
    local playableArrows = hasArrows
    if playableArrows and not saveNeedsArrowScore then
        local arrowCost = Game.getCardPlayCost(
            state,
            bot.playerId,
            "arrows"
        ) or (ARROW_CARD and ARROW_CARD.cost) or math.huge
        playableArrows = player.emeralds + 0.0001 >= arrowCost
    end
    if saveNeedsArrowScore or playableArrows then
        arrowX, arrowY, arrowScore = bestArrowTarget(state, bot.playerId, view)
    end

    -- Anvil prediction is one of the most expensive decision passes. Its
    -- result is only consumed when Falling Anvil is both in hand and
    -- affordable; scoreCard rejects it before reading anvilScore otherwise.
    local anvilX, anvilY, anvilScore = nil, nil, 0
    if handHasCard(player, "falling_anvil") then
        local anvilCost = Game.getCardPlayCost(
            state,
            bot.playerId,
            "falling_anvil"
        ) or (ANVIL_CARD and ANVIL_CARD.cost) or math.huge
        if player.emeralds + 0.0001 >= anvilCost then
            anvilX, anvilY, anvilScore = bestAnvilTarget(
                state,
                bot.playerId,
                view
            )
        end
    end

    if shouldSaveForPowerCard(bot, state, ctx, arrowScore, cfg, view) then
        return nil
    end

    local defenseThreshold = botDefenseThreshold(bot, state, cfg, view)
    local best = nil
    local bestScore = -math.huge

    for slot = 1, 4 do
        local card = cards.get(player.hand[slot])
        if card then
            local score = scoreCard(
                bot,
                state,
                ctx,
                card,
                slot,
                arrowScore,
                anvilScore,
                cfg,
                defenseThreshold,
                view
            )
            if score > bestScore then
                bestScore = score
                best = { slot = slot, card = card }
            end
        end
    end

    if not best or bestScore < cfg.minPlayScore then return nil end

    if best.card.id == "arrows" and arrowX then
        best.x, best.y = arrowX, arrowY
    elseif best.card.id == "falling_anvil" and anvilX then
        best.x, best.y = anvilX, anvilY
    elseif ctx.primaryThreat
        and ctx.primaryThreatScore >= defenseThreshold
    then
        best.x, best.y = defensivePlacement(bot, best.card, ctx.primaryThreat)
    else
        best.x, best.y = offensivePlacement(bot, state, best.card, view)
    end

    return best
end

local function play(bot, state, choice)
    local ok = Game.playCardFromSlot(
        state,
        bot.playerId,
        choice.slot,
        choice.x,
        choice.y
    )

    if not ok then return false end

    bot.actions = bot.actions + 1
    bot.lastAction = choice.card.name
    bot.lastX = choice.x
    bot.lastY = choice.y
    bot.thinkTimer = 0.85 + ((bot.actions * 13 + (bot.styleSeed or 0)) % 5) * 0.07
    return true
end

function Bot.new(playerId, deck)
    return {
        playerId = playerId or 2,
        enabled = false,
        mode = "normal",
        deck = copyDeck(deck),
        styleSeed = deckStyleSeed(deck),
        thinkTimer = 0.75,
        decisionCount = 0,
        actions = 0,
        lastAction = "NONE",
        memory = newMemory(),
    }
end

function Bot.setDifficulty(bot, difficulty)
    difficulty = string.lower(tostring(difficulty or "normal"))
    if not DIFFICULTIES[difficulty] then return false end
    bot.mode = difficulty
    return true
end

function Bot.reset(bot, state)
    Bot.prepare(bot, state)
end

function Bot.beginMatch(bot)
    bot.thinkTimer = 0.75
    bot.decisionCount = 0
    bot.actions = 0
    bot.lastAction = "NONE"
    resetMemory(bot)
end

function Bot.setEnabled(bot, state, enabled, prepare)
    bot.enabled = enabled == true
    if bot.enabled and prepare ~= false then
        Bot.prepare(bot, state)
    end
end

function Bot.toggle(bot, state)
    Bot.setEnabled(bot, state, not bot.enabled)
end

function Bot.update(bot, state, dt)
    if not bot.enabled then return end

    local playable = state.phase == "battle" or state.phase == "admin"
    if not playable then return end
    if state.phase == "battle" and state.tiebreaker then return end
    if state.phase == "admin" and state.adminPaused then return end

    if state.phase == "battle" and not state.headlessSimulation then
        observeOpponent(bot, state)
    end

    -- Normal battles already generate Emeralds inside Game.update().
    -- Admin sandbox does not, so give the bot the same economy there.
    if state.phase == "admin" then
        local player = state.players[bot.playerId]
        local boost = ownEmeraldBoost(state, bot.playerId)
        local rate = config.MATCH.emeraldPerSecond * (1 + boost)
        player.emeralds = math.min(player.maxEmeralds, player.emeralds + rate * dt)
    end

    bot.thinkTimer = bot.thinkTimer - dt
    if bot.thinkTimer > 0 then return end

    -- Benchmark states only need opponent memory at decision time. Catching up
    -- the chronological play history here produces the same decision input
    -- while avoiding two observer passes on every 0.10s simulation tick.
    if state.phase == "battle" and state.headlessSimulation then
        observeOpponent(bot, state)
    end

    bot.decisionCount = bot.decisionCount + 1
    local cfg = difficultyConfig(bot)
    local baseThink = state.overtime and cfg.overtimeThink
        or ((state.timeLeft and state.timeLeft <= 60) and cfg.lateThink or cfg.think)

    local jitter = bot.mode == "hard" and 0.035 or (bot.mode == "easy" and 0.11 or 0.08)
    bot.thinkTimer = baseThink + ((bot.decisionCount * 11 + (bot.styleSeed or 0)) % 6) * jitter

    local choice = choosePlay(bot, state)
    if choice then play(bot, state, choice) end
end

function Bot.debugCounterpushLane(state, playerId)
    local view = buildDecisionView(state, playerId)
    return counterpushLane(state, playerId, view)
end

function Bot.status(bot, state)
    local player = state.players[bot.playerId]
    return {
        enabled = bot.enabled,
        mode = bot.mode,
        playerId = bot.playerId,
        emeralds = player and player.emeralds or 0,
        actions = bot.actions,
        lastAction = bot.lastAction,
        enemyEmeralds = bot.memory and bot.memory.enemyEmeralds or 0,
        knownCards = bot.memory and bot.memory.knownCards or {},
        enemyPlayIndex = bot.memory and bot.memory.enemyPlayIndex or 0,
    }
end

return Bot

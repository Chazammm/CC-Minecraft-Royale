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

local function otherPlayer(playerId)
    return playerId == 1 and 2 or 1
end

local function copyDeck(deck)
    local out = {}
    for i, id in ipairs(deck or NORMAL_DECK) do out[i] = id end
    return out
end

local function newMemory()
    return {
        observedPlays = {},
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

    for cardId, cardStats in pairs(stats.cards or {}) do
        local plays = cardStats.plays or 0
        local seen = bot.memory.observedPlays[cardId] or 0

        if plays > seen then
            for _ = seen + 1, plays do
                bot.memory.enemyPlayIndex = bot.memory.enemyPlayIndex + 1
                bot.memory.lastSeenPlayIndex[cardId] = bot.memory.enemyPlayIndex
                bot.memory.knownCards[cardId] = true
            end
            bot.memory.observedPlays[cardId] = plays
        end
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

local function enemyCanAfford(bot, cardId)
    local card = cards.get(cardId)
    if not card then return false end
    return (bot.memory and bot.memory.enemyEmeralds or 0) + 0.25 >= card.cost
end

function Bot.defaultDeck()
    return copyDeck(NORMAL_DECK)
end

function Bot.prepare(bot, state)
    local player = state.players[bot.playerId]
    player.deck = copyDeck(bot.deck)

    player.hand = {}
    player.queue = {}
    for i = 1, 4 do player.hand[i] = player.deck[i] end
    for i = 5, #player.deck do table.insert(player.queue, player.deck[i]) end

    player.selectedSlot = nil
    player.ready = false
    player.rematch = false
    player.emeralds = config.MATCH.emeraldStart

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

local function ownedVillagerCount(state, playerId)
    local count = 0
    for _, entity in ipairs(state.entities) do
        if entity.alive and entity.owner == playerId and entity.name == "Villager" then
            count = count + 1
        end
    end
    return count
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

local function nearestOwnTowerDistance(state, playerId, entity)
    local best = math.huge
    for _, candidate in ipairs(state.entities) do
        if candidate.alive and candidate.owner == playerId and candidate.kind == "tower" then
            local dx = candidate.x - entity.x
            local dy = candidate.y - entity.y
            local d = math.sqrt(dx * dx + dy * dy)
            if d < best then best = d end
        end
    end
    return best
end

local function isApproachingHalf(playerId, y)
    if playerId == 1 then
        return y >= config.ARENA.riverTop - 12
    end
    return y <= config.ARENA.riverBottom + 12
end

local function threatScore(state, playerId, entity)
    if not entity.alive or entity.owner == playerId or entity.kind ~= "unit" then return -math.huge end
    if entity.passive then return 0 end
    if not isApproachingHalf(playerId, entity.y) then return 0 end

    local score = (entity.maxHp or 100) / 260 + unitDps(entity) / 35
    local towerDistance = nearestOwnTowerDistance(state, playerId, entity)

    if towerDistance < math.huge then
        score = score + math.max(0, (65 - towerDistance) / 10)
    end

    if entity.name == "Iron Golem" then score = score + 4 end
    if entity.name == "Creeper" then score = score + 3.5 end
    if entity.name == "Enderman" then score = score + 2.5 end
    if entity.flying then score = score + 1 end

    return score
end

local function battlefield(state, playerId)
    local ctx = {
        enemies = {},
        primaryThreat = nil,
        primaryThreatScore = 0,
        nearbyThreats = 0,
    }

    for _, entity in ipairs(state.entities) do
        if entity.alive and entity.owner ~= playerId and entity.kind == "unit" then
            table.insert(ctx.enemies, entity)
            local score = threatScore(state, playerId, entity)

            if score > 1.5 then ctx.nearbyThreats = ctx.nearbyThreats + 1 end
            if score > ctx.primaryThreatScore then
                ctx.primaryThreat = entity
                ctx.primaryThreatScore = score
            end
        end
    end

    return ctx
end

local function bestArrowTarget(state, playerId)
    local arrow = cards.get("arrows")
    local radius = arrow and arrow.spell and arrow.spell.radius or 12
    local best, bestScore = nil, 0

    for _, center in ipairs(state.entities) do
        if center.alive and center.owner ~= playerId and center.kind ~= "tower" then
            local score = 0

            for _, target in ipairs(state.entities) do
                if target.alive and target.owner ~= playerId and target.kind ~= "tower" then
                    local dx = center.x - target.x
                    local dy = center.y - target.y
                    if math.sqrt(dx * dx + dy * dy) <= radius then
                        if target.name == "Villager" then
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
            end

            if score > bestScore then
                bestScore = score
                best = center
            end
        end
    end

    local towerDamage = arrow and arrow.spell
        and (arrow.spell.damage or 0) * (arrow.spell.towerMultiplier or 1)
        or 0

    -- A spell that can end a tower should not be ignored just because there
    -- is no troop cluster nearby.
    for _, tower in ipairs(state.entities) do
        if tower.alive
            and tower.owner ~= playerId
            and tower.kind == "tower"
            and towerDamage > 0
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

local function bestAnvilTarget(state, playerId)
    local card = cards.get("falling_anvil")
    local spell = card and card.spell or nil
    if not spell then return nil, nil, 0 end

    local radius = spell.radius or 5.5
    local delay = spell.delay or 3
    local damage = spell.damage or 0
    local bestX, bestY, bestScore = nil, nil, 0

    for _, center in ipairs(state.entities) do
        if center.alive
            and center.owner ~= playerId
            and not center.flying
        then
            local cx, cy = center.x, center.y

            -- Lead moving ground troops roughly toward the bot's side. This
            -- turns the 3-second warning into an actual timing challenge.
            if center.kind == "unit" and (center.moveSpeed or 0) > 0 then
                local direction = playerId == 1 and 1 or -1
                cy = cy + direction * (center.moveSpeed or 0) * delay * 0.80
                cy = math.max(3, math.min(config.ARENA.height - 3, cy))
            end

            local score = 0
            for _, target in ipairs(state.entities) do
                if target.alive
                    and target.owner ~= playerId
                    and not target.flying
                then
                    local tx, ty = target.x, target.y
                    if target.kind == "unit" and (target.moveSpeed or 0) > 0 then
                        local direction = playerId == 1 and 1 or -1
                        ty = ty + direction * (target.moveSpeed or 0) * delay * 0.80
                        ty = math.max(3, math.min(config.ARENA.height - 3, ty))
                    end

                    local d = math.sqrt((cx - tx)^2 + (cy - ty)^2)
                    if d <= radius then
                        local hitDamage = damage
                        if target.kind == "tower" then
                            hitDamage = hitDamage * (spell.towerMultiplier or 1)
                            score = score + math.min(hitDamage, target.hp) / 90
                            if target.hp <= hitDamage + 0.001 then
                                score = score + (target.towerType == "king" and 60 or 25)
                            end
                        else
                            score = score + math.min(hitDamage, target.hp or 0) / 100
                            if (target.hp or 0) <= hitDamage then score = score + 2.5 end
                            if target.name == "Villager" then score = score + 4 end
                        end
                    end
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

local function defensivePlacement(bot, card, threat)
    local playerId = bot.playerId
    local back = backDirection(playerId)

    if card.id == "cannon" or card.id == "endermite" then
        return clampOwnPlacement(playerId, 50, threat.y + back * 10)
    end

    if card.id == "snow_golem" or card.id == "skeleton" or card.id == "witch" then
        return clampOwnPlacement(playerId, threat.x, threat.y + back * 13)
    end

    return clampOwnPlacement(playerId, threat.x, threat.y + back * 7)
end

local function weakestEnemyPrincess(state, playerId)
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

local function towerPressureState(state, playerId)
    local enemyId = otherPlayer(playerId)
    local ownHp, enemyHp = 0, 0

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

    local crownDelta = (state.players[playerId].towersDestroyed or 0)
        - (state.players[enemyId].towersDestroyed or 0)

    return crownDelta * 2 + (ownHp - enemyHp) * 0.35
end

local function counterpushLane(state, playerId)
    local bestLane, bestScore = nil, 0

    for _, entity in ipairs(state.entities) do
        if entity.alive
            and entity.owner == playerId
            and entity.kind == "unit"
            and not entity.passive
        then
            local advanced = playerId == 1 and entity.y <= 112 or entity.y >= 48
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

local function offensivePlacement(bot, state, card)
    local playerId = bot.playerId
    local cfg = difficultyConfig(bot)
    local targetTower = weakestEnemyPrincess(state, playerId)
    local laneX = targetTower and targetTower.x
        or (((bot.decisionCount + bot.playerId) % 2) == 0 and 25 or 75)
    local lateGame = state.overtime or (state.timeLeft and state.timeLeft <= 60)

    if cfg.counterpush and bot.mode ~= "easy" then
        local pushLane = counterpushLane(state, playerId)
        local targetCritical = targetTower
            and targetTower.hp / math.max(1, targetTower.maxHp) <= 0.30

        if pushLane and not targetCritical then
            laneX = pushLane
        end
    end

    if card.id == "villager" then
        local y = playerId == 1 and 142 or 18
        local x = (bot.decisionCount % 2 == 0) and 38 or 62
        return clampOwnPlacement(playerId, x, y)
    end

    if card.id == "iron_golem" or card.id == "witch" then
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

local function shouldSaveForPowerCard(bot, state, ctx, arrowScore)
    local cfg = difficultyConfig(bot)
    if not cfg.saveForPower then return false end

    local player = state.players[bot.playerId]
    local threat = ctx.primaryThreat
    local lateGame = state.overtime or (state.timeLeft and state.timeLeft <= 60)

    if threat and ctx.primaryThreatScore >= (lateGame and 4.5 or 3) then
        return false
    end
    if arrowScore and arrowScore >= difficultyConfig(bot).arrowThreshold then
        return false
    end

    local bestCost = nil
    local bestPriority = -math.huge

    local priority = {
        iron_golem = 9,
        villager = lateGame and -math.huge or 8,
        witch = 7,
        enderman = 6,
        creeper = 5.5,
        blaze = 5,
    }

    for slot = 1, 4 do
        local card = cards.get(player.hand[slot])
        if card and player.emeralds < card.cost then
            local gap = card.cost - player.emeralds
            local p = priority[card.id] or 0

            if card.id == "villager" and ownedVillagerCount(state, bot.playerId) > 0 then
                p = -math.huge
            end

            -- Only wait a short time; never sit forever on a distant expensive card.
            if gap <= 2.25 and p > bestPriority then
                bestPriority = p
                bestCost = card.cost
            end
        end
    end

    return bestCost ~= nil
end

local function botDefenseThreshold(bot, state)
    local cfg = difficultyConfig(bot)
    local lateGame = state.overtime or (state.timeLeft and state.timeLeft <= 60)
    local base = state.overtime and 5.0 or (lateGame and 4.2 or 3.0)

    if bot.mode == "hard" and lateGame then
        local advantage = towerPressureState(state, bot.playerId)
        if advantage > 0.35 then
            base = base - 0.75 -- protect the lead
        elseif advantage < -0.35 then
            base = base + 0.75 -- accept more risk and push
        end
    end

    return base + cfg.defenseOffset
end

local function scoreCard(bot, state, ctx, card, slot, arrowScore, anvilScore)
    local player = state.players[bot.playerId]
    if player.emeralds + 0.0001 < card.cost then return -math.huge end

    local cfg = difficultyConfig(bot)
    local score = 0
    local threat = ctx.primaryThreat
    local lateGame = state.overtime or (state.timeLeft and state.timeLeft <= 60)
    local defenseThreshold = botDefenseThreshold(bot, state)
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
        if defending or lateGame or ownedVillagerCount(state, bot.playerId) > 0 then
            return -math.huge
        end
        if player.emeralds >= 7 then
            score = 10 + (player.emeralds - 7) * 0.5
        end
    elseif defending then
        score = 3 + ctx.primaryThreatScore * 0.35

        -- Never answer a flying threat with a troop that cannot actually hit it.
        if threat.flying
            and card.kind == "unit"
            and not card.unit.canAttackAir
            and not card.unit.passive
        then
            return -math.huge
        end

        if card.id == "cannon" and not threat.flying then
            score = score + 4
            if threat.targetMode == "buildings" or threat.name == "Iron Golem" then score = score + 5 end
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
        local offense = {
            iron_golem = 7,
            witch = 6,
            enderman = 5.5,
            blaze = 5,
            zombie = 4.5,
            slime = 4.5,
            spider = 4,
            wolf = 4,
            snow_golem = 3.5,
            skeleton = 3.5,
            bat_swarm = 4,
            endermite = 2,
            cannon = 1,
            nether_portal = 5.0,
        }
        score = offense[card.id] or 2
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
                and enemyCanAfford(bot, "arrows")
            then
                score = score - 3.5
            end
        elseif card.id == "iron_golem" then
            if enemyCardDefinitelyCycling(bot, "cannon") then
                score = score + 2.2
            elseif enemyCardLikelyReady(bot, "cannon")
                and enemyCanAfford(bot, "cannon")
            then
                score = score - 2.0
            end
        end

        -- If a known dangerous tank is back in cycle and affordable, avoid
        -- throwing away the best cheap pull before it appears.
        if (card.id == "cannon" or card.id == "endermite")
            and enemyCardLikelyReady(bot, "iron_golem")
            and enemyCanAfford(bot, "iron_golem")
        then
            score = score - 2.8
        end
    end

    score = score - card.cost * 0.12
    score = score + (((bot.decisionCount * 7 + slot * 3 + bot.playerId) % 5) * 0.08)
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
    local ctx = battlefield(state, bot.playerId)
    local arrowX, arrowY, arrowScore = bestArrowTarget(state, bot.playerId)
    local anvilX, anvilY, anvilScore = bestAnvilTarget(state, bot.playerId)

    if shouldSaveForPowerCard(bot, state, ctx, arrowScore) then
        return nil
    end

    local best = nil
    local bestScore = -math.huge

    for slot = 1, 4 do
        local card = cards.get(player.hand[slot])
        if card then
            local score = scoreCard(bot, state, ctx, card, slot, arrowScore, anvilScore)
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
        and ctx.primaryThreatScore >= botDefenseThreshold(bot, state)
    then
        best.x, best.y = defensivePlacement(bot, best.card, ctx.primaryThreat)
    else
        best.x, best.y = offensivePlacement(bot, state, best.card)
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
    bot.thinkTimer = 0.85 + ((bot.actions * 13 + bot.playerId) % 5) * 0.07
    return true
end

function Bot.new(playerId, deck)
    return {
        playerId = playerId or 2,
        enabled = false,
        mode = "normal",
        deck = copyDeck(deck),
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
    if state.phase == "admin" and state.adminPaused then return end

    if state.phase == "battle" then
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

    bot.decisionCount = bot.decisionCount + 1
    local cfg = difficultyConfig(bot)
    local baseThink = state.overtime and cfg.overtimeThink
        or ((state.timeLeft and state.timeLeft <= 60) and cfg.lateThink or cfg.think)

    local jitter = bot.mode == "hard" and 0.035 or (bot.mode == "easy" and 0.11 or 0.08)
    bot.thinkTimer = baseThink + ((bot.decisionCount * 11 + bot.playerId) % 6) * jitter

    local choice = choosePlay(bot, state)
    if choice then play(bot, state, choice) end
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

local config = require("config")
local cards = require("src.cards")
local arena = require("src.arena")
local Game = require("src.game")

local Bot = {}

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

    if best and bestScore >= 2.4 then
        return best.x, best.y, bestScore
    end
    return nil, nil, bestScore
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

local function offensivePlacement(bot, state, card)
    local playerId = bot.playerId
    local targetTower = weakestEnemyPrincess(state, playerId)
    local laneX = targetTower and targetTower.x
        or (((bot.decisionCount + bot.playerId) % 2) == 0 and 25 or 75)
    local lateGame = state.overtime or (state.timeLeft and state.timeLeft <= 60)

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

local function scoreCard(bot, state, ctx, card, slot, arrowScore)
    local player = state.players[bot.playerId]
    if player.emeralds + 0.0001 < card.cost then return -math.huge end

    local score = 0
    local threat = ctx.primaryThreat
    local defending = threat and ctx.primaryThreatScore >= 3
    local lateGame = state.overtime or (state.timeLeft and state.timeLeft <= 60)

    -- Economy cards were effectively never tested because the bot kept
    -- spending cheap cards before reaching 7E. When safe, reserve the last
    -- couple of Emeralds so Villager gets a real chance to enter the match.
    local savingForVillager = not defending
        and not lateGame
        and ownedVillagerCount(state, bot.playerId) == 0
        and handHasCard(player, "villager")
        and player.emeralds >= 5
        and player.emeralds < 7

    if savingForVillager and card.id ~= "villager" then
        return -math.huge
    end

    if card.id == "arrows" then
        if arrowScore >= 2.4 then
            score = 8 + arrowScore
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

        if card.id == "cannon" and not threat.flying then
            score = score + 4
            if threat.targetMode == "buildings" or threat.name == "Iron Golem" then score = score + 5 end
        elseif card.id == "endermite" and not threat.flying then
            score = score + 3
            if threat.name == "Iron Golem" or threat.name == "Creeper" then score = score + 4 end
        elseif card.id == "enderman" and (threat.attackRange or 0) >= 10 then
            score = score + 5
        elseif card.id == "snow_golem" and not threat.flying then
            score = score + 4
        elseif card.id == "skeleton" and not threat.flying then
            score = score + 3
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
        }
        score = offense[card.id] or 2
        if lateGame and card.id ~= "cannon" and card.id ~= "villager" then
            score = score + 2.5
        end
    end

    score = score - card.cost * 0.12
    score = score + (((bot.decisionCount * 7 + slot * 3 + bot.playerId) % 5) * 0.08)
    return score
end

local function choosePlay(bot, state)
    local player = state.players[bot.playerId]
    local ctx = battlefield(state, bot.playerId)
    local arrowX, arrowY, arrowScore = bestArrowTarget(state, bot.playerId)

    local best = nil
    local bestScore = -math.huge

    for slot = 1, 4 do
        local card = cards.get(player.hand[slot])
        if card then
            local score = scoreCard(bot, state, ctx, card, slot, arrowScore)
            if score > bestScore then
                bestScore = score
                best = { slot = slot, card = card }
            end
        end
    end

    if not best or bestScore < 2 then return nil end

    if best.card.id == "arrows" and arrowX then
        best.x, best.y = arrowX, arrowY
    elseif ctx.primaryThreat and ctx.primaryThreatScore >= 3 then
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
        mode = "NORMAL",
        deck = copyDeck(deck),
        thinkTimer = 0.75,
        decisionCount = 0,
        actions = 0,
        lastAction = "NONE",
    }
end

function Bot.reset(bot, state)
    Bot.prepare(bot, state)
end

function Bot.beginMatch(bot)
    bot.thinkTimer = 0.75
    bot.decisionCount = 0
    bot.actions = 0
    bot.lastAction = "NONE"
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
    local baseThink = (state.overtime or (state.timeLeft and state.timeLeft <= 60)) and 0.45 or 0.65
    bot.thinkTimer = baseThink + ((bot.decisionCount * 11 + bot.playerId) % 6) * 0.08

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
    }
end

return Bot

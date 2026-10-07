local config = require("config")
local util = require("src.util")
local cards = require("src.cards")
local arena = require("src.arena")

local Game = {}

local function otherPlayer(playerId)
    return playerId == 1 and 2 or 1
end

local function newPlayer(playerId)
    return {
        id = playerId,
        ready = false,
        rematch = false,
        emeralds = config.MATCH.emeraldStart,
        maxEmeralds = config.MATCH.emeraldMax,
        deck = cards.defaultDeck(),
        hand = {},
        queue = {},
        selectedSlot = nil,
        towersDestroyed = 0,
        feedback = nil,
        feedbackTime = 0,
    }
end

local function resetDeck(player)
    player.deck = cards.defaultDeck()
    player.hand = {}
    player.queue = {}

    for i = 1, 4 do
        player.hand[i] = player.deck[i]
    end
    for i = 5, #player.deck do
        table.insert(player.queue, player.deck[i])
    end

    player.selectedSlot = nil
end

local function setFeedback(player, text, duration)
    player.feedback = text
    player.feedbackTime = duration or 1.2
end

local function emitSound(state, name, volume, pitch)
    if state.sound then
        state.sound(name, volume or 1, pitch or 1)
    end
end

local function addEffect(state, kind, x, y, radius, ttl, owner)
    local lifetime = ttl or 0.3
    table.insert(state.effects, {
        kind = kind,
        x = x,
        y = y,
        radius = radius or 1,
        ttl = lifetime,
        duration = lifetime,
        owner = owner,
    })
end

local function makeBaseEntity(state, owner, kind, x, y)
    local entity = {
        id = state.nextEntityId,
        owner = owner,
        kind = kind,
        x = x,
        y = y,
        alive = true,
        targetId = nil,
        attackCooldownLeft = 0,
    }
    state.nextEntityId = state.nextEntityId + 1
    return entity
end

local function spawnUnitFromStats(state, owner, stats, x, y, name, icon, color)
    local entity = makeBaseEntity(state, owner, "unit", x, y)

    for k, v in pairs(util.deepcopy(stats)) do
        entity[k] = v
    end

    entity.name = name or "Unit"
    entity.icon = icon or "?"
    entity.color = color or colors.white
    entity.maxHp = entity.maxHp or 100
    entity.hp = entity.maxHp
    entity.moveSpeed = entity.moveSpeed or 5
    entity.attackRange = entity.attackRange or 2
    entity.attackCooldown = entity.attackCooldown or 1
    entity.aggroRange = entity.aggroRange or 25
    entity.targetMode = entity.targetMode or "any"
    entity.canAttackAir = entity.canAttackAir == true
    entity.flying = entity.flying == true

    table.insert(state.entities, entity)
    return entity
end

local function spawnCardUnit(state, owner, card, x, y)
    local count = card.spawnCount or 1
    local radius = card.spawnRadius or 0

    for i = 1, count do
        local angle = ((i - 1) / math.max(1, count)) * math.pi * 2
        local ox = math.cos(angle) * radius
        local oy = math.sin(angle) * radius
        local sx = util.clamp(x + ox, 2, config.ARENA.width - 2)
        local sy = util.clamp(y + oy, 2, config.ARENA.height - 2)

        if card.unit.flying or arena.isWalkable(card.unit, sx, sy) then
            spawnUnitFromStats(state, owner, card.unit, sx, sy, card.name, card.icon, card.color)
        else
            spawnUnitFromStats(state, owner, card.unit, x, y, card.name, card.icon, card.color)
        end
    end
end

local function spawnBuilding(state, owner, card, x, y)
    local entity = makeBaseEntity(state, owner, "building", x, y)
    for k, v in pairs(util.deepcopy(card.building)) do
        entity[k] = v
    end

    entity.name = card.name
    entity.icon = card.icon
    entity.color = card.color
    entity.maxHp = entity.maxHp or 500
    entity.hp = entity.maxHp
    entity.attackRange = entity.attackRange or 20
    entity.attackCooldown = entity.attackCooldown or 1
    entity.canAttackAir = entity.canAttackAir == true
    entity.remainingLifetime = entity.lifetime

    table.insert(state.entities, entity)
    return entity
end

local function spawnTower(state, blueprint)
    local entity = makeBaseEntity(state, blueprint.owner, "tower", blueprint.x, blueprint.y)
    entity.towerType = blueprint.towerType

    if blueprint.towerType == "king" then
        entity.name = "King Tower"
        entity.icon = "K"
        entity.maxHp = 2700
        entity.damage = 105
        entity.attackRange = 27
        entity.attackCooldown = 0.90
    else
        entity.name = "Princess Tower"
        entity.icon = "T"
        entity.maxHp = 1750
        entity.damage = 82
        entity.attackRange = 26
        entity.attackCooldown = 0.95
    end

    entity.hp = entity.maxHp
    entity.canAttackAir = true
    entity.projectileSpeed = 60
    entity.color = blueprint.owner == 1 and colors.lightBlue or colors.red

    table.insert(state.entities, entity)
end

local function getEntityById(state, id)
    if not id then return nil end
    for _, entity in ipairs(state.entities) do
        if entity.id == id and entity.alive then
            return entity
        end
    end
    return nil
end

local function targetAllowed(attacker, candidate)
    if not candidate.alive or candidate.owner == attacker.owner then return false end
    if candidate.flying and not attacker.canAttackAir then return false end

    if attacker.kind == "tower" or attacker.kind == "building" then
        return candidate.kind == "unit"
    end

    if attacker.targetMode == "buildings" then
        return candidate.kind == "building" or candidate.kind == "tower"
    end

    return true
end

local function findNearest(state, entity, filter, maxRange)
    local best = nil
    local bestDistance = math.huge

    for _, candidate in ipairs(state.entities) do
        if candidate.id ~= entity.id and targetAllowed(entity, candidate) and (not filter or filter(candidate)) then
            local d = util.distance(entity.x, entity.y, candidate.x, candidate.y)
            if (not maxRange or d <= maxRange) and d < bestDistance then
                bestDistance = d
                best = candidate
            end
        end
    end

    return best, bestDistance
end

local function acquireTarget(state, entity)
    if entity.kind == "tower" or entity.kind == "building" then
        local target = findNearest(state, entity, function(candidate)
            return candidate.kind == "unit"
        end, entity.attackRange)
        return target
    end

    local nearby = findNearest(state, entity, nil, entity.aggroRange)
    if nearby then return nearby end

    if entity.targetMode == "buildings" then
        return findNearest(state, entity, function(candidate)
            return candidate.kind == "tower" or candidate.kind == "building"
        end, nil)
    end

    local tower = findNearest(state, entity, function(candidate)
        return candidate.kind == "tower"
    end, nil)
    if tower then return tower end

    return findNearest(state, entity, nil, nil)
end

local function moveToward(entity, tx, ty, dt)
    local dx = tx - entity.x
    local dy = ty - entity.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.001 then return end

    local step = math.min(length, (entity.moveSpeed or 0) * dt)
    local nx = entity.x + dx / length * step
    local ny = entity.y + dy / length * step

    if arena.isWalkable(entity, nx, ny) then
        entity.x = nx
        entity.y = ny
        return
    end

    if arena.isWalkable(entity, nx, entity.y) then
        entity.x = nx
    elseif arena.isWalkable(entity, entity.x, ny) then
        entity.y = ny
    end
end

local function moveAway(entity, target, dt)
    local dx = entity.x - target.x
    local dy = entity.y - target.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.001 then
        dx = entity.owner == 1 and 0 or 0
        dy = entity.owner == 1 and 1 or -1
        length = 1
    end

    local step = (entity.moveSpeed or 0) * dt
    local nx = entity.x + dx / length * step
    local ny = entity.y + dy / length * step

    if arena.isWalkable(entity, nx, ny) then
        entity.x = nx
        entity.y = ny
    end
end

local damageEntity
local killEntity

local function spawnProjectile(state, attacker, target)
    table.insert(state.projectiles, {
        x = attacker.x,
        y = attacker.y,
        targetId = target.id,
        owner = attacker.owner,
        damage = attacker.damage,
        speed = attacker.projectileSpeed or 50,
        visual = attacker.name == "Skeleton" and "arrow"
            or (attacker.name == "Cannon" and "cannonball")
            or (attacker.kind == "tower" and "tower_shot")
            or "shot",
        alive = true,
    })
end

damageEntity = function(state, target, damage, sourceOwner)
    if not target or not target.alive then return end

    if damage > 0 then
        target.damageFlash = 0.18
        addEffect(state, "hit", target.x, target.y, 1.5, 0.16, sourceOwner)
    end

    target.hp = target.hp - damage
    if target.hp <= 0 then
        killEntity(state, target, sourceOwner)
    end
end

local function explodeProximityUnit(state, entity)
    local spec = entity.proximityExplosion
    if not spec or not entity.alive then return end

    addEffect(state, "explosion", entity.x, entity.y, spec.radius or 8, 0.55, entity.owner)
    emitSound(state, "minecraft:entity.generic.explode", 0.9, 1.0)

    local victims = {}
    for _, candidate in ipairs(state.entities) do
        if candidate.alive and candidate.id ~= entity.id and candidate.owner ~= entity.owner then
            local d = util.distance(entity.x, entity.y, candidate.x, candidate.y)
            if d <= (spec.radius or 8) then
                table.insert(victims, candidate)
            end
        end
    end

    -- Mark the Creeper dead directly. This is a self-detonation, not a normal
    -- death-trigger ability, so getting killed before the fuse completes does
    -- not cause an explosion.
    entity.alive = false
    entity.fuseRemaining = nil

    for _, victim in ipairs(victims) do
        damageEntity(state, victim, spec.damage or 0, entity.owner)
    end
end

local function handleDeathAbilities(state, entity)
    if entity.deathDamage then
        addEffect(state, "explosion", entity.x, entity.y, entity.deathDamage.radius, 0.45, entity.owner)

        local victims = {}
        for _, candidate in ipairs(state.entities) do
            if candidate.alive and candidate.owner ~= entity.owner then
                local d = util.distance(entity.x, entity.y, candidate.x, candidate.y)
                if d <= entity.deathDamage.radius then
                    table.insert(victims, candidate)
                end
            end
        end

        for _, victim in ipairs(victims) do
            damageEntity(state, victim, entity.deathDamage.damage, entity.owner)
        end
    end

    if entity.splitOnDeath then
        local template = cards.getInternalUnit(entity.splitOnDeath.template)
        if template then
            local count = entity.splitOnDeath.count or 2
            for i = 1, count do
                local direction = i % 2 == 0 and 1 or -1
                local sx = util.clamp(entity.x + direction * 2.2, 2, config.ARENA.width - 2)
                local sy = util.clamp(entity.y + (i - 1) * 1.2, 2, config.ARENA.height - 2)
                if arena.isWalkable(template, sx, sy) then
                    spawnUnitFromStats(
                        state,
                        entity.owner,
                        template,
                        sx,
                        sy,
                        template.name,
                        template.icon,
                        template.color
                    )
                end
            end
        end
    end
end

killEntity = function(state, entity, sourceOwner)
    if not entity.alive then return end
    entity.alive = false

    if entity.kind == "tower" then
        addEffect(state, "tower_down", entity.x, entity.y, 7, 0.7, sourceOwner)
        emitSound(state, "minecraft:entity.generic.explode", 0.8, 0.8)

        -- Admin sandbox tests should continue after a tower dies.
        if state.adminMode then
            return
        end

        local winner = sourceOwner or otherPlayer(entity.owner)

        if entity.towerType == "king" then
            Game.finish(state, winner, "KING TOWER DESTROYED")
        else
            state.players[winner].towersDestroyed = state.players[winner].towersDestroyed + 1
            if state.overtime then
                Game.finish(state, winner, "OVERTIME SUDDEN DEATH")
            end
        end
    elseif entity.kind == "unit" then
        handleDeathAbilities(state, entity)
    end
end

local function performAttack(state, entity, target)
    if entity.projectileSpeed then
        spawnProjectile(state, entity, target)
    else
        damageEntity(state, target, entity.damage or 0, entity.owner)
    end
    entity.attackCooldownLeft = entity.attackCooldown or 1
end

local function updateCombatEntity(state, entity, dt)
    if not entity.alive then return end

    if entity.damageFlash and entity.damageFlash > 0 then
        entity.damageFlash = math.max(0, entity.damageFlash - dt)
    end

    if entity.remainingLifetime then
        entity.remainingLifetime = entity.remainingLifetime - dt
        if entity.remainingLifetime <= 0 then
            entity.alive = false
            return
        end
    end

    entity.attackCooldownLeft = math.max(0, (entity.attackCooldownLeft or 0) - dt)

    local target = getEntityById(state, entity.targetId)
    if target and not targetAllowed(entity, target) then
        target = nil
    end

    -- Normal troops must be able to get "pulled" off a distant tower.
    -- Previously a troop could lock a tower while far away and keep that
    -- target forever, causing two enemy troops to walk past each other at
    -- the bridge. Building-only troops (e.g. Iron Golem) intentionally keep
    -- their building/tower targeting rules.
    if target
        and entity.kind == "unit"
        and entity.targetMode ~= "buildings"
    then
        local localTarget, localDistance = findNearest(state, entity, nil, entity.aggroRange)

        if localTarget and localTarget.id ~= target.id then
            local currentDistance = util.distance(entity.x, entity.y, target.x, target.y)

            -- Retarget when marching toward a tower and a closer valid enemy
            -- enters aggro range. Once fighting a unit/building, keep the lock
            -- to avoid jitter between several nearby targets.
            if target.kind == "tower" and localDistance < currentDistance then
                target = localTarget
                entity.targetId = localTarget.id
            end
        end
    end

    if not target then
        target = acquireTarget(state, entity)
        entity.targetId = target and target.id or nil
    end

    if not target then
        entity.fuseRemaining = nil
        return
    end

    local distance = util.distance(entity.x, entity.y, target.x, target.y)
    local attackRange = entity.attackRange or 0

    if entity.kind == "unit" and entity.proximityExplosion then
        local spec = entity.proximityExplosion
        local triggerRange = spec.triggerRange or 4
        local cancelRange = spec.cancelRange or (triggerRange + 2)

        if entity.fuseRemaining then
            if distance > cancelRange then
                entity.fuseRemaining = nil
            else
                entity.fuseRemaining = entity.fuseRemaining - dt
                if entity.fuseRemaining <= 0 then
                    explodeProximityUnit(state, entity)
                end
                return
            end
        end

        if distance <= triggerRange then
            entity.fuseRemaining = spec.fuseTime or 1.5
            emitSound(state, "minecraft:entity.creeper.primed", 0.7, 1.0)
            return
        end

        local tx, ty = arena.navigationPoint(entity, target)
        moveToward(entity, tx, ty, dt)
        return
    end

    if entity.kind == "unit"
        and entity.preferredMinRange
        and target.kind == "unit"
        and distance < entity.preferredMinRange
    then
        if distance <= attackRange and entity.attackCooldownLeft <= 0 then
            performAttack(state, entity, target)
        end
        moveAway(entity, target, dt)
        return
    end

    if distance <= attackRange then
        if entity.attackCooldownLeft <= 0 then
            performAttack(state, entity, target)
        end
        return
    end

    if entity.kind ~= "unit" then
        entity.targetId = nil
        return
    end

    local tx, ty = arena.navigationPoint(entity, target)
    moveToward(entity, tx, ty, dt)
end

local function updateProjectiles(state, dt)
    for _, projectile in ipairs(state.projectiles) do
        if projectile.alive then
            local target = getEntityById(state, projectile.targetId)
            if not target then
                projectile.alive = false
            else
                local dx = target.x - projectile.x
                local dy = target.y - projectile.y
                local distance = math.sqrt(dx * dx + dy * dy)
                local step = projectile.speed * dt

                if distance <= math.max(step, 1.2) then
                    projectile.x = target.x
                    projectile.y = target.y
                    projectile.alive = false
                    damageEntity(state, target, projectile.damage, projectile.owner)
                elseif distance > 0 then
                    projectile.x = projectile.x + dx / distance * step
                    projectile.y = projectile.y + dy / distance * step
                end
            end
        end
    end

    local kept = {}
    for _, projectile in ipairs(state.projectiles) do
        if projectile.alive then table.insert(kept, projectile) end
    end
    state.projectiles = kept
end

local function updateEffects(state, dt)
    local kept = {}
    for _, effect in ipairs(state.effects) do
        effect.ttl = effect.ttl - dt
        if effect.ttl > 0 then table.insert(kept, effect) end
    end
    state.effects = kept
end

local function cleanupEntities(state)
    local kept = {}
    for _, entity in ipairs(state.entities) do
        if entity.alive then table.insert(kept, entity) end
    end
    state.entities = kept
end

local function resetPlayersForMatch(state)
    for playerId = 1, 2 do
        local player = state.players[playerId]
        resetDeck(player)
        player.emeralds = config.MATCH.emeraldStart
        player.towersDestroyed = 0
        player.rematch = false
        player.feedback = nil
        player.feedbackTime = 0
    end
end

local function createTowers(state)
    for _, blueprint in ipairs(arena.towerBlueprints()) do
        spawnTower(state, blueprint)
    end
end

function Game.new(soundCallback)
    local state = {
        phase = "lobby",
        players = {
            [1] = newPlayer(1),
            [2] = newPlayer(2),
        },
        entities = {},
        projectiles = {},
        effects = {},
        nextEntityId = 1,
        countdown = config.MATCH.countdown,
        timeLeft = config.MATCH.normalTime,
        overtime = false,
        winner = nil,
        resultReason = nil,
        sound = soundCallback,
        adminMode = false,
        adminPaused = false,
        adminScenario = nil,
    }

    resetDeck(state.players[1])
    resetDeck(state.players[2])
    return state
end

function Game.resetLobby(state)
    state.phase = "lobby"
    state.entities = {}
    state.projectiles = {}
    state.effects = {}
    state.winner = nil
    state.resultReason = nil
    state.overtime = false
    state.adminMode = false
    state.adminPaused = false
    state.adminScenario = nil

    for playerId = 1, 2 do
        local player = state.players[playerId]
        player.ready = false
        player.rematch = false
        resetDeck(player)
        player.emeralds = config.MATCH.emeraldStart
        player.towersDestroyed = 0
    end
end

function Game.startCountdown(state)
    state.phase = "countdown"
    state.adminMode = false
    state.adminPaused = false
    state.adminScenario = nil
    state.countdown = config.MATCH.countdown
    state.entities = {}
    state.projectiles = {}
    state.effects = {}
    state.winner = nil
    state.resultReason = nil
    state.overtime = false
    resetPlayersForMatch(state)
    emitSound(state, "minecraft:block.note_block.pling", 0.7, 1.2)
end

local function beginBattle(state)
    state.phase = "battle"
    state.timeLeft = config.MATCH.normalTime
    state.overtime = false
    createTowers(state)
    emitSound(state, "minecraft:entity.experience_orb.pickup", 0.9, 1.0)
end

function Game.finish(state, winner, reason)
    if state.phase == "result" then return end
    state.phase = "result"
    state.winner = winner
    state.resultReason = reason or "MATCH OVER"
    state.players[1].selectedSlot = nil
    state.players[2].selectedSlot = nil

    if winner then
        emitSound(state, "minecraft:ui.toast.challenge_complete", 1.0, 1.0)
    else
        emitSound(state, "minecraft:block.note_block.bass", 0.8, 0.7)
    end
end

local function castArrows(state, playerId, card, x, y)
    addEffect(state, "arrows", x, y, card.spell.radius, 0.45, playerId)

    local targets = {}
    for _, entity in ipairs(state.entities) do
        if entity.alive and entity.owner ~= playerId then
            local distance = util.distance(x, y, entity.x, entity.y)
            if distance <= card.spell.radius then
                table.insert(targets, entity)
            end
        end
    end

    for _, target in ipairs(targets) do
        local damage = card.spell.damage
        if target.kind == "tower" then
            damage = damage * (card.spell.towerMultiplier or 1)
        end
        damageEntity(state, target, damage, playerId)
    end

    emitSound(state, "minecraft:entity.arrow.shoot", 0.7, 1.1)
end

local function cycleHand(player, slot)
    local playedCard = player.hand[slot]
    local nextCard = table.remove(player.queue, 1)
    player.hand[slot] = nextCard
    table.insert(player.queue, playedCard)
end

local function playSelectedCard(state, playerId, x, y)
    local player = state.players[playerId]
    local slot = player.selectedSlot
    if not slot then return false end

    local cardId = player.hand[slot]
    local card = cards.get(cardId)
    if not card then
        setFeedback(player, "CARD ERROR")
        player.selectedSlot = nil
        return false
    end

    if player.emeralds + 0.0001 < card.cost then
        setFeedback(player, "NOT ENOUGH EMERALDS")
        return false
    end

    if not arena.placementAllowed(playerId, x, y, card.placement) then
        setFeedback(player, "INVALID PLACEMENT")
        return false
    end

    if card.kind == "unit" then
        spawnCardUnit(state, playerId, card, x, y)
    elseif card.kind == "building" then
        spawnBuilding(state, playerId, card, x, y)
    elseif card.kind == "spell" then
        castArrows(state, playerId, card, x, y)
    else
        setFeedback(player, "UNSUPPORTED CARD")
        return false
    end

    player.emeralds = player.emeralds - card.cost
    cycleHand(player, slot)
    player.selectedSlot = nil
    setFeedback(player, card.name .. " DEPLOYED", 0.7)
    emitSound(state, "minecraft:block.amethyst_block.hit", 0.45, 1.4)
    return true
end

local function hit(zone, x, y)
    return zone
        and x >= zone.x1 and x <= zone.x2
        and y >= zone.y1 and y <= zone.y2
end

function Game.handleTouch(state, playerId, x, y, layout)
    local player = state.players[playerId]

    if state.phase == "lobby" then
        if hit(layout.readyButton, x, y) then
            player.ready = not player.ready
            emitSound(state, "minecraft:block.note_block.hat", 0.5, player.ready and 1.4 or 0.8)

            if state.players[1].ready and state.players[2].ready then
                Game.startCountdown(state)
            end
        end
        return
    end

    if state.phase == "countdown" then
        return
    end

    if state.phase == "battle" then
        for slot = 1, 4 do
            if hit(layout.cards[slot], x, y) then
                if player.selectedSlot == slot then
                    player.selectedSlot = nil
                else
                    player.selectedSlot = slot
                end
                return
            end
        end

        if hit(layout.arena, x, y) and player.selectedSlot then
            local wx, wy = arena.screenToWorld(playerId, x, y, layout.arena)
            playSelectedCard(state, playerId, wx, wy)
        end
        return
    end

    if state.phase == "result" then
        if hit(layout.resultButtons.rematch, x, y) then
            player.rematch = not player.rematch
            if state.players[1].rematch and state.players[2].rematch then
                state.players[1].ready = true
                state.players[2].ready = true
                Game.startCountdown(state)
            end
        elseif hit(layout.resultButtons.deck, x, y) then
            Game.resetLobby(state)
        elseif hit(layout.resultButtons.exit, x, y) then
            Game.resetLobby(state)
        end
    end
end

function Game.update(state, dt)
    dt = util.clamp(dt or config.TICK_RATE, 0, 0.25)

    for playerId = 1, 2 do
        local player = state.players[playerId]
        if player.feedbackTime > 0 then
            player.feedbackTime = math.max(0, player.feedbackTime - dt)
            if player.feedbackTime <= 0 then player.feedback = nil end
        end
    end

    if state.phase == "countdown" then
        state.countdown = state.countdown - dt
        if state.countdown <= 0 then
            beginBattle(state)
        end
        return
    end

    local isBattle = state.phase == "battle"
    local isAdmin = state.phase == "admin"

    if not isBattle and not isAdmin then return end
    if isAdmin and state.adminPaused then return end

    if isBattle then
        local multiplier = state.overtime and config.MATCH.overtimeMultiplier or 1
        local emeraldRate = config.MATCH.emeraldPerSecond * multiplier

        for playerId = 1, 2 do
            local player = state.players[playerId]
            player.emeralds = math.min(player.maxEmeralds, player.emeralds + emeraldRate * dt)
        end
    end

    for _, entity in ipairs(state.entities) do
        if isBattle and state.phase ~= "battle" then break end
        updateCombatEntity(state, entity, dt)
    end

    if (isBattle and state.phase == "battle") or isAdmin then
        updateProjectiles(state, dt)
        updateEffects(state, dt)
        cleanupEntities(state)

        if isBattle and state.phase ~= "battle" then
            return
        end

        if isAdmin then
            return
        end

        state.timeLeft = state.timeLeft - dt
        if state.timeLeft <= 0 then
            if not state.overtime then
                local score1 = state.players[1].towersDestroyed
                local score2 = state.players[2].towersDestroyed

                if score1 > score2 then
                    Game.finish(state, 1, "MORE TOWERS DESTROYED")
                elseif score2 > score1 then
                    Game.finish(state, 2, "MORE TOWERS DESTROYED")
                else
                    state.overtime = true
                    state.timeLeft = config.MATCH.overtimeTime
                    emitSound(state, "minecraft:block.beacon.activate", 0.9, 1.2)
                    setFeedback(state.players[1], "OVERTIME - 3X EMERALDS", 2)
                    setFeedback(state.players[2], "OVERTIME - 3X EMERALDS", 2)
                end
            else
                Game.finish(state, nil, "DRAW")
            end
        end
    end
end

local function clearSimulation(state)
    state.entities = {}
    state.projectiles = {}
    state.effects = {}
    state.nextEntityId = 1
end

local function spawnScenarioTowers(state, scenario)
    local blueprints = arena.towerBlueprints()

    if scenario == "full" then
        for _, blueprint in ipairs(blueprints) do
            spawnTower(state, blueprint)
        end
        return
    end

    if scenario == "princess" then
        for _, blueprint in ipairs(blueprints) do
            if blueprint.towerType == "princess" then
                spawnTower(state, blueprint)
            end
        end
        return
    end

    if scenario == "king" then
        for _, blueprint in ipairs(blueprints) do
            if blueprint.towerType == "king" then
                spawnTower(state, blueprint)
            end
        end
        return
    end

    if scenario == "single_tower" then
        spawnTower(state, { owner = 1, towerType = "princess", x = 50, y = 132 })
        spawnTower(state, { owner = 2, towerType = "princess", x = 50, y = 28 })
    end
end

function Game.debugLoadScenario(state, scenario)
    scenario = scenario or "full"
    clearSimulation(state)

    state.phase = "admin"
    state.adminMode = true
    state.adminPaused = true
    state.adminScenario = scenario
    state.winner = nil
    state.resultReason = nil
    state.overtime = false

    for playerId = 1, 2 do
        state.players[playerId].emeralds = state.players[playerId].maxEmeralds
        state.players[playerId].towersDestroyed = 0
        state.players[playerId].selectedSlot = nil
    end

    spawnScenarioTowers(state, scenario)
end

function Game.debugSpawnCard(state, owner, cardId, x, y)
    if not state.adminMode then return false, "NOT IN ADMIN MODE" end
    if owner ~= 1 and owner ~= 2 then return false, "INVALID OWNER" end

    local card = cards.get(cardId)
    if not card then return false, "UNKNOWN CARD" end

    x = util.clamp(x, 2, config.ARENA.width - 2)
    y = util.clamp(y, 2, config.ARENA.height - 2)

    if card.kind == "unit" then
        spawnCardUnit(state, owner, card, x, y)
    elseif card.kind == "building" then
        spawnBuilding(state, owner, card, x, y)
    elseif card.kind == "spell" then
        castArrows(state, owner, card, x, y)
    else
        return false, "UNSUPPORTED CARD"
    end

    return true
end

function Game.debugClearUnits(state)
    local kept = {}
    for _, entity in ipairs(state.entities) do
        if entity.kind == "tower" and entity.alive then
            entity.targetId = nil
            entity.attackCooldownLeft = 0
            table.insert(kept, entity)
        end
    end
    state.entities = kept
    state.projectiles = {}
    state.effects = {}
end

function Game.debugSetPaused(state, paused)
    if not state.adminMode then return end
    state.adminPaused = paused == true
end

function Game.debugTogglePaused(state)
    if not state.adminMode then return false end
    state.adminPaused = not state.adminPaused
    return state.adminPaused
end

function Game.getCardForSlot(state, playerId, slot)
    return cards.get(state.players[playerId].hand[slot])
end

function Game.getCards()
    return cards.list
end

return Game

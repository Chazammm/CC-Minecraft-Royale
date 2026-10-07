local config = require("config")
local util = require("src.util")
local cards = require("src.cards")
local arena = require("src.arena")

local Game = {}

local PRESET_FILE = "deck_presets.db"

local function emptyPresets()
    return {
        [1] = { nil, nil, nil },
        [2] = { nil, nil, nil },
    }
end

local function loadPresets()
    local presets = emptyPresets()
    if not fs or not fs.exists or not fs.exists(PRESET_FILE) then return presets end

    local handle = fs.open(PRESET_FILE, "r")
    if not handle then return presets end
    local raw = handle.readAll()
    handle.close()

    local ok, decoded = pcall(textutils.unserialize, raw)
    if ok and type(decoded) == "table" then
        for playerId = 1, 2 do
            if type(decoded[playerId]) == "table" then
                for slot = 1, 3 do
                    if cards.isValidDeck(decoded[playerId][slot]) then
                        presets[playerId][slot] = util.deepcopy(decoded[playerId][slot])
                    end
                end
            end
        end
    end

    return presets
end

local function savePresets(presets)
    if not fs or not fs.open or not textutils or not textutils.serialize then return false end
    local handle = fs.open(PRESET_FILE, "w")
    if not handle then return false end
    handle.write(textutils.serialize(presets))
    handle.close()
    return true
end

local function randomDeck()
    local pool = {}
    for _, card in ipairs(cards.list) do pool[#pool + 1] = card.id end

    for i = #pool, 2, -1 do
        local j = math.random(i)
        pool[i], pool[j] = pool[j], pool[i]
    end

    local deck = {}
    for i = 1, 8 do deck[i] = pool[i] end
    return deck
end

local function newPlayerStats()
    return {
        cardsPlayed = 0,
        emeraldSpent = 0,
        emeraldGenerated = 0,
        villagerBonus = 0,
        emeraldWasted = 0,
        unitDamage = 0,
        towerDamage = 0,
        kills = 0,
        towersKilled = 0,
        cards = {},
    }
end

local function newMatchStats()
    return {
        elapsed = 0,
        players = {
            [1] = newPlayerStats(),
            [2] = newPlayerStats(),
        },
    }
end

local function getCardStats(state, playerId, cardId)
    if not state.stats or not state.stats.players[playerId] or not cardId then return nil end
    local playerStats = state.stats.players[playerId]
    local stat = playerStats.cards[cardId]
    if not stat then
        stat = {
            plays = 0,
            emeraldSpent = 0,
            unitDamage = 0,
            towerDamage = 0,
            kills = 0,
            towersKilled = 0,
            emeraldBonus = 0,
            slowSeconds = 0,
            targetsHit = 0,
        }
        playerStats.cards[cardId] = stat
    end
    return stat
end

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
        infoOpen = false,
        infoCardId = cards.list[1] and cards.list[1].id or nil,
        collectionPage = 1,
        presetSlot = 1,
        towersDestroyed = 0,
        feedback = nil,
        feedbackTime = 0,
    }
end

local function resetDeck(player)
    if not cards.isValidDeck(player.deck) then
        player.deck = cards.defaultDeck()
    end

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

local function spawnUnitFromStats(state, owner, stats, x, y, name, icon, color, sourceCardId)
    local entity = makeBaseEntity(state, owner, "unit", x, y)

    for k, v in pairs(util.deepcopy(stats)) do
        entity[k] = v
    end

    entity.name = name or "Unit"
    entity.icon = icon or "?"
    entity.color = color or colors.white
    entity.sourceCardId = sourceCardId
    entity.maxHp = entity.maxHp or 100
    entity.hp = entity.maxHp
    entity.moveSpeed = entity.moveSpeed or 5
    entity.attackRange = entity.attackRange or 2
    entity.attackCooldown = entity.attackCooldown or 1
    entity.aggroRange = entity.aggroRange or 25
    entity.targetMode = entity.targetMode or "any"
    entity.canAttackAir = entity.canAttackAir == true
    entity.flying = entity.flying == true
    entity.remainingLifetime = entity.lifetime
    entity.teleportCooldownLeft = 0
    entity.slowRemaining = 0
    entity.slowFactor = 1
    entity.periodicSpawnTimer = entity.periodicSpawn
        and (entity.periodicSpawn.initialDelay or entity.periodicSpawn.interval or 8)
        or nil
    entity.emeraldPulseTimer = entity.emeraldBoost and 0.25 or nil

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
            spawnUnitFromStats(state, owner, card.unit, sx, sy, card.name, card.icon, card.color, card.id)
        else
            spawnUnitFromStats(state, owner, card.unit, x, y, card.name, card.icon, card.color, card.id)
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
    entity.sourceCardId = card.id
    entity.maxHp = entity.maxHp or 500
    entity.hp = entity.maxHp
    entity.attackRange = entity.attackRange or 20
    entity.attackCooldown = entity.attackCooldown or 1
    entity.canAttackAir = entity.canAttackAir == true
    entity.remainingLifetime = entity.lifetime
    entity.periodicSpawnTimer = entity.periodicSpawn
        and (entity.periodicSpawn.initialDelay or entity.periodicSpawn.interval or 8)
        or nil

    table.insert(state.entities, entity)
    return entity
end

local function spawnTower(state, blueprint)
    local entity = makeBaseEntity(state, blueprint.owner, "tower", blueprint.x, blueprint.y)
    entity.towerType = blueprint.towerType

    if blueprint.towerType == "king" then
        entity.name = "King Tower"
        entity.icon = "K"
        entity.maxHp = 2565
        entity.damage = 105
        entity.attackRange = 27
        entity.attackCooldown = 0.90
    else
        entity.name = "Princess Tower"
        entity.icon = "T"
        entity.maxHp = 1580
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
    if entity.passive or entity.targetMode == "none" then
        return nil
    end

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

local function currentMoveSpeed(entity)
    local speed = entity.moveSpeed or 0
    if entity.slowRemaining and entity.slowRemaining > 0 then
        speed = speed * (entity.slowFactor or 1)
    end
    return speed
end

local function moveToward(entity, tx, ty, dt)
    local dx = tx - entity.x
    local dy = ty - entity.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.001 then return end

    local step = math.min(length, currentMoveSpeed(entity) * dt)
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

local function spawnProjectile(state, attacker, target, damageOverride, visualOverride)
    table.insert(state.projectiles, {
        x = attacker.x,
        y = attacker.y,
        targetId = target.id,
        owner = attacker.owner,
        sourceCardId = attacker.sourceCardId,
        damage = damageOverride or attacker.damage,
        speed = attacker.projectileSpeed or 50,
        visual = visualOverride
            or attacker.projectileVisual
            or (attacker.name == "Skeleton" and "arrow")
            or (attacker.name == "Cannon" and "cannonball")
            or (attacker.kind == "tower" and "tower_shot")
            or "shot",
        splashRadius = attacker.projectileSplashRadius,
        onHitSlow = attacker.onHitSlow and util.deepcopy(attacker.onHitSlow) or nil,
        alive = true,
    })
end

damageEntity = function(state, target, damage, sourceOwner, sourceCardId)
    if not target or not target.alive then return end

    local actualDamage = math.min(math.max(0, damage or 0), math.max(0, target.hp or 0))

    if actualDamage > 0 then
        target.damageFlash = 0.18
        addEffect(state, "hit", target.x, target.y, 1.5, 0.16, sourceOwner)

        if state.phase == "battle" and sourceOwner and sourceCardId and state.stats then
            local playerStats = state.stats.players[sourceOwner]
            local cardStats = getCardStats(state, sourceOwner, sourceCardId)

            if target.kind == "tower" then
                playerStats.towerDamage = playerStats.towerDamage + actualDamage
                cardStats.towerDamage = cardStats.towerDamage + actualDamage
            else
                playerStats.unitDamage = playerStats.unitDamage + actualDamage
                cardStats.unitDamage = cardStats.unitDamage + actualDamage
            end
        end
    end

    target.hp = target.hp - (damage or 0)

    if target.kind == "tower"
        and target.alive
        and not target.lowHpAlerted
        and target.hp > 0
        and target.hp / math.max(1, target.maxHp) <= 0.25
    then
        target.lowHpAlerted = true
        addEffect(state, "tower_warning", target.x, target.y, 6, 0.65, target.owner)
        emitSound(state, "minecraft:block.note_block.bass", 0.7, 0.55)
    end

    if target.hp <= 0 then
        killEntity(state, target, sourceOwner, sourceCardId)
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
        damageEntity(state, victim, spec.damage or 0, entity.owner, entity.sourceCardId)
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
            damageEntity(state, victim, entity.deathDamage.damage, entity.owner, entity.sourceCardId)
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
                        template.color,
                        entity.sourceCardId
                    )
                end
            end
        end
    end
end

killEntity = function(state, entity, sourceOwner, sourceCardId)
    if not entity.alive then return end
    entity.alive = false

    if state.phase == "battle" and sourceOwner and sourceCardId and state.stats then
        local playerStats = state.stats.players[sourceOwner]
        local cardStats = getCardStats(state, sourceOwner, sourceCardId)
        if entity.kind == "tower" then
            playerStats.towersKilled = playerStats.towersKilled + 1
            cardStats.towersKilled = cardStats.towersKilled + 1
        else
            playerStats.kills = playerStats.kills + 1
            cardStats.kills = cardStats.kills + 1
        end
    end

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
        addEffect(state, "death", entity.x, entity.y, 3.5, 0.28, entity.owner)
        handleDeathAbilities(state, entity)
    elseif entity.kind == "building" then
        addEffect(state, "death", entity.x, entity.y, 4.5, 0.35, entity.owner)
    end
end

local function updatePeriodicSpawn(state, entity, dt)
    local spec = entity.periodicSpawn
    if not spec then return end

    entity.periodicSpawnTimer = (entity.periodicSpawnTimer or spec.interval or 8) - dt
    if entity.periodicSpawnTimer > 0 then return end

    local template = cards.getInternalUnit(spec.template)
    if not template then
        entity.periodicSpawnTimer = spec.interval or 8
        return
    end

    if spec.maxAlive then
        local aliveSummons = 0
        for _, candidate in ipairs(state.entities) do
            if candidate.alive and candidate.summonerId == entity.id then
                aliveSummons = aliveSummons + 1
            end
        end

        if aliveSummons >= spec.maxAlive then
            entity.periodicSpawnTimer = spec.interval or 8
            return
        end
    end

    local count = spec.count or 1
    local radius = spec.radius or 2

    for i = 1, count do
        local angle = ((i - 1) / math.max(1, count)) * math.pi * 2
        local sx = util.clamp(entity.x + math.cos(angle) * radius, 2, config.ARENA.width - 2)
        local sy = util.clamp(entity.y + math.sin(angle) * radius, 2, config.ARENA.height - 2)

        if template.flying or arena.isWalkable(template, sx, sy) then
            local summoned = spawnUnitFromStats(
                state,
                entity.owner,
                template,
                sx,
                sy,
                template.name,
                template.icon,
                template.color,
                entity.sourceCardId
            )
            summoned.summonerId = entity.id
        end
    end

    addEffect(
        state,
        spec.effect or "summon",
        entity.x,
        entity.y,
        5,
        0.35,
        entity.owner
    )
    emitSound(
        state,
        spec.sound or "minecraft:entity.zombie_villager.cure",
        spec.soundVolume or 0.35,
        spec.soundPitch or 1.4
    )
    entity.periodicSpawnTimer = spec.interval or 8
end

local function performAttack(state, entity, target)
    if entity.hybridAttack then
        local spec = entity.hybridAttack

        -- Piglin-style hybrid units only use their ranged weapon against
        -- flying targets. Every grounded target (troops, buildings, towers)
        -- is attacked with the melee weapon.
        if target.flying then
            spawnProjectile(
                state,
                entity,
                target,
                spec.rangedDamage or entity.damage,
                entity.projectileVisual or "crossbow_bolt"
            )
            entity.attackCooldownLeft = spec.rangedCooldown or entity.attackCooldown or 1
            emitSound(state, "minecraft:item.crossbow.shoot", 0.35, 1.15)
        else
            damageEntity(
                state,
                target,
                spec.meleeDamage or entity.damage or 0,
                entity.owner,
                entity.sourceCardId
            )
            entity.attackCooldownLeft = spec.meleeCooldown or entity.attackCooldown or 1
            emitSound(state, "minecraft:entity.player.attack.sweep", 0.35, 1.25)
        end
        return
    end

    if entity.projectileSpeed then
        spawnProjectile(state, entity, target)
    else
        damageEntity(state, target, entity.damage or 0, entity.owner, entity.sourceCardId)
    end
    entity.attackCooldownLeft = entity.attackCooldown or 1
end

local function updateCombatEntity(state, entity, dt)
    if not entity.alive then return end

    if entity.damageFlash and entity.damageFlash > 0 then
        entity.damageFlash = math.max(0, entity.damageFlash - dt)
    end

    if entity.kind == "tower"
        and entity.hp
        and entity.maxHp
        and entity.hp > 0
        and entity.hp / math.max(1, entity.maxHp) <= 0.25
    then
        entity.criticalPulseTimer = (entity.criticalPulseTimer or 0) - dt
        if entity.criticalPulseTimer <= 0 then
            entity.damageFlash = math.max(entity.damageFlash or 0, 0.10)
            entity.criticalPulseTimer = 0.55
        end
    end

    if entity.remainingLifetime then
        entity.remainingLifetime = entity.remainingLifetime - dt
        if entity.remainingLifetime <= 0 then
            entity.alive = false
            addEffect(
                state,
                entity.emeraldBoost and "emerald" or "death",
                entity.x,
                entity.y,
                entity.kind == "building" and 4.5 or 3.5,
                entity.emeraldBoost and 0.55 or 0.30,
                entity.owner
            )
            return
        end
    end

    entity.attackCooldownLeft = math.max(0, (entity.attackCooldownLeft or 0) - dt)
    entity.teleportCooldownLeft = math.max(0, (entity.teleportCooldownLeft or 0) - dt)

    if entity.slowRemaining and entity.slowRemaining > 0 then
        entity.slowRemaining = math.max(0, entity.slowRemaining - dt)
        if entity.slowRemaining <= 0 then
            entity.slowFactor = 1
        end
    end

    updatePeriodicSpawn(state, entity, dt)

    if entity.emeraldBoost then
        entity.emeraldPulseTimer = (entity.emeraldPulseTimer or 0) - dt
        if entity.emeraldPulseTimer <= 0 then
            addEffect(state, "emerald", entity.x, entity.y, 2.5, 0.45, entity.owner)
            entity.emeraldPulseTimer = 1.0
        end
    end

    if entity.passive or entity.targetMode == "none" then
        entity.targetId = nil
        return
    end

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

    if entity.hybridAttack and not target.flying then
        attackRange = entity.hybridAttack.meleeRange or 2.5
    end

    if entity.kind == "unit" and entity.teleport and entity.teleportCooldownLeft <= 0 then
        local spec = entity.teleport
        local minRange = spec.minRange or 8
        local maxRange = spec.maxRange or 30

        if distance >= minRange and distance <= maxRange then
            local dx = entity.x - target.x
            local dy = entity.y - target.y
            local length = math.sqrt(dx * dx + dy * dy)
            if length < 0.001 then length = 1 end

            local stopRange = spec.stopRange or math.max(2.5, attackRange)
            local nx = target.x + dx / length * stopRange
            local ny = target.y + dy / length * stopRange

            if arena.isWalkable(entity, nx, ny) then
                addEffect(state, "teleport", entity.x, entity.y, 4, 0.25, entity.owner)
                entity.x = util.clamp(nx, 2, config.ARENA.width - 2)
                entity.y = util.clamp(ny, 2, config.ARENA.height - 2)
                entity.teleportCooldownLeft = spec.cooldown or 4
                addEffect(state, "teleport", entity.x, entity.y, 4, 0.25, entity.owner)
                emitSound(state, "minecraft:entity.enderman.teleport", 0.7, 1.0)
                distance = util.distance(entity.x, entity.y, target.x, target.y)
            end
        end
    end

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

                    local victims = {}
                    if projectile.splashRadius then
                        for _, candidate in ipairs(state.entities) do
                            if candidate.alive and candidate.owner ~= projectile.owner then
                                local d = util.distance(target.x, target.y, candidate.x, candidate.y)
                                if d <= projectile.splashRadius then
                                    table.insert(victims, candidate)
                                end
                            end
                        end
                        addEffect(state, "splash", target.x, target.y, projectile.splashRadius, 0.30, projectile.owner)
                    else
                        table.insert(victims, target)
                    end

                    for _, victim in ipairs(victims) do
                        damageEntity(state, victim, projectile.damage, projectile.owner, projectile.sourceCardId)
                        if victim.alive and projectile.onHitSlow then
                            local oldRemaining = victim.slowRemaining or 0
                            local newRemaining = math.max(
                                oldRemaining,
                                projectile.onHitSlow.duration or 1
                            )
                            victim.slowRemaining = newRemaining
                            victim.slowFactor = math.min(
                                victim.slowFactor or 1,
                                projectile.onHitSlow.factor or 0.7
                            )
                            addEffect(state, "slow", victim.x, victim.y, 3.5, 0.28, projectile.owner)

                            if state.phase == "battle"
                                and state.stats
                                and projectile.sourceCardId
                            then
                                local cardStats = getCardStats(
                                    state,
                                    projectile.owner,
                                    projectile.sourceCardId
                                )
                                cardStats.slowSeconds = cardStats.slowSeconds
                                    + math.max(0, newRemaining - oldRemaining)
                            end
                        end
                    end
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
        player.infoOpen = false
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
        pendingSpells = {},
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
        gameMode = "pvp",
        botPlayerId = 2,
        botDifficulty = "normal",
        deckPresets = loadPresets(),
        stats = newMatchStats(),
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
    state.pendingSpells = {}
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
        player.infoOpen = false
        if not cards.get(player.infoCardId) then
            player.infoCardId = cards.list[1] and cards.list[1].id or nil
        end
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
    state.pendingSpells = {}
    state.winner = nil
    state.resultReason = nil
    state.overtime = false
    state.stats = newMatchStats()
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
    state.pendingSpells = {}

    if winner then
        emitSound(state, "minecraft:ui.toast.challenge_complete", 1.0, 1.0)
    else
        emitSound(state, "minecraft:block.note_block.bass", 0.8, 0.7)
    end
end

local function castFallingAnvil(state, playerId, card, x, y)
    local spell = card.spell
    local delay = spell.delay or 3

    state.pendingSpells[#state.pendingSpells + 1] = {
        kind = "falling_anvil",
        owner = playerId,
        cardId = card.id,
        x = x,
        y = y,
        remaining = delay,
        delay = delay,
        spell = util.deepcopy(spell),
    }

    addEffect(state, "anvil_warning", x, y, spell.radius or 5.5, delay, playerId)
    emitSound(state, "minecraft:block.anvil.place", 0.45, 1.7)
end

local function resolveFallingAnvil(state, pending)
    local spell = pending.spell
    local targets = {}

    for _, entity in ipairs(state.entities) do
        if entity.alive
            and entity.owner ~= pending.owner
            and (not spell.groundOnly or not entity.flying)
        then
            local distance = util.distance(pending.x, pending.y, entity.x, entity.y)
            if distance <= (spell.radius or 5.5) then
                targets[#targets + 1] = entity
            end
        end
    end

    if state.phase == "battle" and state.stats then
        local cardStats = getCardStats(state, pending.owner, pending.cardId)
        cardStats.targetsHit = cardStats.targetsHit + #targets
    end

    for _, target in ipairs(targets) do
        local damage = spell.damage or 0
        if target.kind == "tower" then
            damage = damage * (spell.towerMultiplier or 1)
        end
        damageEntity(state, target, damage, pending.owner, pending.cardId)
    end

    addEffect(
        state,
        "anvil_impact",
        pending.x,
        pending.y,
        spell.radius or 5.5,
        0.65,
        pending.owner
    )
    emitSound(state, "minecraft:block.anvil.land", 1.0, 0.75)
end

local function updatePendingSpells(state, dt)
    local kept = {}

    for _, pending in ipairs(state.pendingSpells) do
        pending.remaining = pending.remaining - dt
        if pending.remaining <= 0 then
            if pending.kind == "falling_anvil" then
                resolveFallingAnvil(state, pending)
            end
        else
            kept[#kept + 1] = pending
        end
    end

    state.pendingSpells = kept
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

    if state.phase == "battle" and state.stats then
        local cardStats = getCardStats(state, playerId, card.id)
        cardStats.targetsHit = cardStats.targetsHit + #targets
    end

    for _, target in ipairs(targets) do
        local damage = card.spell.damage
        if target.kind == "tower" then
            damage = damage * (card.spell.towerMultiplier or 1)
        end
        damageEntity(state, target, damage, playerId, card.id)
    end

    emitSound(state, "minecraft:entity.arrow.shoot", 0.7, 1.1)
end

local function cycleHand(player, slot)
    local playedCard = player.hand[slot]
    local nextCard = table.remove(player.queue, 1)
    player.hand[slot] = nextCard
    table.insert(player.queue, playedCard)
end

function Game.playCardFromSlot(state, playerId, slot, x, y)
    local player = state.players[playerId]
    if not player or (state.phase ~= "battle" and state.phase ~= "admin") then
        return false, "NOT PLAYABLE"
    end

    local cardId = player.hand[slot]
    local card = cards.get(cardId)
    if not card then
        setFeedback(player, "CARD ERROR")
        player.selectedSlot = nil
        return false, "CARD ERROR"
    end

    if player.emeralds + 0.0001 < card.cost then
        setFeedback(player, "NOT ENOUGH EMERALDS")
        return false, "NOT ENOUGH EMERALDS"
    end

    if not arena.placementAllowed(playerId, x, y, card.placement) then
        setFeedback(player, "INVALID PLACEMENT")
        return false, "INVALID PLACEMENT"
    end

    if card.kind == "unit" then
        spawnCardUnit(state, playerId, card, x, y)
        addEffect(state, "spawn", x, y, card.spawnCount and 5 or 3.5, 0.30, playerId)
    elseif card.kind == "building" then
        spawnBuilding(state, playerId, card, x, y)
        addEffect(state, "spawn", x, y, 5, 0.35, playerId)
    elseif card.kind == "spell" then
        if card.id == "falling_anvil" then
            castFallingAnvil(state, playerId, card, x, y)
        else
            castArrows(state, playerId, card, x, y)
        end
    else
        setFeedback(player, "UNSUPPORTED CARD")
        return false, "UNSUPPORTED CARD"
    end

    player.emeralds = player.emeralds - card.cost

    if state.phase == "battle" and state.stats then
        local playerStats = state.stats.players[playerId]
        local cardStats = getCardStats(state, playerId, card.id)
        playerStats.cardsPlayed = playerStats.cardsPlayed + 1
        playerStats.emeraldSpent = playerStats.emeraldSpent + card.cost
        cardStats.plays = cardStats.plays + 1
        cardStats.emeraldSpent = cardStats.emeraldSpent + card.cost
    end

    cycleHand(player, slot)
    player.selectedSlot = nil
    setFeedback(player, card.name .. " DEPLOYED", 0.7)
    emitSound(state, "minecraft:block.amethyst_block.hit", 0.45, 1.4)
    return true
end

local function playSelectedCard(state, playerId, x, y)
    local player = state.players[playerId]
    if not player.selectedSlot then return false end
    return Game.playCardFromSlot(state, playerId, player.selectedSlot, x, y)
end

local function deckPosition(deck, cardId)
    for i, id in ipairs(deck) do
        if id == cardId then return i end
    end
    return nil
end

function Game.toggleDeckCard(state, playerId, cardId)
    local player = state.players[playerId]
    local card = cards.get(cardId)
    if not player or not card then return false end

    local pos = deckPosition(player.deck, cardId)
    player.ready = false

    if pos then
        table.remove(player.deck, pos)
        setFeedback(player, card.name .. " REMOVED", 0.8)
        return true
    end

    if #player.deck >= 8 then
        setFeedback(player, "DECK FULL - REMOVE A CARD", 1.2)
        return false
    end

    table.insert(player.deck, cardId)
    setFeedback(player, card.name .. " ADDED", 0.8)
    return true
end

function Game.setGameMode(state, mode, requestingPlayerId)
    if mode ~= "pvp" and mode ~= "bot" then return false end
    if state.phase ~= "lobby" then return false end

    state.gameMode = mode

    -- The player who enables VS BOT remains the human. The opposite monitor
    -- becomes the AI side. Calls without a requester keep P2 as the legacy
    -- default so tests/admin code remain backwards compatible.
    if mode == "bot" then
        if requestingPlayerId == 1 or requestingPlayerId == 2 then
            state.botPlayerId = otherPlayer(requestingPlayerId)
        elseif state.botPlayerId ~= 1 and state.botPlayerId ~= 2 then
            state.botPlayerId = 2
        end
    end

    state.players[1].ready = false
    state.players[2].ready = false
    state.players[1].rematch = false
    state.players[2].rematch = false
    return true
end

function Game.toggleGameMode(state, requestingPlayerId)
    return Game.setGameMode(
        state,
        state.gameMode == "bot" and "pvp" or "bot",
        requestingPlayerId
    )
end

function Game.cycleBotDifficulty(state)
    if state.phase ~= "lobby" or state.gameMode ~= "bot" then return false end
    local order = { "easy", "normal", "hard" }
    local current = state.botDifficulty or "normal"
    local nextValue = "easy"

    for i, value in ipairs(order) do
        if value == current then
            nextValue = order[(i % #order) + 1]
            break
        end
    end

    state.botDifficulty = nextValue
    return true
end

local COLLECTION_PAGE_SIZE = 16

local function collectionPageCount()
    return math.max(1, math.ceil(#cards.list / COLLECTION_PAGE_SIZE))
end

local function collectionCardForSlot(player, slot)
    local page = math.max(1, math.min(collectionPageCount(), player.collectionPage or 1))
    local index = (page - 1) * COLLECTION_PAGE_SIZE + slot
    return cards.list[index]
end

function Game.cycleCollectionPage(state, playerId, delta)
    local player = state.players[playerId]
    if not player then return false end

    local pages = collectionPageCount()
    local page = (player.collectionPage or 1) + (delta or 1)
    if page < 1 then page = pages end
    if page > pages then page = 1 end
    player.collectionPage = page
    return true
end

function Game.cycleDeckPresetSlot(state, playerId, delta)
    local player = state.players[playerId]
    if not player then return false end

    local slot = (player.presetSlot or 1) + (delta or 1)
    if slot < 1 then slot = 3 end
    if slot > 3 then slot = 1 end
    player.presetSlot = slot

    local status = state.deckPresets[playerId][slot] and "SAVED" or "EMPTY"
    setFeedback(player, "PRESET " .. tostring(slot) .. "/3 - " .. status, 0.8)
    return true
end

function Game.saveDeckPreset(state, playerId, slot)
    local player = state.players[playerId]
    if not player or slot < 1 or slot > 3 then return false end
    if not cards.isValidDeck(player.deck) then
        setFeedback(player, "NEED A VALID 8-CARD DECK", 1.2)
        return false
    end

    state.deckPresets[playerId][slot] = util.deepcopy(player.deck)
    savePresets(state.deckPresets)
    setFeedback(player, "PRESET " .. tostring(slot) .. " SAVED", 1.0)
    return true
end

function Game.loadDeckPreset(state, playerId, slot)
    local player = state.players[playerId]
    if not player or slot < 1 or slot > 3 then return false end
    local preset = state.deckPresets[playerId][slot]

    if not cards.isValidDeck(preset) then
        setFeedback(player, "PRESET " .. tostring(slot) .. " EMPTY", 1.0)
        return false
    end

    player.deck = util.deepcopy(preset)
    player.ready = false
    setFeedback(player, "PRESET " .. tostring(slot) .. " LOADED", 1.0)
    return true
end

function Game.randomizeDeck(state, playerId)
    local player = state.players[playerId]
    if not player then return false end

    player.deck = randomDeck()
    player.ready = false
    setFeedback(player, "RANDOM DECK", 1.0)
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
        if player.infoOpen then
            if layout.collectionPageButtons then
                if hit(layout.collectionPageButtons.prev, x, y) then
                    Game.cycleCollectionPage(state, playerId, -1)
                    emitSound(state, "minecraft:block.note_block.hat", 0.35, 0.9)
                    return
                elseif hit(layout.collectionPageButtons.next, x, y) then
                    Game.cycleCollectionPage(state, playerId, 1)
                    emitSound(state, "minecraft:block.note_block.hat", 0.35, 1.3)
                    return
                end
            end

            if layout.collectionCards then
                for slot, zone in ipairs(layout.collectionCards) do
                    if hit(zone, x, y) then
                        local card = collectionCardForSlot(player, slot)
                        if card then
                            player.infoCardId = card.id
                            emitSound(state, "minecraft:block.note_block.hat", 0.35, 1.3)
                        end
                        return
                    end
                end
            end

            if hit(layout.readyButton, x, y) then
                player.infoOpen = false
                emitSound(state, "minecraft:block.note_block.pling", 0.45, 1.0)
            end
            return
        end

        if hit(layout.infoButton, x, y) then
            player.infoOpen = true
            if not cards.get(player.infoCardId) then
                player.infoCardId = cards.list[1] and cards.list[1].id or nil
            end
            emitSound(state, "minecraft:block.note_block.pling", 0.45, 1.5)
            return
        end

        if hit(layout.modeButton, x, y) then
            Game.toggleGameMode(state, playerId)
            emitSound(state, "minecraft:block.note_block.pling", 0.5, state.gameMode == "bot" and 1.4 or 1.0)
            return
        end

        if hit(layout.botDifficultyButton, x, y)
            and state.gameMode == "bot"
            and playerId ~= state.botPlayerId
        then
            Game.cycleBotDifficulty(state)
            emitSound(state, "minecraft:block.note_block.pling", 0.5, state.botDifficulty == "hard" and 1.7 or 1.2)
            return
        end

        if layout.collectionPageButtons then
            if hit(layout.collectionPageButtons.prev, x, y) then
                Game.cycleCollectionPage(state, playerId, -1)
                emitSound(state, "minecraft:block.note_block.hat", 0.35, 0.9)
                return
            elseif hit(layout.collectionPageButtons.next, x, y) then
                Game.cycleCollectionPage(state, playerId, 1)
                emitSound(state, "minecraft:block.note_block.hat", 0.35, 1.3)
                return
            end
        end

        if state.gameMode == "bot" and playerId == state.botPlayerId then
            return
        end

        if layout.presetButtons then
            if hit(layout.presetButtons.prev, x, y) then
                Game.cycleDeckPresetSlot(state, playerId, -1)
                emitSound(state, "minecraft:block.note_block.hat", 0.4, 0.9)
                return
            end

            if hit(layout.presetButtons.next, x, y) then
                Game.cycleDeckPresetSlot(state, playerId, 1)
                emitSound(state, "minecraft:block.note_block.hat", 0.4, 1.3)
                return
            end

            if hit(layout.presetButtons.save, x, y) then
                Game.saveDeckPreset(state, playerId, player.presetSlot or 1)
                emitSound(state, "minecraft:block.note_block.chime", 0.45, 1.2)
                return
            end

            if hit(layout.presetButtons.load, x, y) then
                Game.loadDeckPreset(state, playerId, player.presetSlot or 1)
                emitSound(state, "minecraft:block.note_block.hat", 0.4, 1.1)
                return
            end

            if hit(layout.presetButtons.random, x, y) then
                Game.randomizeDeck(state, playerId)
                emitSound(state, "minecraft:block.note_block.pling", 0.45, 1.5)
                return
            end
        end

        if layout.collectionCards then
            for slot, zone in ipairs(layout.collectionCards) do
                if hit(zone, x, y) then
                    local card = collectionCardForSlot(player, slot)
                    if card then
                        Game.toggleDeckCard(state, playerId, card.id)
                        emitSound(state, "minecraft:block.note_block.hat", 0.4, 1.2)
                    end
                    return
                end
            end
        end

        if hit(layout.readyButton, x, y) then
            if not cards.isValidDeck(player.deck) then
                player.ready = false
                setFeedback(player, "SELECT EXACTLY 8 CARDS", 1.4)
                emitSound(state, "minecraft:block.note_block.bass", 0.5, 0.7)
                return
            end

            player.ready = not player.ready
            emitSound(state, "minecraft:block.note_block.hat", 0.5, player.ready and 1.4 or 0.8)

            if state.gameMode == "bot"
                and playerId ~= state.botPlayerId
                and player.ready
            then
                state.players[state.botPlayerId].ready = true
            end

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
        if state.gameMode == "bot" and playerId == state.botPlayerId then return end

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

            if state.gameMode == "bot"
                and playerId ~= state.botPlayerId
                and player.rematch
            then
                state.players[state.botPlayerId].rematch = true
            end

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
        if state.stats then state.stats.elapsed = state.stats.elapsed + dt end

        local multiplier = state.overtime and config.MATCH.overtimeMultiplier or 1
        local emeraldRate = config.MATCH.emeraldPerSecond * multiplier

        for playerId = 1, 2 do
            local player = state.players[playerId]
            local boost = 0

            for _, entity in ipairs(state.entities) do
                if entity.alive and entity.owner == playerId and entity.emeraldBoost then
                    boost = boost + entity.emeraldBoost
                end
            end

            local baseGain = emeraldRate * dt
            local bonusGain = baseGain * boost
            local potentialGain = baseGain + bonusGain
            local available = math.max(0, player.maxEmeralds - player.emeralds)
            local actualGain = math.min(available, potentialGain)

            player.emeralds = player.emeralds + actualGain

            if state.stats then
                local playerStats = state.stats.players[playerId]
                playerStats.emeraldGenerated = playerStats.emeraldGenerated + actualGain
                playerStats.emeraldWasted = playerStats.emeraldWasted + math.max(0, potentialGain - actualGain)

                local baseRealized = math.min(available, baseGain)
                local bonusAvailable = math.max(0, available - baseRealized)
                local realizedBonus = math.min(bonusAvailable, bonusGain)
                playerStats.villagerBonus = playerStats.villagerBonus + realizedBonus

                -- Attribute realized economy value back to the card that
                -- created each living boost unit. This makes Villager useful
                -- in balance reports even though it deals no damage.
                if realizedBonus > 0 and boost > 0 then
                    for _, entity in ipairs(state.entities) do
                        if entity.alive
                            and entity.owner == playerId
                            and entity.emeraldBoost
                            and entity.sourceCardId
                        then
                            local share = realizedBonus * entity.emeraldBoost / boost
                            local cardStats = getCardStats(state, playerId, entity.sourceCardId)
                            cardStats.emeraldBonus = cardStats.emeraldBonus + share
                        end
                    end
                end
            end
        end
    end

    updatePendingSpells(state, dt)

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
    state.pendingSpells = {}
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
        if card.id == "falling_anvil" then
            castFallingAnvil(state, owner, card, x, y)
        else
            castArrows(state, owner, card, x, y)
        end
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
    state.pendingSpells = {}
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

function Game.getMatchStats(state, playerId)
    if not state.stats then return nil end
    local playerStats = state.stats.players[playerId]
    if not playerStats then return nil end

    local bestCardId = nil
    local bestValue = -1
    for cardId, stat in pairs(playerStats.cards) do
        local value = stat.towerDamage * 1.5 + stat.unitDamage + stat.kills * 75 + stat.towersKilled * 400
        if value > bestValue then
            bestValue = value
            bestCardId = cardId
        end
    end

    return {
        elapsed = state.stats.elapsed,
        cardsPlayed = playerStats.cardsPlayed,
        emeraldSpent = playerStats.emeraldSpent,
        emeraldGenerated = playerStats.emeraldGenerated,
        villagerBonus = playerStats.villagerBonus,
        emeraldWasted = playerStats.emeraldWasted,
        unitDamage = playerStats.unitDamage,
        towerDamage = playerStats.towerDamage,
        kills = playerStats.kills,
        towersKilled = playerStats.towersKilled,
        bestCardId = bestCardId,
        bestCard = bestCardId and cards.get(bestCardId) or nil,
        cardStats = playerStats.cards,
    }
end

function Game.getCardForSlot(state, playerId, slot)
    return cards.get(state.players[playerId].hand[slot])
end

function Game.getCards()
    return cards.list
end

return Game

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

local PRESET_TEMP_FILE = PRESET_FILE .. ".tmp"
local PRESET_BACKUP_FILE = PRESET_FILE .. ".bak"

local function presetPathExists(path)
    if not fs or not fs.exists then return false end
    local ok, exists = pcall(fs.exists, path)
    return ok and exists == true
end

local function safePresetDelete(path)
    if not presetPathExists(path) then return true end
    if fs.isDir then
        local okDir, isDir = pcall(fs.isDir, path)
        if not okDir or isDir then return false end
    end
    local ok = pcall(fs.delete, path)
    return ok
end

local function readPresetBody(path)
    if not presetPathExists(path) then return nil end

    if fs.isDir then
        local okDir, isDir = pcall(fs.isDir, path)
        if not okDir or isDir then return nil end
    end

    local okOpen, handle = pcall(fs.open, path, "r")
    if not okOpen or not handle then return nil end

    local okRead, raw = pcall(handle.readAll)
    pcall(handle.close)
    if not okRead then return nil end
    return raw
end

local function decodePresets(raw)
    if type(raw) ~= "string"
        or not textutils
        or not textutils.unserialize
    then
        return nil
    end

    local ok, decoded = pcall(textutils.unserialize, raw)
    if not ok or type(decoded) ~= "table" then return nil end
    if type(decoded[1]) ~= "table" or type(decoded[2]) ~= "table" then
        return nil
    end

    local presets = emptyPresets()
    for playerId = 1, 2 do
        for slot = 1, 3 do
            local deck = decoded[playerId][slot]
            if deck ~= nil then
                if not cards.isValidDeck(deck) then return nil end
                presets[playerId][slot] = util.deepcopy(deck)
            end
        end
    end
    return presets
end

local function loadPresets()
    if not fs or not fs.open or not fs.exists then
        return emptyPresets()
    end

    local candidates = {
        PRESET_FILE,
        PRESET_TEMP_FILE,
        PRESET_BACKUP_FILE,
    }

    for index, path in ipairs(candidates) do
        local presets = decodePresets(readPresetBody(path))
        if presets then
            if index > 1 and fs.move and fs.delete then
                -- Recover a fully serialized transaction left behind by a
                -- reboot/power loss between old->backup and temp->final.
                safePresetDelete(PRESET_FILE)
                local promoted = pcall(fs.move, path, PRESET_FILE)
                if promoted then
                    safePresetDelete(PRESET_BACKUP_FILE)
                    safePresetDelete(PRESET_TEMP_FILE)
                end
            elseif index == 1 then
                -- A valid final file wins; stale transaction debris can be
                -- discarded without risking the recovered presets.
                safePresetDelete(PRESET_BACKUP_FILE)
                safePresetDelete(PRESET_TEMP_FILE)
            end
            return presets
        end
    end

    return emptyPresets()
end

local function savePresets(presets)
    if not fs or not fs.open or not textutils or not textutils.serialize then
        return nil
    end

    -- A partially available filesystem API is a real persistence failure, not
    -- the "plain Lua/no filesystem" case where presets intentionally remain
    -- memory-only.
    if not fs.exists or not fs.delete or not fs.move then
        return false
    end

    if not safePresetDelete(PRESET_TEMP_FILE)
        or not safePresetDelete(PRESET_BACKUP_FILE)
    then
        return false
    end

    local okOpen, handle = pcall(fs.open, PRESET_TEMP_FILE, "w")
    if not okOpen or not handle then return false end

    local ok, serialized = pcall(textutils.serialize, presets)
    if ok then ok = pcall(handle.write, serialized) end
    pcall(handle.close)

    if not ok then
        safePresetDelete(PRESET_TEMP_FILE)
        return false
    end

    -- Move the old valid file aside only after the replacement has been fully
    -- written. A failed final move can then restore the previous presets.
    if presetPathExists(PRESET_FILE) then
        local movedOld = pcall(fs.move, PRESET_FILE, PRESET_BACKUP_FILE)
        if not movedOld then
            safePresetDelete(PRESET_TEMP_FILE)
            return false
        end
    end

    local movedNew = pcall(fs.move, PRESET_TEMP_FILE, PRESET_FILE)
    if not movedNew then
        safePresetDelete(PRESET_FILE)
        if presetPathExists(PRESET_BACKUP_FILE) then
            pcall(fs.move, PRESET_BACKUP_FILE, PRESET_FILE)
        end
        safePresetDelete(PRESET_TEMP_FILE)
        return false
    end

    safePresetDelete(PRESET_BACKUP_FILE)
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
        evolutionPlays = 0,
        playHistory = {},
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
            evolutionPlays = 0,
        }
        playerStats.cards[cardId] = stat
    end
    return stat
end

local function otherPlayer(playerId)
    return playerId == 1 and 2 or 1
end

local function deckHasCard(deck, cardId)
    if not cardId then return false end
    for _, id in ipairs(deck or {}) do
        if id == cardId then return true end
    end
    return false
end

local function validateEvolutionCard(player)
    if not player then return false end

    local valid = player.evolutionCardId
        and deckHasCard(player.deck, player.evolutionCardId)
        and cards.isSelectable(player.evolutionCardId)
        and cards.hasEvolution(player.evolutionCardId)

    if not valid then
        player.evolutionCardId = nil
        player.evolutionProgress = 0
        player.evolutionSelecting = false
        return false
    end

    return true
end

local function newPlayer(playerId)
    return {
        id = playerId,
        ready = false,
        rematch = false,
        emeralds = config.MATCH.emeraldStart,
        maxEmeralds = config.MATCH.emeraldMax,
        -- Lobby boot state is intentionally empty. Players build an 8-card
        -- deck manually, load a preset, or use RANDOM before they can READY.
        deck = {},
        hand = {},
        queue = {},
        selectedSlot = nil,
        evolutionCardId = nil,
        evolutionProgress = 0,
        evolutionSelecting = false,
        infoOpen = false,
        rulesetOpen = false,
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
    player.evolutionProgress = 0
    player.evolutionSelecting = false
    validateEvolutionCard(player)
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
    if state.headlessSimulation then return end
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

local function addBeamEffect(state, source, target)
    if state.headlessSimulation then return end
    local lifetime = 0.12
    table.insert(state.effects, {
        kind = "guardian_beam",
        x = source.x,
        y = source.y,
        x2 = target.x,
        y2 = target.y,
        charge = source.beamCharge or 0,
        ttl = lifetime,
        duration = lifetime,
        owner = source.owner,
    })
end

local function addFangEffect(state, kind, pending, ttl)
    if state.headlessSimulation then return end
    local lifetime = ttl or 0.35
    table.insert(state.effects, {
        kind = kind,
        x = pending.x,
        y = pending.y,
        x2 = pending.x2,
        y2 = pending.y2,
        mode = pending.mode,
        radius = pending.spec and pending.spec.ringRadius or 5,
        width = pending.spec and pending.spec.lineHalfWidth or 2.4,
        ttl = lifetime,
        duration = lifetime,
        owner = pending.owner,
    })
end

local SPATIAL_CELL_SIZE = 16
local SPATIAL_KEY_STRIDE = 1024

local function spatialCellCoords(x, y)
    return math.floor((x or 0) / SPATIAL_CELL_SIZE),
        math.floor((y or 0) / SPATIAL_CELL_SIZE)
end

local function spatialKey(cx, cy)
    -- Arena/query cell X is tiny compared with this stride, so this numeric
    -- key is collision-free for every reachable arena/query coordinate and
    -- avoids allocating "x:y" strings in combat hotpaths.
    return cy * SPATIAL_KEY_STRIDE + cx
end

local function ensureSpatialIndex(state)
    if not state.spatialIndex then
        state.spatialIndex = {
            cellSize = SPATIAL_CELL_SIZE,
            buckets = { [1] = {}, [2] = {} },
        }
    end
    return state.spatialIndex
end

local function removeSpatialEntity(state, entity)
    if not entity or not entity._spatialKey or not entity._spatialOwner then
        return
    end

    local index = state.spatialIndex
    local ownerBuckets = index
        and index.buckets
        and index.buckets[entity._spatialOwner]
    local bucket = ownerBuckets and ownerBuckets[entity._spatialKey]
    if bucket then
        bucket[entity.id] = nil
        if next(bucket) == nil then
            ownerBuckets[entity._spatialKey] = nil
        end
    end

    entity._spatialKey = nil
    entity._spatialOwner = nil
end

local function indexSpatialEntity(state, entity)
    if not entity or not entity.alive then return end
    if entity.owner ~= 1 and entity.owner ~= 2 then return end

    local index = ensureSpatialIndex(state)
    local cx, cy = spatialCellCoords(entity.x, entity.y)
    local key = spatialKey(cx, cy)

    if entity._spatialKey == key
        and entity._spatialOwner == entity.owner
    then
        return
    end

    removeSpatialEntity(state, entity)

    local ownerBuckets = index.buckets[entity.owner]
    local bucket = ownerBuckets[key]
    if not bucket then
        bucket = {}
        ownerBuckets[key] = bucket
    end
    bucket[entity.id] = entity
    entity._spatialKey = key
    entity._spatialOwner = entity.owner
end

local function rebuildSpatialIndex(state)
    state.spatialIndex = {
        cellSize = SPATIAL_CELL_SIZE,
        buckets = { [1] = {}, [2] = {} },
    }

    for order, entity in ipairs(state.entities or {}) do
        entity._spatialKey = nil
        entity._spatialOwner = nil
        entity._spatialOrder = order
        if entity.alive then
            indexSpatialEntity(state, entity)
        end
    end
end

local function spatialCandidatesInBounds(
    state,
    owner,
    minX,
    minY,
    maxX,
    maxY
)
    local index = state.spatialIndex
    local ownerBuckets = index and index.buckets and index.buckets[owner]
    if not ownerBuckets then
        return state.entitiesByOwner
            and state.entitiesByOwner[owner]
            or state.entities
    end

    local minCx, minCy = spatialCellCoords(minX, minY)
    local maxCx, maxCy = spatialCellCoords(maxX, maxY)
    local out = {}

    for cx = minCx, maxCx do
        for cy = minCy, maxCy do
            local bucket = ownerBuckets[spatialKey(cx, cy)]
            if bucket then
                for _, entity in pairs(bucket) do
                    if entity.alive then out[#out + 1] = entity end
                end
            end
        end
    end

    table.sort(out, function(a, b)
        local ao = a._spatialOrder or a.id
        local bo = b._spatialOrder or b.id
        if ao == bo then return a.id < b.id end
        return ao < bo
    end)
    return out
end

local function spatialCandidatesInRadius(state, owner, x, y, radius)
    radius = math.max(0, radius or 0)
    return spatialCandidatesInBounds(
        state,
        owner,
        x - radius,
        y - radius,
        x + radius,
        y + radius
    )
end

local function makeBaseEntity(state, owner, kind, x, y)
    local entity = {
        id = state.nextEntityId,
        _spatialOrder = #(state.entities or {}) + 1,
        owner = owner,
        kind = kind,
        x = x,
        y = y,
        alive = true,
        targetId = nil,
        -- targetId may change while approaching; lockedTargetId is set only
        -- once a unit actually commits an attack to that target.
        lockedTargetId = nil,
        attackCooldownLeft = 0,
    }
    state.nextEntityId = state.nextEntityId + 1
    state.entityById = state.entityById or {}
    state.entityById[entity.id] = entity

    state.entitiesByOwner = state.entitiesByOwner
        or { [1] = {}, [2] = {} }
    if owner == 1 or owner == 2 then
        local owned = state.entitiesByOwner[owner]
        owned[#owned + 1] = entity
    end
    indexSpatialEntity(state, entity)

    return entity
end

local function registerEmeraldBoost(state, entity)
    local boost = tonumber(entity and entity.emeraldBoost) or 0
    local owner = entity and entity.owner
    if boost == 0 or (owner ~= 1 and owner ~= 2) then return end

    state.emeraldBoost = state.emeraldBoost or { [1] = 0, [2] = 0 }
    state.emeraldBoostSources = state.emeraldBoostSources
        or { [1] = {}, [2] = {} }

    state.emeraldBoost[owner] = (state.emeraldBoost[owner] or 0) + boost
    state.emeraldBoostSources[owner][entity.id] = entity
end

local function unregisterEmeraldBoost(state, entity)
    local boost = tonumber(entity and entity.emeraldBoost) or 0
    local owner = entity and entity.owner
    if boost == 0 or (owner ~= 1 and owner ~= 2) then return end

    state.emeraldBoost = state.emeraldBoost or { [1] = 0, [2] = 0 }
    state.emeraldBoostSources = state.emeraldBoostSources
        or { [1] = {}, [2] = {} }

    state.emeraldBoost[owner] = math.max(
        0,
        (state.emeraldBoost[owner] or 0) - boost
    )
    state.emeraldBoostSources[owner][entity.id] = nil
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
    entity.slowEffects = {}
    entity.periodicSpawnTimer = entity.periodicSpawn
        and (entity.periodicSpawn.initialDelay or entity.periodicSpawn.interval or 8)
        or nil
    entity.periodicSpawnTotal = 0
    entity.periodicSpawnAlive = 0
    entity.emeraldPulseTimer = entity.emeraldBoost and 0.25 or nil
    entity.beamCharge = entity.beam and 0 or nil
    entity.beamTickTimer = entity.beam and 0 or nil
    entity.beamTargetId = nil
    entity.groundPulseTimer = entity.groundPulse
        and (entity.groundPulse.initialDelay or entity.groundPulse.interval or 2)
        or nil

    if entity.globalEnemyMoveSlow or state.globalMovementAuraActive then
        state.globalMovementAuraDirty = true
    end

    registerEmeraldBoost(state, entity)
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
    entity.periodicSpawnTotal = 0
    entity.periodicSpawnAlive = 0

    if entity.globalEnemyMoveSlow then
        state.globalMovementAuraDirty = true
    end

    registerEmeraldBoost(state, entity)
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
        entity.attackRange = (config.TOWERS and config.TOWERS.kingRange) or 27
        entity.attackCooldown = 0.90
    else
        entity.name = "Princess Tower"
        entity.icon = "T"
        entity.maxHp = 1501
        entity.damage = 80
        entity.attackRange = (config.TOWERS and config.TOWERS.princessRange) or 42.5
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

    -- All engine-created entities are indexed by id. This avoids repeated
    -- linear scans for target locks and projectile tracking in headless
    -- benchmarks without changing target selection or combat timing.
    if state.entityById then
        local entity = state.entityById[id]
        if entity and entity.alive then return entity end
        return nil
    end

    -- Compatibility fallback for any externally constructed legacy state.
    for _, entity in ipairs(state.entities) do
        if entity.id == id and entity.alive then
            return entity
        end
    end
    return nil
end

local function attackReachAgainst(attacker, candidate)
    if attacker.hybridAttack and not candidate.flying then
        return attacker.hybridAttack.meleeRange or 2.5
    end

    if attacker.proximityExplosion then
        return attacker.proximityExplosion.triggerRange
            or attacker.attackRange
            or 0
    end

    return attacker.attackRange or 0
end

local function canAttackWaterTarget(attacker, candidate)
    if not candidate.waterOnly then return true end

    -- Air/water units can physically occupy the river, while towers and
    -- buildings do not need pathing and are already range-gated by their own
    -- acquireTarget branches.
    if attacker.flying
        or attacker.waterOnly
        or attacker.kind == "tower"
        or attacker.kind == "building"
    then
        return true
    end

    local requiredReach = arena.distanceToGroundReach(
        candidate.x,
        candidate.y
    )

    return attackReachAgainst(attacker, candidate) + 0.001 >= requiredReach
end

local function targetAllowed(attacker, candidate)
    if not candidate.alive or candidate.owner == attacker.owner then return false end
    if candidate.flying and not attacker.canAttackAir then return false end
    -- Ground-erupting Fang attacks cannot interact with water-only targets.
    -- Reject them during acquisition so the Evoker never locks a Guardian it
    -- can never damage.
    if attacker.fangAttack and candidate.waterOnly then return false end
    if not canAttackWaterTarget(attacker, candidate) then return false end

    if attacker.kind == "tower" then
        return candidate.kind == "unit" or candidate.kind == "building"
    end

    if attacker.kind == "building" then
        return candidate.kind == "unit"
    end

    if attacker.targetMode == "buildings" then
        return candidate.kind == "building" or candidate.kind == "tower"
    end

    return true
end

local function findNearest(state, entity, filter, maxRange)
    local best = nil
    local bestDistanceSq = math.huge
    local maxRangeSq = maxRange and maxRange * maxRange or nil
    local enemyOwner = otherPlayer(entity.owner)

    local function consider(candidate)
        if candidate.id == entity.id
            or not targetAllowed(entity, candidate)
            or (filter and not filter(candidate))
        then
            return
        end

        local d2 = util.distanceSquared(
            entity.x,
            entity.y,
            candidate.x,
            candidate.y
        )
        if maxRangeSq and d2 > maxRangeSq then return end

        -- The former ordered candidate list was ID-sorted before using a
        -- strict distance comparison. Preserve that exact tie behavior
        -- explicitly without allocating/sorting a query result table.
        if d2 < bestDistanceSq
            or (
                d2 == bestDistanceSq
                and (not best or candidate.id < best.id)
            )
        then
            bestDistanceSq = d2
            best = candidate
        end
    end

    local index = maxRange and state.spatialIndex or nil
    local ownerBuckets = index
        and index.buckets
        and index.buckets[enemyOwner]

    if maxRange and ownerBuckets then
        local minCx, minCy = spatialCellCoords(
            entity.x - maxRange,
            entity.y - maxRange
        )
        local maxCx, maxCy = spatialCellCoords(
            entity.x + maxRange,
            entity.y + maxRange
        )

        for cx = minCx, maxCx do
            for cy = minCy, maxCy do
                local bucket = ownerBuckets[spatialKey(cx, cy)]
                if bucket then
                    for _, candidate in pairs(bucket) do
                        if candidate.alive then consider(candidate) end
                    end
                end
            end
        end
    else
        local candidates = state.entitiesByOwner
            and state.entitiesByOwner[enemyOwner]
            or state.entities
        for _, candidate in ipairs(candidates) do
            consider(candidate)
        end
    end

    return best, best and math.sqrt(bestDistanceSq) or math.huge
end

local function preferredTowerObjective(state, entity)
    local enemyId = otherPlayer(entity.owner)
    local lane = arena.laneForX(entity.x)
    local lanePrincess = nil
    local kingTower = nil
    local fallbackPrincess = nil
    local fallbackDistance = math.huge

    local candidates = state.entitiesByOwner
        and state.entitiesByOwner[enemyId]
        or state.entities

    for _, candidate in ipairs(candidates) do
        if candidate.alive
            and candidate.owner == enemyId
            and candidate.kind == "tower"
        then
            if candidate.towerType == "king" then
                kingTower = candidate
            elseif candidate.towerType == "princess" then
                local candidateLane = arena.laneForX(candidate.x)
                if candidateLane == lane then
                    lanePrincess = candidate
                else
                    local d2 = util.distanceSquared(
                        entity.x,
                        entity.y,
                        candidate.x,
                        candidate.y
                    )
                    if d2 < fallbackDistance then
                        fallbackDistance = d2
                        fallbackPrincess = candidate
                    end
                end
            end
        end
    end

    -- Clash-style lane objective:
    -- 1) attack the Princess Tower belonging to the current lane;
    -- 2) once that tower is gone, continue into the King Tower;
    -- 3) only use the opposite Princess Tower as a final fallback if no King
    --    exists (mostly useful for admin/custom scenarios).
    return lanePrincess or kingTower or fallbackPrincess
end

local function acquireTarget(state, entity)
    if entity.passive or entity.targetMode == "none" then
        return nil
    end

    if entity.kind == "tower" then
        return findNearest(state, entity, function(candidate)
            return candidate.kind == "unit" or candidate.kind == "building"
        end, entity.attackRange)
    end

    if entity.kind == "building" then
        return findNearest(state, entity, function(candidate)
            return candidate.kind == "unit"
        end, entity.attackRange)
    end

    -- Troops/buildings may distract a marching unit, but towers do not take
    -- part in generic aggro selection. Tower choice is lane-aware below.
    local nearby
    if entity.targetMode == "buildings" then
        nearby = findNearest(
            state,
            entity,
            function(candidate)
                return candidate.kind == "building"
            end,
            entity.aggroRange
        )
    else
        nearby = findNearest(
            state,
            entity,
            function(candidate)
                return candidate.kind ~= "tower"
            end,
            entity.aggroRange
        )
    end

    if nearby then return nearby end

    local tower = preferredTowerObjective(state, entity)
    if tower then return tower end

    return findNearest(state, entity, nil, nil)
end

local updateGroundPulse

local function refreshMovementSlow(entity)
    local effects = entity.slowEffects
    if type(effects) ~= "table" then
        if not entity.slowRemaining or entity.slowRemaining <= 0 then
            entity.slowRemaining = 0
            entity.slowFactor = 1
        end
        return
    end

    if #effects == 0 then
        entity.slowRemaining = 0
        entity.slowFactor = 1
        return
    end

    local strongest = 1
    local strongestRemaining = 0
    for _, effect in ipairs(effects) do
        local remaining = math.max(0, effect.remaining or 0)
        if remaining > 0 then
            local factor = util.clamp(effect.factor or 1, 0, 1)
            if factor < strongest - 1e-9 then
                strongest = factor
                strongestRemaining = remaining
            elseif math.abs(factor - strongest) <= 1e-9 then
                strongestRemaining = math.max(strongestRemaining, remaining)
            end
        end
    end

    entity.slowFactor = strongest
    entity.slowRemaining = strongest < 1 and strongestRemaining or 0
end

local function updateMovementSlows(entity, dt)
    local effects = entity.slowEffects
    if type(effects) == "table" and #effects > 0 then
        local write = 1
        for read = 1, #effects do
            local effect = effects[read]
            effect.remaining = math.max(0, (effect.remaining or 0) - dt)
            if effect.remaining > 1e-9 then
                effects[write] = effect
                write = write + 1
            end
        end
        for i = write, #effects do effects[i] = nil end
        refreshMovementSlow(entity)
        return
    end

    -- Compatibility path for legacy/debug entities which still provide only
    -- the old aggregate slow fields.
    if entity.slowRemaining and entity.slowRemaining > 0 then
        entity.slowRemaining = math.max(0, entity.slowRemaining - dt)
        if entity.slowRemaining <= 0 then
            entity.slowFactor = 1
        end
    end
end

local function applyMovementSlow(entity, spec)
    if not entity or type(spec) ~= "table" then return 0, false end

    local factor = util.clamp(tonumber(spec.factor) or 1, 0, 1)
    local duration = math.max(0, tonumber(spec.duration) or 0)
    if factor >= 1 or duration <= 0 then return 0, false end

    local effects = entity.slowEffects
    if type(effects) ~= "table" then
        effects = {}
        entity.slowEffects = effects
    end

    -- Preserve externally-created legacy slow state by converting it into the
    -- same paired representation before adding a new effect.
    if #effects == 0
        and entity.slowRemaining
        and entity.slowRemaining > 0
        and (entity.slowFactor or 1) < 1
    then
        effects[1] = {
            factor = util.clamp(entity.slowFactor or 1, 0, 1),
            remaining = entity.slowRemaining,
        }
    end

    -- slowSeconds measures only duration for which this new slow adds actual
    -- control. Equal/stronger effects which already cover part of its window
    -- do not let a weaker hit claim or artificially extend that time.
    local coveredByEqualOrStronger = 0
    for _, effect in ipairs(effects) do
        local remaining = math.max(0, effect.remaining or 0)
        local existingFactor = util.clamp(effect.factor or 1, 0, 1)
        if remaining > 0 and existingFactor <= factor + 1e-9 then
            coveredByEqualOrStronger = math.max(
                coveredByEqualOrStronger,
                remaining
            )
        end
    end

    local effectiveAdded = math.max(0, duration - coveredByEqualOrStronger)
    if effectiveAdded <= 0 then
        refreshMovementSlow(entity)
        return 0, false
    end

    effects[#effects + 1] = {
        factor = factor,
        remaining = duration,
    }
    refreshMovementSlow(entity)
    return effectiveAdded, true
end

local function currentMoveSpeed(entity)
    local speed = entity.moveSpeed or 0
    if entity.slowRemaining and entity.slowRemaining > 0 then
        speed = speed * (entity.slowFactor or 1)
    end
    speed = speed * (entity.globalMoveSpeedFactor or 1)
    return speed
end

local function updateGlobalMovementAuras(state)
    -- Aura values only change when an aura source is spawned/dies or when a
    -- new unit appears while an aura is already active. Avoid a full entity
    -- scan on every 0.10s combat tick in the overwhelmingly common no-aura
    -- case.
    if not state.globalMovementAuraDirty then return end
    state.globalMovementAuraDirty = false

    local slow1, slow2 = 0, 0
    local anyAura = false

    for _, entity in ipairs(state.entities) do
        if entity.alive and entity.globalEnemyMoveSlow then
            anyAura = true
            local slow = util.clamp(entity.globalEnemyMoveSlow, 0, 0.95)
            if entity.owner == 1 then
                slow1 = math.max(slow1, slow)
            else
                slow2 = math.max(slow2, slow)
            end
        end
    end

    state.globalMovementAuraActive = anyAura

    for _, entity in ipairs(state.entities) do
        if entity.kind == "unit" then
            local enemySlow = entity.owner == 1 and slow2 or slow1
            entity.globalMoveSpeedFactor = 1 - enemySlow
        else
            entity.globalMoveSpeedFactor = 1
        end
    end
end

local function advanceMovementPulse(state, entity, oldX, oldY, dt, effectiveSpeed)
    if not entity.groundPulse or not updateGroundPulse then return end

    local moved = util.distance(oldX, oldY, entity.x, entity.y)
    if moved <= 0.0001 then return end

    local speed = math.max(0.0001, effectiveSpeed or currentMoveSpeed(entity))
    local movementTime = math.min(dt, moved / speed)
    updateGroundPulse(state, entity, movementTime)
end

local function moveToward(state, entity, tx, ty, dt)
    local dx = tx - entity.x
    local dy = ty - entity.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.001 then return false end

    local speed = currentMoveSpeed(entity)
    if speed <= 0 then return false end

    local oldX, oldY = entity.x, entity.y
    local step = math.min(length, speed * dt)
    local nx = entity.x + dx / length * step
    local ny = entity.y + dy / length * step

    if arena.isWalkable(entity, nx, ny) then
        entity.x = nx
        entity.y = ny
    elseif arena.isWalkable(entity, nx, entity.y) then
        entity.x = nx
    elseif arena.isWalkable(entity, entity.x, ny) then
        entity.y = ny
    end

    local moved = util.distance(oldX, oldY, entity.x, entity.y)
    if moved > 0.0001 then
        indexSpatialEntity(state, entity)
        advanceMovementPulse(state, entity, oldX, oldY, dt, speed)
        return true
    end
    return false
end

local function moveAway(state, entity, target, dt)
    local dx = entity.x - target.x
    local dy = entity.y - target.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.001 then
        dx = 0
        dy = entity.owner == 1 and 1 or -1
        length = 1
    end

    local retreatMultiplier = entity.retreatSpeedMultiplier or 1
    local speed = currentMoveSpeed(entity) * retreatMultiplier
    if speed <= 0 then return false end

    local oldX, oldY = entity.x, entity.y
    local step = speed * dt
    local nx = entity.x + dx / length * step
    local ny = entity.y + dy / length * step

    if arena.isWalkable(entity, nx, ny) then
        entity.x = nx
        entity.y = ny
    end

    local moved = util.distance(oldX, oldY, entity.x, entity.y)
    if moved > 0.0001 then
        indexSpatialEntity(state, entity)
        advanceMovementPulse(state, entity, oldX, oldY, dt, speed)
        return true
    end
    return false
end

local damageEntity
local killEntity

local function deactivateEntity(state, entity)
    if not entity or not entity.alive then return false end
    unregisterEmeraldBoost(state, entity)

    if entity.summonerId then
        local summoner = getEntityById(state, entity.summonerId)
        if summoner then
            summoner.periodicSpawnAlive = math.max(
                0,
                (summoner.periodicSpawnAlive or 0) - 1
            )
        end
    end

    removeSpatialEntity(state, entity)
    entity.alive = false
    state.entitiesDirty = true

    if entity.globalEnemyMoveSlow then
        state.globalMovementAuraDirty = true
        -- Aura removal should affect units which have not moved yet in this
        -- same combat tick, not one tick later.
        updateGlobalMovementAuras(state)
    end

    return true
end

local function despawnEntity(state, entity)
    return deactivateEntity(state, entity)
end

local function spawnProjectile(state, attacker, target, damageOverride, visualOverride)
    table.insert(state.projectiles, {
        x = attacker.x,
        y = attacker.y,
        targetId = target.id,
        owner = attacker.owner,
        sourceCardId = attacker.sourceCardId,
        sourceEntityId = attacker.id,
        damage = damageOverride or attacker.damage,
        speed = attacker.projectileSpeed or 50,
        visual = visualOverride
            or attacker.projectileVisual
            or (attacker.sourceCardId == "skeleton" and "arrow")
            or (attacker.sourceCardId == "cannon" and "cannonball")
            or (attacker.kind == "tower" and "tower_shot")
            or "shot",
        splashRadius = attacker.projectileSplashRadius,
        splashEffect = attacker.projectileSplashEffect,
        -- Projectile code only reads this immutable combat spec. Sharing the
        -- entity-owned table avoids one short-lived allocation per shot.
        onHitSlow = attacker.onHitSlow,
        slowPrimaryOnly = attacker.projectileSlowPrimaryOnly == true,
        alive = true,
    })
end

damageEntity = function(
    state,
    target,
    damage,
    sourceOwner,
    sourceCardId,
    sourceEntityId,
    isReflected
)
    if not target or not target.alive then return end

    damage = math.max(0, damage or 0)
    local actualDamage = math.min(
        damage,
        math.max(0, target.hp or 0)
    )

    if actualDamage > 0 then
        target.damageFlash = 0.18
        addEffect(state, "hit", target.x, target.y, 1.5, 0.16, sourceOwner)

        -- Guardian-style beam charge is disrupted by damage but never hard
        -- reset. "20%" means keep 80% of the current accumulated charge.
        if target.beam then
            local loss = util.clamp(
                target.beam.chargeLossOnHit or 0.20,
                0,
                1
            )
            local before = target.beamCharge or 0
            target.lastBeamChargeBeforeHit = before
            target.beamCharge = before * (1 - loss)
            target.lastBeamChargeAfterHit = target.beamCharge
        end

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

    target.hp = target.hp - damage

    -- Guardian spikes only punish the flying entity which actually caused the
    -- hit. Spells and Crown Towers have no flying source entity and therefore
    -- do not trigger this reflection.
    if actualDamage > 0
        and not isReflected
        and target.spikeReflectFlying
        and sourceEntityId
    then
        local attacker = getEntityById(state, sourceEntityId)
        if attacker and attacker.alive and attacker.flying then
            local reflected = actualDamage * target.spikeReflectFlying
            if reflected > 0 then
                damageEntity(
                    state,
                    attacker,
                    reflected,
                    target.owner,
                    target.sourceCardId,
                    target.id,
                    true
                )
                addEffect(
                    state,
                    "guardian_spike",
                    target.x,
                    target.y,
                    3,
                    0.22,
                    target.owner
                )
            end
        end
    end

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

    addEffect(
        state,
        spec.effectKind or "explosion",
        entity.x,
        entity.y,
        spec.visualRadius or spec.radius or 8,
        spec.visualTtl or 0.55,
        entity.owner
    )
    emitSound(
        state,
        spec.sound or "minecraft:entity.generic.explode",
        spec.soundVolume or 0.9,
        spec.soundPitch or 1.0
    )

    local victims = {}
    local radius = spec.radius or 8
    local radiusSq = radius * radius
    local candidates = spatialCandidatesInRadius(
        state,
        otherPlayer(entity.owner),
        entity.x,
        entity.y,
        radius
    )
    for _, candidate in ipairs(candidates) do
        if candidate.alive
            and candidate.id ~= entity.id
            and candidate.owner ~= entity.owner
            and util.distanceSquared(
                entity.x,
                entity.y,
                candidate.x,
                candidate.y
            ) <= radiusSq
        then
            table.insert(victims, candidate)
        end
    end

    -- Mark the Creeper dead directly. This is a self-detonation, not a normal
    -- death-trigger ability, so getting killed before the fuse completes does
    -- not cause an explosion.
    deactivateEntity(state, entity)
    entity.fuseRemaining = nil

    local battleAtStart = state.phase == "battle"
    for _, victim in ipairs(victims) do
        damageEntity(
            state,
            victim,
            spec.damage or 0,
            entity.owner,
            entity.sourceCardId,
            entity.id
        )
        if battleAtStart and state.phase ~= "battle" then break end
    end
end

local function handleDeathAbilities(state, entity)
    if entity.deathDamage then
        addEffect(state, "explosion", entity.x, entity.y, entity.deathDamage.radius, 0.45, entity.owner)

        local victims = {}
        local radius = entity.deathDamage.radius
        local radiusSq = radius * radius
        local candidates = spatialCandidatesInRadius(
            state,
            otherPlayer(entity.owner),
            entity.x,
            entity.y,
            radius
        )
        for _, candidate in ipairs(candidates) do
            if candidate.alive
                and candidate.owner ~= entity.owner
                and util.distanceSquared(
                    entity.x,
                    entity.y,
                    candidate.x,
                    candidate.y
                ) <= radiusSq
            then
                table.insert(victims, candidate)
            end
        end

        local battleAtStart = state.phase == "battle"
        for _, victim in ipairs(victims) do
            damageEntity(
                state,
                victim,
                entity.deathDamage.damage,
                entity.owner,
                entity.sourceCardId,
                entity.id
            )
            if battleAtStart and state.phase ~= "battle" then break end
        end
    end

    if entity.splitOnDeath then
        local template = cards.getInternalUnitTemplate(entity.splitOnDeath.template)
        if template then
            local count = entity.splitOnDeath.count or 2
            for i = 1, count do
                local direction = i % 2 == 0 and 1 or -1
                local sx = util.clamp(entity.x + direction * 2.2, 2, config.ARENA.width - 2)
                local sy = util.clamp(entity.y + (i - 1) * 1.2, 2, config.ARENA.height - 2)

                -- Offset splits can land beside a bridge in water. The parent
                -- ground unit died on a valid tile, so fall back to that
                -- position instead of silently losing the split unit.
                if not (template.flying or arena.isWalkable(template, sx, sy)) then
                    sx, sy = entity.x, entity.y
                end

                if template.flying or arena.isWalkable(template, sx, sy) then
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
    if not deactivateEntity(state, entity) then return end

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

            state.destroyedSideTowers = state.destroyedSideTowers or {
                [1] = { left = false, right = false },
                [2] = { left = false, right = false },
            }
            local lane = arena.laneForX(entity.x)
            state.destroyedSideTowers[entity.owner][lane] = true

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

    if spec.maxTotal
        and (entity.periodicSpawnTotal or 0) >= spec.maxTotal
    then
        return
    end

    entity.periodicSpawnTimer = (entity.periodicSpawnTimer or spec.interval or 8) - dt
    if entity.periodicSpawnTimer > 0 then return end

    local template = cards.getInternalUnitTemplate(spec.template)
    if not template then
        entity.periodicSpawnTimer = spec.interval or 8
        return
    end

    local aliveSummons = nil
    if spec.maxAlive then
        aliveSummons = entity.periodicSpawnAlive or 0

        if aliveSummons >= spec.maxAlive then
            entity.periodicSpawnTimer = spec.interval or 8
            return
        end
    end

    local count = spec.count or 1
    if spec.maxAlive and aliveSummons then
        count = math.min(count, math.max(0, spec.maxAlive - aliveSummons))
    end
    if spec.maxTotal then
        count = math.min(
            count,
            math.max(0, spec.maxTotal - (entity.periodicSpawnTotal or 0))
        )
    end

    if count <= 0 then return end

    local radius = spec.radius or 2

    for i = 1, count do
        local angle = ((i - 1) / math.max(1, count)) * math.pi * 2
        local sx = util.clamp(entity.x + math.cos(angle) * radius, 2, config.ARENA.width - 2)
        local sy = util.clamp(entity.y + math.sin(angle) * radius, 2, config.ARENA.height - 2)

        -- A circular offset can land beside a bridge in water. The
        -- summoner itself already occupies a valid tile, so ground summons
        -- fall back to the summoner position instead of silently vanishing.
        if not template.flying and not arena.isWalkable(template, sx, sy) then
            sx, sy = entity.x, entity.y
        end

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
            entity.periodicSpawnAlive = (entity.periodicSpawnAlive or 0) + 1
            entity.periodicSpawnTotal = (entity.periodicSpawnTotal or 0) + 1
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

updateGroundPulse = function(state, entity, dt)
    local spec = entity.groundPulse
    if not spec then return end

    entity.groundPulseTimer = (entity.groundPulseTimer or (spec.interval or 2)) - dt
    if entity.groundPulseTimer > 0 then return end

    local radius = spec.radius or 8
    local radiusSq = radius * radius
    local pulseDamage = spec.damage or 20
    local hitCount = 0
    local victims = {}

    -- Snapshot victims before applying damage. A lethal pulse may split a
    -- Slime/Magma Cube, but newborn split units did not exist when the stomp
    -- happened and must not be hit by that same pulse.
    local candidates = spatialCandidatesInRadius(
        state,
        otherPlayer(entity.owner),
        entity.x,
        entity.y,
        radius
    )
    for _, victim in ipairs(candidates) do
        if victim.alive
            and victim.owner ~= entity.owner
            and victim.kind == "unit"
            and not victim.flying
            and not victim.waterOnly
            and util.distanceSquared(
                entity.x,
                entity.y,
                victim.x,
                victim.y
            ) <= radiusSq
        then
            victims[#victims + 1] = victim
        end
    end

    local battleAtStart = state.phase == "battle"
    for _, victim in ipairs(victims) do
        damageEntity(
            state,
            victim,
            pulseDamage,
            entity.owner,
            entity.sourceCardId,
            entity.id
        )
        hitCount = hitCount + 1
        if battleAtStart and state.phase ~= "battle" then break end
    end

    addEffect(
        state,
        spec.effect or "ground_quake",
        entity.x,
        entity.y,
        radius,
        0.55,
        entity.owner
    )

    entity.lastGroundPulseHits = hitCount
    entity.groundPulseTimer = spec.interval or 2
end

local function pointToSegmentDistance(px, py, x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    local lengthSq = dx * dx + dy * dy
    if lengthSq <= 0.000001 then
        return util.distance(px, py, x1, y1)
    end

    local t = ((px - x1) * dx + (py - y1) * dy) / lengthSq
    t = util.clamp(t, 0, 1)
    local nx = x1 + dx * t
    local ny = y1 + dy * t
    return util.distance(px, py, nx, ny)
end

local function queueEvokerFangs(state, entity, target)
    local spec = entity.fangAttack
    if not spec or target.flying or target.waterOnly then return false end

    local targetDistance = util.distance(entity.x, entity.y, target.x, target.y)
    local closeRange = spec.closeRange or 4
    local mode = targetDistance <= closeRange and "ring" or "line"
    local warning = spec.warning or 0.4

    local pending = {
        kind = "evoker_fangs",
        owner = entity.owner,
        cardId = entity.sourceCardId,
        sourceEntityId = entity.id,
        x = entity.x,
        y = entity.y,
        x2 = target.x,
        y2 = target.y,
        mode = mode,
        remaining = warning,
        delay = warning,
        -- Pending Fang resolution treats the spec as immutable.
        spec = spec,
    }

    state.pendingSpells[#state.pendingSpells + 1] = pending
    addFangEffect(state, "evoker_fangs_warning", pending, warning)
    emitSound(state, "minecraft:entity.evoker.prepare_attack", 0.55, 1.0)
    return true
end

local function resolveEvokerFangs(state, pending)
    local spec = pending.spec or {}
    local damage = spec.damage or 85
    local targets = {}

    local candidates
    if pending.mode == "ring" then
        local ringRadius = spec.ringRadius or 5
        candidates = spatialCandidatesInRadius(
            state,
            otherPlayer(pending.owner),
            pending.x,
            pending.y,
            ringRadius
        )
    else
        local halfWidth = spec.lineHalfWidth or 2.4
        candidates = spatialCandidatesInBounds(
            state,
            otherPlayer(pending.owner),
            math.min(pending.x, pending.x2) - halfWidth,
            math.min(pending.y, pending.y2) - halfWidth,
            math.max(pending.x, pending.x2) + halfWidth,
            math.max(pending.y, pending.y2) + halfWidth
        )
    end

    for _, candidate in ipairs(candidates) do
        if candidate.alive
            and candidate.owner ~= pending.owner
            and not candidate.flying
            and not candidate.waterOnly
            and (
                candidate.kind == "unit"
                or candidate.kind == "building"
                or candidate.kind == "tower"
            )
        then
            local hit = false
            if pending.mode == "ring" then
                local ringRadius = spec.ringRadius or 5
                hit = util.distanceSquared(
                    pending.x,
                    pending.y,
                    candidate.x,
                    candidate.y
                ) <= ringRadius * ringRadius
            else
                hit = pointToSegmentDistance(
                    candidate.x,
                    candidate.y,
                    pending.x,
                    pending.y,
                    pending.x2,
                    pending.y2
                ) <= (spec.lineHalfWidth or 2.4)
            end

            if hit then targets[#targets + 1] = candidate end
        end
    end

    local battleAtStart = state.phase == "battle"
    local processedTargets = 0
    for _, target in ipairs(targets) do
        damageEntity(
            state,
            target,
            damage,
            pending.owner,
            pending.cardId,
            pending.sourceEntityId
        )
        processedTargets = processedTargets + 1
        if battleAtStart and state.phase ~= "battle" then break end
    end

    if battleAtStart and state.stats and pending.cardId then
        local cardStats = getCardStats(state, pending.owner, pending.cardId)
        cardStats.targetsHit = cardStats.targetsHit + processedTargets
    end

    addFangEffect(state, "evoker_fangs_impact", pending, 0.45)
    emitSound(state, "minecraft:entity.evoker_fangs.attack", 0.75, 1.0)
end

local function performAttack(state, entity, target)
    if entity.fangAttack then
        queueEvokerFangs(state, entity, target)
        entity.attackCooldownLeft = entity.attackCooldown or 2.4
        return
    end

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
                entity.sourceCardId,
                entity.id
            )
            entity.attackCooldownLeft = spec.meleeCooldown or entity.attackCooldown or 1
            emitSound(state, "minecraft:entity.player.attack.sweep", 0.35, 1.25)
        end
        return
    end

    if entity.projectileSpeed then
        spawnProjectile(state, entity, target)
    else
        damageEntity(
            state,
            target,
            entity.damage or 0,
            entity.owner,
            entity.sourceCardId,
            entity.id
        )
    end
    entity.attackCooldownLeft = entity.attackCooldown or 1
end

local function updateCombatEntity(state, entity, dt)
    if not entity.alive then return end

    if not state.headlessSimulation then
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
    end

    if entity.remainingLifetime then
        if entity.kind == "building"
            and entity.lifetime
            and entity.lifetime > 0
        then
            -- Clash-style building lifetime: buildings do not stay at full HP
            -- and suddenly disappear. Their original max HP decays linearly
            -- over the configured lifetime. Enemy damage stacks on top, so a
            -- damaged building naturally dies earlier.
            local elapsed = math.min(dt, math.max(0, entity.remainingLifetime))
            entity.remainingLifetime = math.max(0, entity.remainingLifetime - dt)

            local decayMultiplier = (config.BUILDINGS and config.BUILDINGS.lifetimeDecayMultiplier) or 1
            local decayPerSecond = (entity.maxHp / entity.lifetime) * decayMultiplier
            entity.hp = entity.hp - decayPerSecond * elapsed

            if entity.hp <= 0 or entity.remainingLifetime <= 0 then
                killEntity(state, entity, nil, nil)
                return
            end
        else
            -- Units with a lifetime (Piglin, Villager, etc.) keep their normal
            -- timed despawn behavior. Only buildings use HP decay.
            entity.remainingLifetime = entity.remainingLifetime - dt
            if entity.remainingLifetime <= 0 then
                despawnEntity(state, entity)
                addEffect(
                    state,
                    entity.emeraldBoost and "emerald" or "death",
                    entity.x,
                    entity.y,
                    3.5,
                    entity.emeraldBoost and 0.55 or 0.30,
                    entity.owner
                )
                return
            end
        end
    end

    entity.attackCooldownLeft = math.max(0, (entity.attackCooldownLeft or 0) - dt)
    entity.teleportCooldownLeft = math.max(0, (entity.teleportCooldownLeft or 0) - dt)

    updateMovementSlows(entity, dt)

    updatePeriodicSpawn(state, entity, dt)

    if entity.emeraldBoost and not state.headlessSimulation then
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

    local lockedTarget = nil
    if entity.kind == "unit" and entity.lockedTargetId then
        lockedTarget = getEntityById(state, entity.lockedTargetId)
        if lockedTarget and targetAllowed(entity, lockedTarget) then
            entity.targetId = lockedTarget.id
        else
            -- The committed target died or became invalid. Only then may the
            -- unit acquire/lock something new.
            entity.lockedTargetId = nil
            lockedTarget = nil
        end
    end

    local target = lockedTarget or getEntityById(state, entity.targetId)
    if target and not targetAllowed(entity, target) then
        target = nil
        if entity.kind == "unit" then
            entity.lockedTargetId = nil
        end
    end

    -- Units marching toward a tower may be pulled by a closer valid target.
    -- Normal troops can be distracted by nearby enemies. Building-only troops
    -- such as the Iron Golem may only be pulled by actual buildings, which
    -- allows defensive Cannons to kite them toward the middle of the arena.
    if target
        and entity.kind == "unit"
        and not entity.lockedTargetId
        and target.kind == "tower"
    then
        local pullTarget, pullDistance

        if entity.targetMode == "buildings" then
            pullTarget, pullDistance = findNearest(
                state,
                entity,
                function(candidate)
                    return candidate.kind == "building"
                end,
                entity.aggroRange
            )
        else
            pullTarget, pullDistance = findNearest(
                state,
                entity,
                function(candidate)
                    return candidate.kind ~= "tower"
                end,
                entity.aggroRange
            )
        end

        if pullTarget and pullTarget.id ~= target.id then
            local currentDistance = util.distance(
                entity.x,
                entity.y,
                target.x,
                target.y
            )

            if pullDistance < currentDistance then
                target = pullTarget
                entity.targetId = pullTarget.id
            end
        end
    end

    if not target then
        target = acquireTarget(state, entity)
        entity.targetId = target and target.id or nil
    end

    if not target then
        entity.fuseRemaining = nil
        if entity.beam then
            entity.beamCharge = 0
            entity.beamTargetId = nil
            entity.lockedTargetId = nil
        end
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
                indexSpatialEntity(state, entity)
                entity.teleportCooldownLeft = spec.cooldown or 4
                addEffect(state, "teleport", entity.x, entity.y, 4, 0.25, entity.owner)
                emitSound(state, "minecraft:entity.enderman.teleport", 0.7, 1.0)
                distance = util.distance(entity.x, entity.y, target.x, target.y)
            end
        end
    end

    if entity.kind == "unit" and entity.beam then
        local spec = entity.beam

        if distance > attackRange then
            -- Inferno-style lock: leaving beam range drops the current charge.
            entity.beamCharge = 0
            entity.beamTargetId = nil
            entity.lockedTargetId = nil
            entity.targetId = nil
            return
        end

        if entity.beamTargetId ~= target.id then
            entity.beamTargetId = target.id
            entity.beamCharge = 0
            entity.beamTickTimer = 0
            emitSound(state, "minecraft:entity.guardian.attack", 0.35, 1.1)
        end

        entity.lockedTargetId = target.id
        entity.targetId = target.id

        local rampSeconds = math.max(0.05, spec.rampSeconds or 4)
        entity.beamCharge = math.min(
            1,
            (entity.beamCharge or 0) + dt / rampSeconds
        )

        entity.beamTickTimer = (entity.beamTickTimer or 0) - dt
        if entity.beamTickTimer <= 0 then
            local tick = math.max(0.05, spec.tick or 0.25)
            local baseDps = spec.baseDps or 30
            local maxDps = math.max(baseDps, spec.maxDps or baseDps)
            local dps = baseDps
                + (maxDps - baseDps) * (entity.beamCharge or 0)

            damageEntity(
                state,
                target,
                dps * tick,
                entity.owner,
                entity.sourceCardId,
                entity.id
            )
            addBeamEffect(state, entity, target)
            entity.beamTickTimer = entity.beamTickTimer + tick
        else
            addBeamEffect(state, entity, target)
        end

        return
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
            entity.lockedTargetId = target.id
            emitSound(state, "minecraft:entity.creeper.primed", 0.7, 1.0)
            return
        end

        local tx, ty = arena.navigationPoint(entity, target)
        moveToward(state, entity, tx, ty, dt)
        return
    end

    if entity.kind == "unit"
        and entity.preferredMinRange
        and target.kind == "unit"
        and distance < entity.preferredMinRange
    then
        if distance <= attackRange and entity.attackCooldownLeft <= 0 then
            entity.lockedTargetId = target.id
            performAttack(state, entity, target)
        end
        moveAway(state, entity, target, dt)
        return
    end

    if distance <= attackRange then
        if entity.attackCooldownLeft <= 0 then
            if entity.kind == "unit" then
                entity.lockedTargetId = target.id
            end
            performAttack(state, entity, target)
        end
        return
    end

    if entity.kind ~= "unit" then
        entity.targetId = nil
        return
    end

    local tx, ty = arena.navigationPoint(entity, target)
    moveToward(state, entity, tx, ty, dt)
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
                        local splashSq =
                            projectile.splashRadius * projectile.splashRadius
                        local candidates = spatialCandidatesInRadius(
                            state,
                            otherPlayer(projectile.owner),
                            target.x,
                            target.y,
                            projectile.splashRadius
                        )
                        for _, candidate in ipairs(candidates) do
                            if candidate.alive
                                and candidate.owner ~= projectile.owner
                                and util.distanceSquared(
                                    target.x,
                                    target.y,
                                    candidate.x,
                                    candidate.y
                                ) <= splashSq
                            then
                                table.insert(victims, candidate)
                            end
                        end
                        addEffect(
                            state,
                            projectile.splashEffect or "splash",
                            target.x,
                            target.y,
                            projectile.splashRadius,
                            0.30,
                            projectile.owner
                        )
                    else
                        table.insert(victims, target)
                    end

                    local battleAtStart = state.phase == "battle"
                    for _, victim in ipairs(victims) do
                        damageEntity(
                            state,
                            victim,
                            projectile.damage,
                            projectile.owner,
                            projectile.sourceCardId,
                            projectile.sourceEntityId
                        )

                        if battleAtStart and state.phase ~= "battle" then
                            break
                        end

                        local shouldSlow = victim.alive
                            and projectile.onHitSlow
                            and victim.kind == "unit"
                            and (victim.moveSpeed or 0) > 0
                            and (
                                not projectile.slowPrimaryOnly
                                or victim.id == target.id
                            )
                        if shouldSlow then
                            local addedSlow, applied = applyMovementSlow(
                                victim,
                                projectile.onHitSlow
                            )
                            if applied then
                                addEffect(
                                    state,
                                    "slow",
                                    victim.x,
                                    victim.y,
                                    3.5,
                                    0.28,
                                    projectile.owner
                                )
                            end

                            if addedSlow > 0
                                and state.phase == "battle"
                                and state.stats
                                and projectile.sourceCardId
                            then
                                local cardStats = getCardStats(
                                    state,
                                    projectile.owner,
                                    projectile.sourceCardId
                                )
                                cardStats.slowSeconds = cardStats.slowSeconds
                                    + addedSlow
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

    local write = 1
    local count = #state.projectiles
    for read = 1, count do
        local projectile = state.projectiles[read]
        if projectile.alive then
            state.projectiles[write] = projectile
            write = write + 1
        end
    end
    for i = write, count do state.projectiles[i] = nil end
end

local function updateEffects(state, dt)
    if state.headlessSimulation then
        -- Visual effects are intentionally absent in headless benchmarks.
        return
    end

    local write = 1
    local count = #state.effects
    for read = 1, count do
        local effect = state.effects[read]
        effect.ttl = effect.ttl - dt
        if effect.ttl > 0 then
            state.effects[write] = effect
            write = write + 1
        end
    end
    for i = write, count do state.effects[i] = nil end
end

local function cleanupEntities(state)
    local write = 1
    local count = #state.entities
    state.entityById = state.entityById or {}
    state.entitiesByOwner = { [1] = {}, [2] = {} }

    for read = 1, count do
        local entity = state.entities[read]
        if entity.alive then
            state.entities[write] = entity
            state.entityById[entity.id] = entity
            if entity.owner == 1 or entity.owner == 2 then
                local owned = state.entitiesByOwner[entity.owner]
                owned[#owned + 1] = entity
            end
            write = write + 1
        else
            state.entityById[entity.id] = nil
        end
    end

    for i = write, count do state.entities[i] = nil end
    state.entitiesDirty = false
end

local function resetPlayersForMatch(state)
    for playerId = 1, 2 do
        local player = state.players[playerId]
        resetDeck(player)
        player.emeralds = config.MATCH.emeraldStart
        player.towersDestroyed = 0
        player.rematch = false
        player.infoOpen = false
        player.rulesetOpen = false
        player.feedback = nil
        player.feedbackTime = 0
    end
end

local function createTowers(state)
    for _, blueprint in ipairs(arena.towerBlueprints()) do
        spawnTower(state, blueprint)
    end
end

function Game.new(soundCallback, options)
    options = options or {}
    local headlessSimulation = options.headlessSimulation == true

    local state = {
        phase = "lobby",
        players = {
            [1] = newPlayer(1),
            [2] = newPlayer(2),
        },
        entities = {},
        entityById = {},
        entitiesByOwner = { [1] = {}, [2] = {} },
        spatialIndex = {
            cellSize = SPATIAL_CELL_SIZE,
            buckets = { [1] = {}, [2] = {} },
        },
        projectiles = {},
        effects = {},
        pendingSpells = {},
        nextEntityId = 1,
        combatTick = 0,
        countdown = config.MATCH.countdown,
        timeLeft = config.MATCH.normalTime,
        overtime = false,
        tiebreaker = false,
        exitRequested = false,
        globalMovementAuraActive = false,
        globalMovementAuraDirty = false,
        entitiesDirty = false,
        emeraldBoost = { [1] = 0, [2] = 0 },
        emeraldBoostSources = { [1] = {}, [2] = {} },
        destroyedSideTowers = {
            [1] = { left = false, right = false },
            [2] = { left = false, right = false },
        },
        winner = nil,
        resultReason = nil,
        sound = headlessSimulation and nil or soundCallback,
        headlessSimulation = headlessSimulation,
        adminMode = false,
        adminPaused = false,
        adminScenario = nil,
        gameMode = "pvp",
        botPlayerId = 2,
        botDifficulty = "normal",
        ruleset = util.deepcopy(config.RULESET_DEFAULTS or {
            evolutions = true,
        }),
        -- Preset IO is irrelevant to automated matches and was previously
        -- repeated once per simulated game.
        deckPresets = headlessSimulation and emptyPresets() or loadPresets(),
        stats = newMatchStats(),
    }

    -- Do not call resetDeck here: resetDeck intentionally has a safety
    -- fallback to the default deck for match setup, while boot should show an
    -- empty deckbuilder.
    return state
end

function Game.resetLobby(state)
    state.phase = "lobby"
    state.entities = {}
    state.entityById = {}
    state.entitiesByOwner = { [1] = {}, [2] = {} }
    state.spatialIndex = {
        cellSize = SPATIAL_CELL_SIZE,
        buckets = { [1] = {}, [2] = {} },
    }
    state.projectiles = {}
    state.effects = {}
    state.pendingSpells = {}
    state.nextEntityId = 1
    state.combatTick = 0
    state.winner = nil
    state.resultReason = nil
    state.overtime = false
    state.tiebreaker = false
    state.exitRequested = false
    state.globalMovementAuraActive = false
    state.globalMovementAuraDirty = false
    state.entitiesDirty = false
    state.emeraldBoost = { [1] = 0, [2] = 0 }
    state.emeraldBoostSources = { [1] = {}, [2] = {} }
    state.destroyedSideTowers = {
        [1] = { left = false, right = false },
        [2] = { left = false, right = false },
    }
    state.adminMode = false
    state.adminPaused = false
    state.adminScenario = nil

    for playerId = 1, 2 do
        local player = state.players[playerId]
        player.ready = false
        player.rematch = false
        player.infoOpen = false
        player.rulesetOpen = false
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
    state.entityById = {}
    state.entitiesByOwner = { [1] = {}, [2] = {} }
    state.spatialIndex = {
        cellSize = SPATIAL_CELL_SIZE,
        buckets = { [1] = {}, [2] = {} },
    }
    state.projectiles = {}
    state.effects = {}
    state.pendingSpells = {}
    state.nextEntityId = 1
    state.combatTick = 0
    state.winner = nil
    state.resultReason = nil
    state.overtime = false
    state.tiebreaker = false
    state.exitRequested = false
    state.globalMovementAuraActive = false
    state.globalMovementAuraDirty = false
    state.entitiesDirty = false
    state.emeraldBoost = { [1] = 0, [2] = 0 }
    state.emeraldBoostSources = { [1] = {}, [2] = {} }
    state.destroyedSideTowers = {
        [1] = { left = false, right = false },
        [2] = { left = false, right = false },
    }
    state.stats = newMatchStats()
    resetPlayersForMatch(state)
    emitSound(state, "minecraft:block.note_block.pling", 0.7, 1.2)
end

local function beginBattle(state)
    state.phase = "battle"
    state.timeLeft = config.MATCH.normalTime
    state.overtime = false
    state.tiebreaker = false
    createTowers(state)
    emitSound(state, "minecraft:entity.experience_orb.pickup", 0.9, 1.0)
end

-- Automated headless benchmarks do not need to spend CPU stepping through the
-- visual countdown. Countdown ticks only decrement state.countdown and return;
-- they do not change combat state. Reuse the exact normal match reset, then
-- enter battle immediately with the same state the countdown would produce.
function Game.startHeadlessBattle(state, dt)
    if not state or not state.headlessSimulation then
        return false, "HEADLESS SIMULATION REQUIRED"
    end

    Game.startCountdown(state)

    -- Reproduce the exact countdown arithmetic without executing the inert
    -- per-tick engine loop. The returned tick count lets benchmark drivers
    -- preserve bot-update ordering and the one final pre-combat bot update
    -- that normally happens on the tick where countdown reaches zero.
    dt = util.clamp(dt or config.TICK_RATE, 0, 0.25)
    if dt <= 0 then
        return false, "POSITIVE TICK REQUIRED"
    end

    local skippedTicks = 0
    while state.countdown > 0 do
        state.countdown = state.countdown - dt
        skippedTicks = skippedTicks + 1
    end

    beginBattle(state)
    return true, skippedTicks
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

local function lowestLivingTowerHp(state, owner)
    local lowest = math.huge

    for _, entity in ipairs(state.entities) do
        if entity.alive
            and entity.kind == "tower"
            and entity.owner == owner
        then
            lowest = math.min(lowest, math.max(0, entity.hp or 0))
        end
    end

    return lowest
end

local function startTiebreaker(state)
    state.tiebreaker = true
    state.timeLeft = 0
    state.projectiles = {}
    state.pendingSpells = {}
    state.effects = {}
    state.players[1].selectedSlot = nil
    state.players[2].selectedSlot = nil

    -- Once overtime expires, normal combat stops. Only towers remain on
    -- screen while all surviving towers lose equal raw HP, Clash-style.
    local towers = {}
    for _, entity in ipairs(state.entities) do
        if entity.alive and entity.kind == "tower" then
            towers[#towers + 1] = entity
            entity.targetId = nil
            entity.damageFlash = 0.18
            addEffect(state, "tower_warning", entity.x, entity.y, 6, 0.65, entity.owner)
        end
    end
    state.entities = towers
    state.entitiesDirty = false
    state.globalMovementAuraActive = false
    state.globalMovementAuraDirty = false
    state.emeraldBoost = { [1] = 0, [2] = 0 }
    state.emeraldBoostSources = { [1] = {}, [2] = {} }
    state.entityById = {}
    state.entitiesByOwner = { [1] = {}, [2] = {} }
    for _, tower in ipairs(towers) do
        state.entityById[tower.id] = tower
        local owned = state.entitiesByOwner[tower.owner]
        owned[#owned + 1] = tower
    end
    rebuildSpatialIndex(state)

    setFeedback(state.players[1], "TIEBREAKER - ALL TOWERS LOSE HP", 3)
    setFeedback(state.players[2], "TIEBREAKER - ALL TOWERS LOSE HP", 3)
    emitSound(state, "minecraft:block.beacon.deactivate", 1.0, 0.75)
end

local function updateTiebreaker(state, dt)
    local rate = config.MATCH.tiebreakerDamagePerSecond or 300
    local p1Lowest = lowestLivingTowerHp(state, 1)
    local p2Lowest = lowestLivingTowerHp(state, 2)

    if p1Lowest == math.huge or p2Lowest == math.huge then
        if p1Lowest == p2Lowest then
            Game.finish(state, nil, "TIEBREAKER DRAW")
        elseif p1Lowest == math.huge then
            Game.finish(state, 2, "TIEBREAKER")
        else
            Game.finish(state, 1, "TIEBREAKER")
        end
        return
    end

    local firstHp = math.min(p1Lowest, p2Lowest)
    local requestedDamage = rate * dt
    local actualDamage = math.min(requestedDamage, firstHp)

    for _, entity in ipairs(state.entities) do
        if entity.alive and entity.kind == "tower" then
            entity.hp = math.max(0, (entity.hp or 0) - actualDamage)
            entity.damageFlash = 0.14
        end
    end

    if actualDamage + 1e-9 < firstHp then return end

    -- Equal HP drain means the tower that started with the least raw HP
    -- reaches zero first. Exact equal lowest HP produces a genuine draw.
    if math.abs(p1Lowest - p2Lowest) < 1e-9 then
        Game.finish(state, nil, "TIEBREAKER DRAW")
    elseif p1Lowest < p2Lowest then
        Game.finish(state, 2, "TIEBREAKER")
    else
        Game.finish(state, 1, "TIEBREAKER")
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
        -- Pending Anvil resolution treats the spell payload as immutable.
        spell = spell,
    }

    addEffect(state, "anvil_warning", x, y, spell.radius or 5.5, delay, playerId)
    emitSound(state, "minecraft:block.anvil.place", 0.45, 1.7)
end

local function resolveFallingAnvil(state, pending)
    local spell = pending.spell
    local targets = {}
    local radius = spell.radius or 5.5
    local candidates = spatialCandidatesInRadius(
        state,
        otherPlayer(pending.owner),
        pending.x,
        pending.y,
        radius
    )

    for _, entity in ipairs(candidates) do
        if entity.alive
            and entity.owner ~= pending.owner
            and (not spell.groundOnly or not entity.flying)
            and util.distanceSquared(
                pending.x,
                pending.y,
                entity.x,
                entity.y
            ) <= radius * radius
        then
            targets[#targets + 1] = entity
        end
    end

    local battleAtStart = state.phase == "battle"
    local processedTargets = 0
    for _, target in ipairs(targets) do
        local damage = spell.damage or 0
        if target.kind == "tower" then
            damage = damage * (spell.towerMultiplier or 1)
        end
        damageEntity(state, target, damage, pending.owner, pending.cardId)
        processedTargets = processedTargets + 1
        if battleAtStart and state.phase ~= "battle" then break end
    end

    if battleAtStart and state.stats then
        local cardStats = getCardStats(state, pending.owner, pending.cardId)
        cardStats.targetsHit = cardStats.targetsHit + processedTargets
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
    -- Keep a stable reference while compacting in place. Resolving a spell can
    -- end the match (for example, an Anvil killing the King Tower), and
    -- Game.finish() deliberately replaces state.pendingSpells with a fresh
    -- empty table. In that case this update must stop immediately instead of
    -- indexing the newly emptied table with the old count.
    local pendingSpells = state.pendingSpells
    local write = 1
    local count = #pendingSpells

    for read = 1, count do
        local pending = pendingSpells[read]
        pending.remaining = pending.remaining - dt
        if pending.remaining <= 0 then
            if pending.kind == "falling_anvil" then
                resolveFallingAnvil(state, pending)
            elseif pending.kind == "evoker_fangs" then
                resolveEvokerFangs(state, pending)
            end

            if state.pendingSpells ~= pendingSpells then
                return
            end
        else
            pendingSpells[write] = pending
            write = write + 1
        end
    end

    for i = write, count do pendingSpells[i] = nil end
end

local function castArrows(state, playerId, card, x, y)
    addEffect(state, "arrows", x, y, card.spell.radius, 0.45, playerId)

    local targets = {}
    local radius = card.spell.radius
    local candidates = spatialCandidatesInRadius(
        state,
        otherPlayer(playerId),
        x,
        y,
        radius
    )
    for _, entity in ipairs(candidates) do
        if entity.alive
            and entity.owner ~= playerId
            and util.distanceSquared(x, y, entity.x, entity.y)
                <= radius * radius
        then
            table.insert(targets, entity)
        end
    end

    local battleAtStart = state.phase == "battle"
    local processedTargets = 0
    for _, target in ipairs(targets) do
        local damage = card.spell.damage
        if target.kind == "tower" then
            damage = damage * (card.spell.towerMultiplier or 1)
        end
        damageEntity(state, target, damage, playerId, card.id)
        processedTargets = processedTargets + 1
        if battleAtStart and state.phase ~= "battle" then break end
    end

    if battleAtStart and state.stats then
        local cardStats = getCardStats(state, playerId, card.id)
        cardStats.targetsHit = cardStats.targetsHit + processedTargets
    end

    emitSound(state, "minecraft:entity.arrow.shoot", 0.7, 1.1)
end

local function cycleHand(player, slot)
    local playedCard = player.hand[slot]
    local nextCard = table.remove(player.queue, 1)
    player.hand[slot] = nextCard
    table.insert(player.queue, playedCard)
end

function Game.getActiveCardForPlayer(state, playerId, cardId)
    local card = cards.get(cardId)
    local player = state and state.players and state.players[playerId]
    if not card or not player then return card, false end

    if state.phase == "battle"
        and Game.rulesetEnabled(state, "evolutions")
        and player.evolutionCardId == card.id
        and cards.hasEvolution(card.id)
    then
        local cycles = cards.evolutionCycles(card.id)
        if cycles ~= nil and (player.evolutionProgress or 0) >= cycles then
            local evolved = cards.evolvedCopy(card.id)
            if evolved then return evolved, true end
        end
    end

    return card, false
end

function Game.getCardPlayCost(state, playerId, cardId)
    local card = cards.get(cardId)
    local player = state and state.players and state.players[playerId]
    if not card then return nil end

    if player
        and state.phase == "battle"
        and Game.rulesetEnabled(state, "evolutions")
        and player.evolutionCardId == card.id
        and cards.hasEvolution(card.id)
    then
        local cycles = cards.evolutionCycles(card.id)
        if cycles ~= nil and (player.evolutionProgress or 0) >= cycles then
            return cards.evolutionCost(card.id) or card.cost
        end
    end

    return card.cost
end

function Game.playCardFromSlot(state, playerId, slot, x, y)
    local player = state.players[playerId]
    if not player
        or (state.phase ~= "battle" and state.phase ~= "admin")
        or (state.phase == "battle" and state.tiebreaker)
    then
        return false, "NOT PLAYABLE"
    end

    local battlePlay = state.phase == "battle"
    local cardId = player.hand[slot]
    local card = cards.get(cardId)
    if not card then
        setFeedback(player, "CARD ERROR")
        player.selectedSlot = nil
        return false, "CARD ERROR"
    end

    local activeCard, evolutionUsed = Game.getActiveCardForPlayer(
        state,
        playerId,
        card.id
    )
    activeCard = activeCard or card
    local playCost = tonumber(activeCard.cost) or tonumber(card.cost) or 0

    if player.emeralds + 0.0001 < playCost then
        if evolutionUsed then
            setFeedback(
                player,
                string.format("EVOLUTION NEEDS %.1f EMERALDS", playCost),
                1.0
            )
        else
            setFeedback(player, "NOT ENOUGH EMERALDS")
        end
        return false, "NOT ENOUGH EMERALDS"
    end

    if not arena.placementAllowed(
        playerId,
        x,
        y,
        activeCard.placement or card.placement,
        state
    ) then
        setFeedback(player, "INVALID PLACEMENT")
        return false, "INVALID PLACEMENT"
    end

    local evolutionCycles = nil
    if battlePlay
        and Game.rulesetEnabled(state, "evolutions")
        and player.evolutionCardId == card.id
        and cards.hasEvolution(card.id)
    then
        evolutionCycles = cards.evolutionCycles(card.id)
        if evolutionCycles == nil then evolutionCycles = 2 end
    end

    if activeCard.kind == "unit" then
        spawnCardUnit(state, playerId, activeCard, x, y)
        addEffect(state, evolutionUsed and "evolution_spawn" or "spawn", x, y, activeCard.spawnCount and 5 or 3.5, 0.30, playerId)
    elseif activeCard.kind == "building" then
        spawnBuilding(state, playerId, activeCard, x, y)
        addEffect(state, evolutionUsed and "evolution_spawn" or "spawn", x, y, 5, 0.35, playerId)
    elseif activeCard.kind == "spell" then
        -- Card plays are rare compared with combat ticks. Reconcile here so
        -- programmatic/test position edits made outside normal movement cannot
        -- make an immediate AoE spell read stale buckets.
        rebuildSpatialIndex(state)
        local castType = activeCard.spell and activeCard.spell.cast
        if castType == "falling_anvil" then
            castFallingAnvil(state, playerId, activeCard, x, y)
        elseif castType == "arrows" then
            castArrows(state, playerId, activeCard, x, y)
        else
            setFeedback(player, "UNSUPPORTED SPELL")
            return false, "UNSUPPORTED SPELL"
        end
    else
        setFeedback(player, "UNSUPPORTED CARD")
        return false, "UNSUPPORTED CARD"
    end

    player.emeralds = player.emeralds - playCost

    if battlePlay and state.stats then
        local playerStats = state.stats.players[playerId]
        local cardStats = getCardStats(state, playerId, card.id)
        playerStats.cardsPlayed = playerStats.cardsPlayed + 1
        playerStats.emeraldSpent = playerStats.emeraldSpent + playCost
        playerStats.playHistory[#playerStats.playHistory + 1] = card.id
        cardStats.plays = cardStats.plays + 1
        cardStats.emeraldSpent = cardStats.emeraldSpent + playCost

        if evolutionUsed then
            playerStats.evolutionPlays = (playerStats.evolutionPlays or 0) + 1
            cardStats.evolutionPlays = (cardStats.evolutionPlays or 0) + 1
        end
    end

    local deploymentFeedback = card.name .. " DEPLOYED"

    if battlePlay
        and Game.rulesetEnabled(state, "evolutions")
        and player.evolutionCardId == card.id
        and cards.hasEvolution(card.id)
    then
        if evolutionCycles == nil then
            evolutionCycles = cards.evolutionCycles(card.id)
        end
        if evolutionCycles == nil then evolutionCycles = 2 end

        if evolutionUsed then
            player.evolutionProgress = 0
            deploymentFeedback = string.format(
                "EVOLVED %s DEPLOYED (%.1fE)",
                card.name,
                playCost
            )
            emitSound(state, "minecraft:block.amethyst_block.chime", 0.75, 1.65)
        else
            player.evolutionProgress = math.min(
                evolutionCycles,
                (player.evolutionProgress or 0) + 1
            )

            if player.evolutionProgress >= evolutionCycles then
                deploymentFeedback = card.name .. " - EVOLUTION READY"
                emitSound(state, "minecraft:block.amethyst_block.chime", 0.60, 1.35)
            else
                deploymentFeedback = string.format(
                    "%s - EVO %d/%d",
                    card.name,
                    player.evolutionProgress,
                    evolutionCycles
                )
            end
        end
    end

    cycleHand(player, slot)
    player.selectedSlot = nil
    setFeedback(player, deploymentFeedback, evolutionUsed and 1.1 or 0.8)
    emitSound(state, "minecraft:block.amethyst_block.hit", 0.45, evolutionUsed and 1.8 or 1.4)
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
    if not cards.isSelectable(card) then
        setFeedback(player, "DEV CARD - ADMIN ONLY", 1.1)
        return false
    end

    local pos = deckPosition(player.deck, cardId)
    player.ready = false

    if pos then
        table.remove(player.deck, pos)
        if player.evolutionCardId == cardId then
            player.evolutionCardId = nil
            player.evolutionProgress = 0
            player.evolutionSelecting = false
        end
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

function Game.setEvolutionCard(state, playerId, cardId)
    local player = state.players[playerId]
    if not player or state.phase ~= "lobby" then return false end

    player.ready = false
    player.evolutionSelecting = false
    player.evolutionProgress = 0

    if cardId == nil then
        player.evolutionCardId = nil
        setFeedback(player, "EVOLUTION SLOT CLEARED", 0.9)
        return true
    end

    local card = cards.get(cardId)
    if not card then
        setFeedback(player, "UNKNOWN EVOLUTION CARD", 1.0)
        return false
    end

    if not cards.isSelectable(card) then
        setFeedback(player, "DEV EVOLUTION - ADMIN ONLY", 1.2)
        return false
    end

    if not deckHasCard(player.deck, cardId) then
        setFeedback(player, "ADD CARD TO DECK FIRST", 1.2)
        return false
    end

    if not cards.hasEvolution(cardId) then
        setFeedback(player, card.name .. " HAS NO EVOLUTION", 1.2)
        return false
    end

    player.evolutionCardId = cardId
    setFeedback(player, card.name .. " SET AS EVOLUTION", 1.0)
    return true
end

function Game.beginEvolutionSelection(state, playerId)
    local player = state.players[playerId]
    if not player or state.phase ~= "lobby" then return false end

    if player.evolutionCardId then
        return Game.setEvolutionCard(state, playerId, nil)
    end

    local eligible = false
    for _, cardId in ipairs(player.deck) do
        if cards.isSelectable(cardId) and cards.hasEvolution(cardId) then
            eligible = true
            break
        end
    end

    if not eligible then
        player.evolutionSelecting = false
        setFeedback(player, "NO EVOLUTION CARD IN DECK", 1.2)
        return false
    end

    player.evolutionSelecting = true
    player.ready = false
    setFeedback(player, "TAP AN EVO CARD IN YOUR DECK", 1.4)
    return true
end

function Game.validateEvolutionSelection(state, playerId)
    local player = state.players[playerId]
    if not player then return false end
    return validateEvolutionCard(player)
end

function Game.rulesetEnabled(state, key)
    if not state or type(state.ruleset) ~= "table" then return true end
    if state.ruleset[key] == nil then return true end
    return state.ruleset[key] ~= false
end

function Game.setRulesetRule(state, key, value, requestingPlayerId)
    if not state or state.phase ~= "lobby" then return false end
    if type(state.ruleset) ~= "table" then state.ruleset = {} end
    if state.ruleset[key] == nil then return false end

    local enabled = value == true
    if state.ruleset[key] == enabled then return true end

    state.ruleset[key] = enabled

    -- Match-wide rules are shared by both monitors. Any rules change cancels
    -- READY for both players so the countdown can never start under stale
    -- assumptions.
    for playerId = 1, 2 do
        local player = state.players[playerId]
        player.ready = false
        player.rematch = false

        if key == "evolutions" and not enabled then
            player.evolutionProgress = 0
            player.evolutionSelecting = false
        end

        if playerId == requestingPlayerId then
            setFeedback(
                player,
                "EVOLUTIONS " .. (enabled and "ENABLED" or "DISABLED"),
                1.1
            )
        else
            setFeedback(
                player,
                "RULESET UPDATED: EVOS " .. (enabled and "ON" or "OFF"),
                1.1
            )
        end
    end

    return true
end

function Game.toggleRulesetRule(state, key, requestingPlayerId)
    return Game.setRulesetRule(
        state,
        key,
        not Game.rulesetEnabled(state, key),
        requestingPlayerId
    )
end

function Game.openRuleset(state, playerId)
    local player = state and state.players and state.players[playerId]
    if not player or state.phase ~= "lobby" then return false end

    player.rulesetOpen = true
    player.infoOpen = false
    player.evolutionSelecting = false
    return true
end

function Game.closeRuleset(state, playerId)
    local player = state and state.players and state.players[playerId]
    if not player then return false end

    player.rulesetOpen = false
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

    local previous = state.deckPresets[playerId][slot]
        and util.deepcopy(state.deckPresets[playerId][slot])
        or nil

    state.deckPresets[playerId][slot] = util.deepcopy(player.deck)
    local persisted = savePresets(state.deckPresets)

    if persisted == false then
        state.deckPresets[playerId][slot] = previous
        setFeedback(player, "PRESET SAVE FAILED", 1.2)
        return false
    end

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
    validateEvolutionCard(player)
    setFeedback(player, "PRESET " .. tostring(slot) .. " LOADED", 1.0)
    return true
end

function Game.randomizeDeck(state, playerId)
    local player = state.players[playerId]
    if not player then return false end

    player.deck = randomDeck()
    player.ready = false
    validateEvolutionCard(player)
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

        if player.rulesetOpen then
            if hit(layout.rulesetEvolutionButton, x, y) then
                Game.toggleRulesetRule(state, "evolutions", playerId)
                emitSound(
                    state,
                    "minecraft:block.note_block.pling",
                    0.5,
                    Game.rulesetEnabled(state, "evolutions") and 1.45 or 0.75
                )
                return
            end

            if hit(layout.rulesetBackButton or layout.readyButton, x, y) then
                Game.closeRuleset(state, playerId)
                emitSound(state, "minecraft:block.note_block.pling", 0.45, 1.0)
            end
            return
        end

        if hit(layout.rulesetButton, x, y) then
            Game.openRuleset(state, playerId)
            emitSound(state, "minecraft:block.note_block.pling", 0.45, 1.25)
            return
        end

        if hit(layout.infoButton, x, y) then
            player.infoOpen = true
            player.rulesetOpen = false
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

        if hit(layout.evolutionSlot, x, y) then
            Game.beginEvolutionSelection(state, playerId)
            emitSound(state, "minecraft:block.amethyst_block.hit", 0.45, player.evolutionSelecting and 1.5 or 0.9)
            return
        end

        if player.evolutionSelecting and layout.deckSlots then
            for slot, zone in ipairs(layout.deckSlots) do
                if hit(zone, x, y) then
                    local cardId = player.deck[slot]
                    if cardId then
                        Game.setEvolutionCard(state, playerId, cardId)
                        emitSound(state, "minecraft:block.amethyst_block.chime", 0.5, cards.hasEvolution(cardId) and 1.4 or 0.7)
                    end
                    return
                end
            end
        end

        if hit(layout.randomButton, x, y) then
            Game.randomizeDeck(state, playerId)
            emitSound(state, "minecraft:block.note_block.pling", 0.45, 1.5)
            return
        end

        if layout.collectionCards then
            for slot, zone in ipairs(layout.collectionCards) do
                if hit(zone, x, y) then
                    local card = collectionCardForSlot(player, slot)
                    if card then
                        if player.evolutionSelecting then
                            Game.setEvolutionCard(state, playerId, card.id)
                            emitSound(state, "minecraft:block.amethyst_block.chime", 0.5, cards.hasEvolution(card.id) and 1.4 or 0.7)
                        else
                            Game.toggleDeckCard(state, playerId, card.id)
                            emitSound(state, "minecraft:block.note_block.hat", 0.4, 1.2)
                        end
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
        if state.tiebreaker then return end
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
            state.exitRequested = true
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

    -- Normal battle movement/spawn/death/teleport paths maintain the index
    -- incrementally. The admin sandbox intentionally permits direct entity
    -- edits, so only that mode pays for a full authoritative reconcile.
    if isAdmin then rebuildSpatialIndex(state) end

    if isBattle and state.tiebreaker then
        if state.stats then state.stats.elapsed = state.stats.elapsed + dt end
        updateEffects(state, dt)
        updateTiebreaker(state, dt)
        return
    end

    if isBattle then
        if state.stats then state.stats.elapsed = state.stats.elapsed + dt end

        local multiplier = 1
        if state.overtime then
            local finalSeconds = config.MATCH.overtimeFinalSeconds or 30
            local baseMultiplier = config.MATCH.overtimeMultiplier or 2
            local finalMultiplier = config.MATCH.overtimeFinalMultiplier or 3

            if state.timeLeft <= finalSeconds then
                multiplier = finalMultiplier
            elseif state.timeLeft - dt >= finalSeconds then
                multiplier = baseMultiplier
            else
                -- Split a tick that crosses the 0:30 boundary so the boost is
                -- exactly 2x before it and 3x after it, even under a long tick.
                local baseDuration = math.max(0, state.timeLeft - finalSeconds)
                local finalDuration = math.max(0, dt - baseDuration)
                multiplier = (
                    baseDuration * baseMultiplier
                    + finalDuration * finalMultiplier
                ) / math.max(dt, 0.000001)
            end
        end
        local emeraldRate = config.MATCH.emeraldPerSecond * multiplier

        local emeraldBoost = state.emeraldBoost or { [1] = 0, [2] = 0 }
        local emeraldBoostSources = state.emeraldBoostSources
            or { [1] = {}, [2] = {} }

        for playerId = 1, 2 do
            local player = state.players[playerId]
            local boost = emeraldBoost[playerId] or 0

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
                    local boostSources = emeraldBoostSources[playerId]
                    if boostSources then
                        for _, entity in pairs(boostSources) do
                            if entity.alive and entity.sourceCardId then
                                local share = realizedBonus
                                    * entity.emeraldBoost
                                    / boost
                                local cardStats = getCardStats(
                                    state,
                                    playerId,
                                    entity.sourceCardId
                                )
                                cardStats.emeraldBonus =
                                    cardStats.emeraldBonus + share
                            end
                        end
                    end
                end
            end
        end
    end

    updatePendingSpells(state, dt)
    updateGlobalMovementAuras(state)

    -- Freeze the entity count for this tick. Summons/splits created while
    -- updating combat begin acting next tick instead of receiving a hidden
    -- same-tick movement/attack/lifetime update.
    local entityCount = #state.entities
    state.combatTick = (state.combatTick or 0) + 1

    -- Alternate traversal direction to avoid a permanent "earlier entity"
    -- advantage in near-simultaneous combat. This is especially important for
    -- the fixed P1/P2 Crown Tower insertion order.
    if state.combatTick % 2 == 1 then
        for i = 1, entityCount do
            if isBattle and state.phase ~= "battle" then break end
            updateCombatEntity(state, state.entities[i], dt)
        end
    else
        for i = entityCount, 1, -1 do
            if isBattle and state.phase ~= "battle" then break end
            updateCombatEntity(state, state.entities[i], dt)
        end
    end

    if (isBattle and state.phase == "battle") or isAdmin then
        updateProjectiles(state, dt)
        updateEffects(state, dt)
        if state.entitiesDirty then
            cleanupEntities(state)
        end

        if isBattle and state.phase ~= "battle" then
            return
        end

        if isAdmin then
            return
        end

        local previousTimeLeft = state.timeLeft
        state.timeLeft = state.timeLeft - dt

        if state.overtime then
            local finalSeconds = config.MATCH.overtimeFinalSeconds or 30
            if previousTimeLeft > finalSeconds and state.timeLeft <= finalSeconds then
                setFeedback(state.players[1], "FINAL 30 - 3X EMERALDS", 2)
                setFeedback(state.players[2], "FINAL 30 - 3X EMERALDS", 2)
                emitSound(state, "minecraft:block.beacon.power_select", 0.9, 1.35)
            end
        end

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
                    setFeedback(state.players[1], "OVERTIME - 2X EMERALDS", 2)
                    setFeedback(state.players[2], "OVERTIME - 2X EMERALDS", 2)
                end
            else
                startTiebreaker(state)
            end
        end
    end
end

local function clearSimulation(state)
    state.entities = {}
    state.entityById = {}
    state.entitiesByOwner = { [1] = {}, [2] = {} }
    state.spatialIndex = {
        cellSize = SPATIAL_CELL_SIZE,
        buckets = { [1] = {}, [2] = {} },
    }
    state.projectiles = {}
    state.effects = {}
    state.pendingSpells = {}
    state.nextEntityId = 1
    state.combatTick = 0
    state.globalMovementAuraActive = false
    state.globalMovementAuraDirty = false
    state.entitiesDirty = false
    state.emeraldBoost = { [1] = 0, [2] = 0 }
    state.emeraldBoostSources = { [1] = {}, [2] = {} }
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
    state.tiebreaker = false
    state.exitRequested = false
    state.destroyedSideTowers = {
        [1] = { left = false, right = false },
        [2] = { left = false, right = false },
    }

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

    local card
    local evolutionBaseId = tostring(cardId or ""):match("^evo:(.+)$")

    if evolutionBaseId then
        card = cards.evolvedCopy(evolutionBaseId)
        if not card then return false, "UNKNOWN EVOLUTION" end
    else
        card = cards.get(cardId)
        if not card then return false, "UNKNOWN CARD" end
    end

    x = util.clamp(x, 2, config.ARENA.width - 2)
    y = util.clamp(y, 2, config.ARENA.height - 2)

    -- The admin sandbox normally allows free placement for testing. Water-only
    -- units are the exception because their terrain restriction is part of
    -- their combat identity and targetability. Guardian/Elder Guardian must
    -- therefore remain in open river water even in admin mode.
    if card.placement == "water"
        and not arena.placementAllowed(owner, x, y, "water", state)
    then
        return false, "WATER ONLY - PLACE IN OPEN RIVER"
    end

    if card.kind == "unit" then
        spawnCardUnit(state, owner, card, x, y)
        addEffect(
            state,
            evolutionBaseId and "evolution_spawn" or "spawn",
            x,
            y,
            card.spawnCount and 5 or 3.5,
            0.30,
            owner
        )
    elseif card.kind == "building" then
        spawnBuilding(state, owner, card, x, y)
        addEffect(
            state,
            evolutionBaseId and "evolution_spawn" or "spawn",
            x,
            y,
            5,
            0.35,
            owner
        )
    elseif card.kind == "spell" then
        local castType = card.spell and card.spell.cast
        if castType == "falling_anvil" then
            castFallingAnvil(state, owner, card, x, y)
        elseif castType == "arrows" then
            castArrows(state, owner, card, x, y)
        else
            return false, "UNSUPPORTED SPELL"
        end
    else
        return false, "UNSUPPORTED CARD"
    end

    if evolutionBaseId then
        emitSound(state, "minecraft:block.amethyst_block.chime", 0.65, 1.55)
    end

    return true
end

function Game.debugKillEntity(state, entityOrId)
    if not state or not state.adminMode then
        return false, "ADMIN MODE REQUIRED"
    end

    local entity = entityOrId
    if type(entityOrId) == "number" then
        entity = getEntityById(state, entityOrId)
    end

    if type(entity) ~= "table" or not entity.alive then
        return false, "ENTITY NOT FOUND"
    end

    killEntity(state, entity, nil, nil)
    return true
end

function Game.debugApplySlow(state, entityOrId, factor, duration)
    if not state or not state.adminMode then
        return false, "ADMIN MODE REQUIRED"
    end

    local entity = entityOrId
    if type(entityOrId) == "number" then
        entity = getEntityById(state, entityOrId)
    end
    if type(entity) ~= "table" or not entity.alive then
        return false, "ENTITY NOT FOUND"
    end

    local _, applied = applyMovementSlow(entity, {
        factor = factor,
        duration = duration,
    })
    return applied
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
    state.entitiesDirty = false
    state.globalMovementAuraActive = false
    state.globalMovementAuraDirty = false
    state.emeraldBoost = { [1] = 0, [2] = 0 }
    state.emeraldBoostSources = { [1] = {}, [2] = {} }
    state.entityById = {}
    state.entitiesByOwner = { [1] = {}, [2] = {} }
    for _, entity in ipairs(kept) do
        state.entityById[entity.id] = entity
        local owned = state.entitiesByOwner[entity.owner]
        owned[#owned + 1] = entity
    end
    rebuildSpatialIndex(state)
    state.projectiles = {}
    state.effects = {}
    state.pendingSpells = {}
end

function Game.debugSpatialRadiusIds(state, owner, x, y, radius)
    rebuildSpatialIndex(state)
    local candidates = spatialCandidatesInRadius(state, owner, x, y, radius)
    local radiusSq = radius * radius
    local ids = {}
    for _, entity in ipairs(candidates) do
        if entity.alive
            and entity.owner == owner
            and util.distanceSquared(x, y, entity.x, entity.y) <= radiusSq
        then
            ids[#ids + 1] = entity.id
        end
    end
    return ids
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

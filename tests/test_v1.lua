-- Minimal Lua 5.4-compatible smoke tests for logic that does not require CC:Tweaked peripherals.

colors = {
    white = 1,
    orange = 2,
    magenta = 4,
    lightBlue = 8,
    yellow = 16,
    lime = 32,
    pink = 64,
    gray = 128,
    lightGray = 256,
    cyan = 512,
    purple = 1024,
    blue = 2048,
    brown = 4096,
    green = 8192,
    red = 16384,
    black = 32768,
}

package.path = "./?.lua;./?/init.lua;" .. package.path

local cards = require("src.cards")
local arena = require("src.arena")
local Game = require("src.game")
local pixelArena = require("src.pixel_arena")
local Bot = require("src.bot")
local musicManifest = require("src.music_manifest")

local function assertEq(actual, expected, message)
    if actual ~= expected then
        error((message or "assertEq failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function assertTrue(value, message)
    if not value then error(message or "assertTrue failed") end
end

assertEq(#cards.list, 18, "Card pool must contain eighteen selectable cards")
assertEq(#cards.defaultDeck(), 8, "Default deck must contain eight cards")
assertTrue(cards.isValidDeck(cards.defaultDeck()), "Default deck must be valid")

local seen = {}
for _, card in ipairs(cards.list) do
    assertTrue(not seen[card.id], "Card IDs must be unique: " .. tostring(card.id))
    seen[card.id] = true
    assertTrue(card.cost > 0, "Card must have a positive cost: " .. tostring(card.id))
    assertTrue(card.kind == "unit" or card.kind == "building" or card.kind == "spell", "Unknown card kind")
end

local deckState = Game.new()
assertEq(#deckState.players[1].deck, 8, "Player must start with an eight-card deck")
Game.toggleDeckCard(deckState, 1, "zombie")
assertEq(#deckState.players[1].deck, 7, "Removing a deck card must leave seven cards")
assertTrue(not cards.isValidDeck(deckState.players[1].deck), "Seven-card deck must be invalid")
Game.toggleDeckCard(deckState, 1, "blaze")
assertEq(#deckState.players[1].deck, 8, "Adding a new card must restore eight cards")
assertTrue(cards.isValidDeck(deckState.players[1].deck), "Edited eight-card deck must be valid")
assertEq(deckState.players[1].deck[8], "blaze", "Added card should occupy the open deck slot")

local villagerCard = cards.get("villager")
assertTrue(villagerCard and villagerCard.kind == "unit", "Villager must be a unit, not a building")
assertEq(villagerCard.cost, 7, "Villager must cost seven Emeralds")
assertTrue(villagerCard.unit.passive, "Villager must be passive")
assertEq(villagerCard.unit.lifetime, 50, "Villager must last fifty seconds")
assertEq(villagerCard.unit.emeraldBoost, 0.616, "Villager boost must target four-Emerald net value")

local endermiteCard = cards.get("endermite")
assertEq(endermiteCard.cost, 1, "Endermite must cost one Emerald")
assertTrue(endermiteCard.unit.maxHp < 150, "Endermite should have low HP")
assertTrue(endermiteCard.unit.damage < 25, "Endermite should have low DPS damage")

local batCard = cards.get("bat_swarm")
assertEq(batCard.unit.maxHp, 45, "Bat Swarm must be extremely fragile")
assertTrue(batCard.unit.maxHp < 80, "Princess Tower must one-shot each Bat")

local skeletonCard = cards.get("skeleton")
local snowGolemCard = cards.get("snow_golem")
assertTrue(
    skeletonCard.unit.preferredMinRange ~= nil,
    "Skeleton must keep its kiting distance"
)
assertTrue(
    snowGolemCard.unit.preferredMinRange == nil,
    "Snow Golem must not kite like Skeleton"
)

local ironGolemCard = cards.get("iron_golem")
local cannonCard = cards.get("cannon")
local blazeCard = cards.get("blaze")
assertEq(ironGolemCard.cost, 5, "Iron Golem must cost five Emeralds")
assertEq(cannonCard.building.maxHp, 618, "Cannon HP must reflect the five-percent nerf")
assertEq(cannonCard.building.damage, 64, "Cannon damage must reflect the two-percent nerf")
assertEq(blazeCard.unit.maxHp, 270, "Blaze HP must reflect the additional two-percent nerf")

local anvilCard = cards.get("falling_anvil")
assertTrue(anvilCard and anvilCard.kind == "spell", "Falling Anvil must be a selectable spell")
assertEq(anvilCard.cost, 3, "Falling Anvil must cost three Emeralds")
assertEq(anvilCard.spell.delay, 3.0, "Falling Anvil must have a three-second delay")
assertEq(anvilCard.spell.damage, 549, "Falling Anvil must leave a full-health Zombie at exactly one HP")
assertEq(anvilCard.spell.radius, 6.05, "Falling Anvil radius must be ten percent larger")
assertTrue(anvilCard.spell.groundOnly == false, "Falling Anvil must hit flying and grounded units")

local portalCard = cards.get("nether_portal")
assertTrue(portalCard and portalCard.kind == "building", "Nether Portal must be a selectable building")
assertEq(portalCard.cost, 3, "Nether Portal must cost three Emeralds")
assertTrue(portalCard.building.periodicSpawn ~= nil, "Nether Portal must periodically spawn Piglins")
assertEq(portalCard.building.periodicSpawn.template, "piglin", "Nether Portal must spawn the internal Piglin")

local piglinTemplate = cards.getInternalUnit("piglin")
assertTrue(piglinTemplate ~= nil, "Piglin must exist as an internal unit")
assertTrue(cards.get("piglin") == nil, "Piglin must not be directly selectable as a card")
assertEq(piglinTemplate.lifetime, 10.0, "Piglin must zombify/despawn after ten seconds")
assertTrue(piglinTemplate.hybridAttack ~= nil, "Piglin must support ranged and melee attacks")
assertTrue(
    piglinTemplate.hybridAttack.meleeDamage > piglinTemplate.hybridAttack.rangedDamage,
    "Piglin axe hit should be stronger than its crossbow shot"
)

local config = require("config")
assertEq(config.MATCH.normalTime, 150, "Regulation must last two minutes thirty")
assertEq(config.MATCH.overtimeTime, 150, "Overtime must last two minutes thirty")
assertEq(config.MATCH.overtimeMultiplier, 2, "Most of overtime must use double Emerald generation")
assertEq(config.MATCH.overtimeFinalSeconds, 30, "Final overtime boost must begin with thirty seconds left")
assertEq(config.MATCH.overtimeFinalMultiplier, 3, "Final thirty seconds must use triple Emerald generation")
assertEq(config.MATCH.tiebreakerDamagePerSecond, 300, "Tiebreaker drain rate must stay deterministic")
local riverMid = (config.ARENA.riverTop + config.ARENA.riverBottom) / 2

assertTrue(not arena.placementAllowed(1, 50, 20, nil), "P1 must not deploy troops on enemy half")
assertTrue(arena.placementAllowed(1, 50, 120, nil), "P1 must deploy troops on own half")
assertTrue(arena.placementAllowed(2, 50, 20, nil), "P2 must deploy troops on own half")
assertTrue(not arena.placementAllowed(2, 50, 120, nil), "P2 must not deploy troops on enemy half")
assertTrue(arena.placementAllowed(1, 50, 20, "anywhere"), "Spell placement must support the whole arena")

local ground = { flying = false }
local flying = { flying = true }
assertTrue(not arena.isWalkable(ground, 50, riverMid), "Ground unit must not walk through river")
assertTrue(arena.isWalkable(ground, config.ARENA.bridgeCenters[1], riverMid), "Ground unit must walk on bridge")
assertTrue(arena.isWalkable(flying, 50, riverMid), "Flying unit must cross river")

local rect = { x1 = 1, y1 = 3, x2 = 57, y2 = 44 }
for playerId = 1, 2 do
    local wx, wy = 23, 121
    local sx, sy = arena.worldToScreen(playerId, wx, wy, rect)
    local rx, ry = arena.screenToWorld(playerId, sx, sy, rect)
    assertTrue(math.abs(rx - wx) < 3, "View transform X round-trip failed for player " .. playerId)
    assertTrue(math.abs(ry - wy) < 5, "View transform Y round-trip failed for player " .. playerId)
end

local state = Game.new()
assertEq(#state.players[1].hand, 4, "Player 1 must start with four cards")
assertEq(#state.players[1].queue, 4, "Player 1 must have four queued cards")

local layout = {
    readyButton = { x1 = 10, y1 = 10, x2 = 20, y2 = 12 },
    arena = rect,
    cards = {
        { x1 = 1, y1 = 45, x2 = 14, y2 = 52 },
        { x1 = 15, y1 = 45, x2 = 28, y2 = 52 },
        { x1 = 29, y1 = 45, x2 = 42, y2 = 52 },
        { x1 = 43, y1 = 45, x2 = 57, y2 = 52 },
    },
    resultButtons = {
        rematch = { x1 = 1, y1 = 50, x2 = 18, y2 = 52 },
        deck = { x1 = 20, y1 = 50, x2 = 38, y2 = 52 },
        exit = { x1 = 40, y1 = 50, x2 = 57, y2 = 52 },
    },
}

Game.handleTouch(state, 1, 15, 11, layout)
assertTrue(state.players[1].ready, "Player 1 ready toggle failed")
Game.handleTouch(state, 2, 15, 11, layout)
assertEq(state.phase, "countdown", "Both players ready must start countdown")

for _ = 1, 13 do
    Game.update(state, 0.25)
end
assertEq(state.phase, "battle", "Countdown must transition to battle")
assertEq(#state.entities, 6, "Battle must begin with six towers")

local firstCard = state.players[1].hand[1]
Game.handleTouch(state, 1, 5, 47, layout)
assertEq(state.players[1].selectedSlot, 1, "Card touch must select slot")

Game.handleTouch(state, 1, 29, 35, layout)
assertTrue(#state.entities > 6, "Valid troop placement must spawn a unit")
assertTrue(state.players[1].hand[1] ~= firstCard, "Played card must cycle out of the hand")

local debugState = Game.new()
Game.debugLoadScenario(debugState, "full")
assertEq(debugState.phase, "admin", "Admin scenario must enter admin phase")
assertTrue(debugState.adminPaused, "Admin scenario should start paused")
assertEq(#debugState.entities, 6, "Full admin scenario must have six towers")

Game.debugLoadScenario(debugState, "princess")
assertEq(#debugState.entities, 4, "Princess-only scenario must have four side towers")

Game.debugLoadScenario(debugState, "king")
assertEq(#debugState.entities, 2, "King-only scenario must have two King Towers")

Game.debugLoadScenario(debugState, "single_tower")
assertEq(#debugState.entities, 2, "1v1 tower scenario must have one tower per player")

Game.debugLoadScenario(debugState, "empty")
assertEq(#debugState.entities, 0, "Empty admin scenario must start empty")

debugState.tiebreaker = true
Game.debugLoadScenario(debugState, "empty")
assertTrue(not debugState.tiebreaker, "Admin scenario reload must clear tiebreaker state")

local ok = Game.debugSpawnCard(debugState, 1, "zombie", 50, 120)
assertTrue(ok, "Admin must spawn cards without Emerald or side restrictions")
assertEq(#debugState.entities, 1, "Admin spawn must create the selected unit")

Game.debugSetPaused(debugState, false)
assertTrue(not debugState.adminPaused, "Admin pause control must resume simulation")

local retargetState = Game.new()
Game.debugLoadScenario(retargetState, "king")
Game.debugSpawnCard(retargetState, 1, "skeleton", 50, 92)
Game.debugSpawnCard(retargetState, 2, "zombie", 50, 68)

local skeleton, zombie, enemyKingForSkeleton, enemyKingForZombie
for _, entity in ipairs(retargetState.entities) do
    if entity.name == "Skeleton" then skeleton = entity end
    if entity.name == "Zombie" then zombie = entity end
    if entity.kind == "tower" and entity.towerType == "king" then
        if entity.owner == 2 then enemyKingForSkeleton = entity end
        if entity.owner == 1 then enemyKingForZombie = entity end
    end
end

assertTrue(skeleton and zombie, "Retarget test units must exist")
assertTrue(enemyKingForSkeleton and enemyKingForZombie, "Retarget test kings must exist")

-- Reproduce the old bug: both troops were already locked onto distant towers.
skeleton.targetId = enemyKingForSkeleton.id
zombie.targetId = enemyKingForZombie.id

Game.debugSetPaused(retargetState, false)
Game.update(retargetState, 0.1)

assertEq(skeleton.targetId, zombie.id, "Skeleton must switch from tower to nearby enemy troop")
assertEq(zombie.targetId, skeleton.id, "Zombie must switch from tower to nearby enemy troop")

local golemPullState = Game.new()
Game.debugLoadScenario(golemPullState, "full")
Game.debugSpawnCard(golemPullState, 1, "iron_golem", 50, 105)
Game.debugSpawnCard(golemPullState, 2, "cannon", 50, 68)

local pullGolem, pullCannon, distantEnemyTower
for _, entity in ipairs(golemPullState.entities) do
    if entity.name == "Iron Golem" then
        pullGolem = entity
    elseif entity.name == "Cannon" and entity.owner == 2 then
        pullCannon = entity
    elseif entity.kind == "tower" and entity.owner == 2 then
        if not distantEnemyTower
            or math.abs(entity.x - 50) < math.abs(distantEnemyTower.x - 50)
        then
            distantEnemyTower = entity
        end
    end
end

assertTrue(pullGolem and pullCannon and distantEnemyTower, "Iron Golem pull test entities must exist")

-- Reproduce the problematic case: the Golem already committed to a tower,
-- then a defensive Cannon is placed inside its sight range.
pullGolem.targetId = distantEnemyTower.id
Game.debugSetPaused(golemPullState, false)
Game.update(golemPullState, 0.10)

assertEq(
    pullGolem.targetId,
    pullCannon.id,
    "Iron Golem must retarget from a tower to a closer Cannon"
)

local creeperState = Game.new()
Game.debugLoadScenario(creeperState, "empty")
Game.debugSpawnCard(creeperState, 1, "creeper", 50, 80)
Game.debugSpawnCard(creeperState, 2, "zombie", 53, 80)

local testCreeper, testZombie
for _, entity in ipairs(creeperState.entities) do
    if entity.name == "Creeper" then testCreeper = entity end
    if entity.name == "Zombie" then testZombie = entity end
end

assertTrue(testCreeper and testZombie, "Creeper fuse test units must exist")
local zombieHpBeforeFuse = testZombie.hp

Game.debugSetPaused(creeperState, false)
Game.update(creeperState, 0.1)

assertTrue(testCreeper.alive, "Creeper must not deal an instant melee hit")
assertEq(testZombie.hp, zombieHpBeforeFuse, "Creeper must deal no melee damage")
assertTrue(testCreeper.fuseRemaining ~= nil, "Creeper must start its fuse in proximity")

for _ = 1, 7 do
    Game.update(creeperState, 0.25)
end

assertTrue(not testCreeper.alive, "Creeper must self-destruct after its fuse")
assertTrue(testZombie.hp < zombieHpBeforeFuse, "Creeper explosion must damage nearby enemies")

local killedCreeperState = Game.new()
Game.debugLoadScenario(killedCreeperState, "empty")
Game.debugSpawnCard(killedCreeperState, 1, "creeper", 50, 80)
Game.debugSpawnCard(killedCreeperState, 2, "zombie", 53, 80)

local nearbyZombie
for _, entity in ipairs(killedCreeperState.entities) do
    if entity.name == "Zombie" then nearbyZombie = entity end
end
local nearbyZombieHp = nearbyZombie.hp

Game.debugSpawnCard(killedCreeperState, 2, "arrows", 50, 80)
Game.debugSpawnCard(killedCreeperState, 2, "arrows", 50, 80)
Game.debugSpawnCard(killedCreeperState, 2, "arrows", 50, 80)

assertEq(nearbyZombie.hp, nearbyZombieHp, "Killed Creeper must not explode on death")

assertTrue(type(pixelArena.draw) == "function", "Semigraphics pixel arena renderer must load")

local visualState = Game.new()
Game.debugLoadScenario(visualState, "empty")
Game.debugSpawnCard(visualState, 1, "skeleton", 50, 90)
Game.debugSpawnCard(visualState, 2, "zombie", 50, 80)
Game.debugSetPaused(visualState, false)
Game.update(visualState, 0.1)

assertTrue(#visualState.projectiles >= 1, "Skeleton must create a visible projectile")
assertEq(visualState.projectiles[1].visual, "arrow", "Skeleton projectile must use arrow visual")

local flashState = Game.new()
Game.debugLoadScenario(flashState, "empty")
Game.debugSpawnCard(flashState, 2, "zombie", 50, 80)
Game.debugSpawnCard(flashState, 1, "arrows", 50, 80)

local flashedZombie
for _, entity in ipairs(flashState.entities) do
    if entity.name == "Zombie" then flashedZombie = entity end
end
assertTrue(flashedZombie and flashedZombie.damageFlash and flashedZombie.damageFlash > 0, "Damage must set hit-flash state")

local villagerState = Game.new()
Game.debugLoadScenario(villagerState, "empty")
Game.debugSpawnCard(villagerState, 1, "villager", 50, 120)
villagerState.phase = "battle"
villagerState.adminMode = false
villagerState.players[1].emeralds = 0
villagerState.players[2].emeralds = 0
Game.update(villagerState, 0.25)

local baseGain = config.MATCH.emeraldPerSecond * 0.25
assertTrue(
    villagerState.players[1].emeralds > baseGain,
    "Living Villager must increase its owner's Emerald generation"
)
assertTrue(
    math.abs(villagerState.players[1].emeralds - baseGain * 1.616) < 0.001,
    "Villager boost must be exactly 61.6 percent"
)

local slowState = Game.new()
Game.debugLoadScenario(slowState, "empty")
Game.debugSpawnCard(slowState, 1, "snow_golem", 50, 90)
Game.debugSpawnCard(slowState, 2, "zombie", 50, 80)
Game.debugSetPaused(slowState, false)
for _ = 1, 4 do Game.update(slowState, 0.15) end

local slowedZombie
for _, entity in ipairs(slowState.entities) do
    if entity.name == "Zombie" then slowedZombie = entity end
end
assertTrue(slowedZombie and slowedZombie.slowRemaining > 0, "Snow Golem snowball must slow targets")

local kiteSlowState = Game.new()
Game.debugLoadScenario(kiteSlowState, "empty")
Game.debugSpawnCard(kiteSlowState, 1, "skeleton", 50, 95)
Game.debugSpawnCard(kiteSlowState, 2, "zombie", 50, 93)

local slowedSkeleton
for _, entity in ipairs(kiteSlowState.entities) do
    if entity.name == "Skeleton" then slowedSkeleton = entity end
end
assertTrue(slowedSkeleton ~= nil, "Slow-aware kite test needs a Skeleton")
slowedSkeleton.slowRemaining = 1.0
slowedSkeleton.slowFactor = 0.5
local kiteStartY = slowedSkeleton.y

Game.debugSetPaused(kiteSlowState, false)
Game.update(kiteSlowState, 0.20)

local kiteDistance = math.abs(slowedSkeleton.y - kiteStartY)
assertTrue(
    math.abs(kiteDistance - 0.75) < 0.05,
    "Skeleton retreat speed must respect active movement slow"
)

local teleportState = Game.new()
Game.debugLoadScenario(teleportState, "empty")
Game.debugSpawnCard(teleportState, 1, "enderman", 50, 110)
Game.debugSpawnCard(teleportState, 2, "zombie", 50, 90)

local testEnderman, teleportZombie
for _, entity in ipairs(teleportState.entities) do
    if entity.name == "Enderman" then testEnderman = entity end
    if entity.name == "Zombie" then teleportZombie = entity end
end
local distanceBeforeTeleport = math.abs(testEnderman.y - teleportZombie.y)
Game.debugSetPaused(teleportState, false)
Game.update(teleportState, 0.1)
local distanceAfterTeleport = math.abs(testEnderman.y - teleportZombie.y)
assertTrue(distanceAfterTeleport < distanceBeforeTeleport, "Enderman must teleport closer to a valid target")

local summonState = Game.new()
Game.debugLoadScenario(summonState, "empty")
Game.debugSpawnCard(summonState, 1, "witch", 50, 95)
Game.debugSetPaused(summonState, false)

for _ = 1, 18 do Game.update(summonState, 0.25) end

local babyZombieCount = 0
for _, entity in ipairs(summonState.entities) do
    if entity.name == "Baby Zombie" then babyZombieCount = babyZombieCount + 1 end
end
assertTrue(babyZombieCount >= 1, "Witch must periodically summon a Baby Zombie")

local anvilState = Game.new()
Game.debugLoadScenario(anvilState, "empty")
Game.debugSpawnCard(anvilState, 2, "zombie", 50, 80)
local anvilZombie
for _, entity in ipairs(anvilState.entities) do
    if entity.name == "Zombie" then anvilZombie = entity end
end
assertTrue(anvilZombie ~= nil, "Anvil test Zombie must exist")
assertTrue(Game.debugSpawnCard(anvilState, 1, "falling_anvil", 50, 80), "Admin must cast Falling Anvil")
assertEq(anvilZombie.hp, 550, "Falling Anvil must not deal instant damage")
assertEq(#anvilState.pendingSpells, 1, "Falling Anvil must wait as a pending spell")

Game.debugSetPaused(anvilState, false)
for _ = 1, 11 do Game.update(anvilState, 0.25) end
assertEq(anvilZombie.hp, 550, "Falling Anvil must still be harmless before three seconds")
Game.update(anvilState, 0.25)
assertEq(anvilZombie.hp, 1, "Falling Anvil direct hit must leave Zombie at exactly one HP")
assertEq(#anvilState.pendingSpells, 0, "Falling Anvil must resolve after its delay")

local anvilMultiState = Game.new()
Game.debugLoadScenario(anvilMultiState, "empty")
Game.debugSpawnCard(anvilMultiState, 2, "zombie", 47, 80)
Game.debugSpawnCard(anvilMultiState, 2, "zombie", 53, 80)
Game.debugSpawnCard(anvilMultiState, 2, "bat_swarm", 50, 82)

local anvilVictims = {}
for _, entity in ipairs(anvilMultiState.entities) do
    if entity.owner == 2 and (entity.name == "Zombie" or entity.name == "Bat Swarm") then
        entity.moveSpeed = 0
        entity.targetMode = "none"
        entity.passive = true
        anvilVictims[#anvilVictims + 1] = entity
    end
end

assertTrue(#anvilVictims >= 5, "Anvil multi-hit test must include multiple ground and flying units")
assertTrue(
    Game.debugSpawnCard(anvilMultiState, 1, "falling_anvil", 50, 80),
    "Anvil must cast over mixed ground and flying units"
)

Game.debugSetPaused(anvilMultiState, false)
for _ = 1, 12 do Game.update(anvilMultiState, 0.25) end

local groundHits, airHits = 0, 0
for _, entity in ipairs(anvilVictims) do
    assertTrue(
        not entity.alive or entity.hp < entity.maxHp,
        "One Falling Anvil must damage every enemy inside its radius"
    )
    if entity.flying then
        airHits = airHits + 1
    else
        groundHits = groundHits + 1
    end
end
assertTrue(groundHits >= 2, "Falling Anvil must hit multiple grounded units at once")
assertTrue(airHits >= 1, "Falling Anvil must hit flying units too")

local portalState = Game.new()
Game.debugLoadScenario(portalState, "empty")
assertTrue(Game.debugSpawnCard(portalState, 1, "nether_portal", 25, 100), "Admin must spawn Nether Portal")
Game.debugSetPaused(portalState, false)
for _ = 1, 9 do Game.update(portalState, 0.25) end

local spawnedPiglin
for _, entity in ipairs(portalState.entities) do
    if entity.name == "Piglin" then spawnedPiglin = entity end
end
assertTrue(spawnedPiglin ~= nil, "Nether Portal must spawn a Piglin")
assertTrue(spawnedPiglin.remainingLifetime <= 10 and spawnedPiglin.remainingLifetime > 0, "Spawned Piglin must have a ten-second lifetime")
assertTrue(spawnedPiglin.hybridAttack ~= nil, "Spawned Piglin must retain hybrid axe/crossbow combat")

local costApiState = Game.new()
costApiState.players[1].ready = true
costApiState.players[2].ready = true
Game.startCountdown(costApiState)
for _ = 1, 13 do Game.update(costApiState, 0.25) end
assertEq(costApiState.phase, "battle", "Cost API test must enter battle")

costApiState.players[1].hand[1] = "falling_anvil"
costApiState.players[1].emeralds = 3
assertTrue(
    Game.playCardFromSlot(costApiState, 1, 1, 50, 60),
    "Falling Anvil must be playable through the normal API with exactly three Emeralds"
)
assertEq(costApiState.players[1].emeralds, 0, "Falling Anvil must deduct exactly three Emeralds")
assertEq(#costApiState.pendingSpells, 1, "Normal Anvil play must create a delayed pending spell")

costApiState.players[1].hand[1] = "nether_portal"
costApiState.players[1].emeralds = 3
assertTrue(
    Game.playCardFromSlot(costApiState, 1, 1, 25, 100),
    "Nether Portal must be playable through the normal API with exactly three Emeralds"
)
assertEq(costApiState.players[1].emeralds, 0, "Nether Portal must deduct exactly three Emeralds")

local normalPortalFound = false
for _, entity in ipairs(costApiState.entities) do
    if entity.name == "Nether Portal" and entity.owner == 1 then
        normalPortalFound = true
        break
    end
end
assertTrue(normalPortalFound, "Normal Nether Portal play must create the building")

local firstPiglinId = spawnedPiglin.id
local maxAlivePiglins = 0
for _ = 1, 120 do
    Game.update(portalState, 0.25)
    local alivePiglins = 0
    for _, entity in ipairs(portalState.entities) do
        if entity.name == "Piglin" and entity.alive then alivePiglins = alivePiglins + 1 end
    end
    maxAlivePiglins = math.max(maxAlivePiglins, alivePiglins)
end
assertTrue(maxAlivePiglins <= 2, "Nether Portal must respect its max-two living Piglin limit")
local firstPiglinStillAlive = false
for _, entity in ipairs(portalState.entities) do
    if entity.id == firstPiglinId and entity.alive then firstPiglinStillAlive = true end
end
assertTrue(not firstPiglinStillAlive, "Piglin must disappear after its ten-second lifetime")

local rangedPiglinState = Game.new()
Game.debugLoadScenario(rangedPiglinState, "empty")
Game.debugSpawnCard(rangedPiglinState, 1, "nether_portal", 25, 100)
Game.debugSetPaused(rangedPiglinState, false)

-- Let the portal create one Piglin first, then place targets relative to its
-- actual spawn position so the weapon-mode tests are deterministic.
for _ = 1, 10 do Game.update(rangedPiglinState, 0.25) end

local rangedPiglin
for _, entity in ipairs(rangedPiglinState.entities) do
    if entity.name == "Piglin" and entity.alive then
        rangedPiglin = entity
        break
    end
end
assertTrue(rangedPiglin ~= nil, "Ranged weapon test must have a living Piglin")

Game.debugSpawnCard(
    rangedPiglinState,
    2,
    "bat_swarm",
    math.min(config.ARENA.width - 4, rangedPiglin.x + 8),
    rangedPiglin.y
)

local rangedBatHpBefore = {}
for _, entity in ipairs(rangedPiglinState.entities) do
    if entity.name == "Bat Swarm" then
        rangedBatHpBefore[entity.id] = entity.hp
    end
end
assertTrue(next(rangedBatHpBefore) ~= nil, "Ranged Piglin flying target must exist")

for _ = 1, 8 do Game.update(rangedPiglinState, 0.10) end

local damagedFlyingTarget = false
for _, entity in ipairs(rangedPiglinState.entities) do
    local before = rangedBatHpBefore[entity.id]
    if before and entity.hp < before then
        damagedFlyingTarget = true
        break
    end
end
assertTrue(
    damagedFlyingTarget,
    "Piglin must use its crossbow against flying targets"
)

local groundNoCrossbowState = Game.new()
Game.debugLoadScenario(groundNoCrossbowState, "empty")
Game.debugSpawnCard(groundNoCrossbowState, 1, "nether_portal", 25, 100)
Game.debugSetPaused(groundNoCrossbowState, false)
for _ = 1, 10 do Game.update(groundNoCrossbowState, 0.25) end

local groundPiglin
for _, entity in ipairs(groundNoCrossbowState.entities) do
    if entity.name == "Piglin" and entity.alive then
        groundPiglin = entity
        break
    end
end
assertTrue(groundPiglin ~= nil, "Ground weapon test must have a living Piglin")

Game.debugSpawnCard(
    groundNoCrossbowState,
    2,
    "villager",
    math.min(config.ARENA.width - 4, groundPiglin.x + 8),
    groundPiglin.y
)

local distantGroundTarget
for _, entity in ipairs(groundNoCrossbowState.entities) do
    if entity.name == "Villager" then distantGroundTarget = entity end
end
assertTrue(distantGroundTarget ~= nil, "Distant ground target must exist")
local distantGroundHpBefore = distantGroundTarget.hp

-- At eight blocks away the Piglin must walk toward a grounded target instead
-- of firing the crossbow.
for _ = 1, 4 do Game.update(groundNoCrossbowState, 0.10) end
assertEq(
    distantGroundTarget.hp,
    distantGroundHpBefore,
    "Piglin must not fire its crossbow at grounded targets"
)

local meleePiglinState = Game.new()
Game.debugLoadScenario(meleePiglinState, "empty")
Game.debugSpawnCard(meleePiglinState, 1, "nether_portal", 25, 100)
Game.debugSetPaused(meleePiglinState, false)
for _ = 1, 10 do Game.update(meleePiglinState, 0.25) end

local meleePiglin
for _, entity in ipairs(meleePiglinState.entities) do
    if entity.name == "Piglin" and entity.alive then
        meleePiglin = entity
        break
    end
end
assertTrue(meleePiglin ~= nil, "Melee weapon test must have a living Piglin")

Game.debugSpawnCard(
    meleePiglinState,
    2,
    "villager",
    math.min(config.ARENA.width - 4, meleePiglin.x + 2),
    meleePiglin.y
)

local meleeTarget
for _, entity in ipairs(meleePiglinState.entities) do
    if entity.name == "Villager" then meleeTarget = entity end
end
assertTrue(meleeTarget ~= nil, "Melee Piglin test target must exist")
local meleeHpBefore = meleeTarget.hp

Game.update(meleePiglinState, 0.10)
assertEq(
    meleeTarget.hp,
    meleeHpBefore - 58,
    "Piglin must use its 58-damage axe against grounded targets in melee range"
)

local botState = Game.new()
Game.debugLoadScenario(botState, "full")
local bot = Bot.new(2)
Bot.setEnabled(bot, botState, true)
assertTrue(bot.enabled, "Admin bot must enable")
assertEq(botState.players[2].emeralds, config.MATCH.emeraldStart, "Bot must start with normal Emeralds")
assertEq(#botState.players[2].hand, 4, "Bot must use a four-card hand")
assertEq(#botState.players[2].queue, 4, "Bot must use an eight-card deck cycle")

-- Force a dangerous ground push into P2's half so the normal bot has a
-- deterministic defensive decision to make.
Game.debugSpawnCard(botState, 1, "iron_golem", 50, 58)
botState.players[2].emeralds = 10
Game.debugSetPaused(botState, false)

local actionsBefore = bot.actions
for _ = 1, 15 do
    Bot.update(bot, botState, 0.2)
    Game.update(botState, 0.2)
end

assertTrue(bot.actions > actionsBefore, "Normal bot must react to a dangerous push")
assertTrue(botState.players[2].emeralds < 10, "Bot must pay Emerald costs for cards")
assertTrue(bot.lastAction ~= "NONE", "Bot should expose its last action for admin UI")

local antiAirBotState = Game.new()
Game.debugLoadScenario(antiAirBotState, "full")
local antiAirBot = Bot.new(2)
Bot.setEnabled(antiAirBot, antiAirBotState, true)
antiAirBotState.players[2].hand = { "cannon", "iron_golem", "spider", "wolf" }
antiAirBotState.players[2].queue = { "zombie", "slime", "creeper", "endermite" }
antiAirBotState.players[2].emeralds = 10
Game.debugSpawnCard(antiAirBotState, 1, "bat_swarm", 50, 58)
Game.debugSetPaused(antiAirBotState, false)
antiAirBot.thinkTimer = 0

local antiAirActionsBefore = antiAirBot.actions
Bot.update(antiAirBot, antiAirBotState, 1.0)
assertEq(
    antiAirBot.actions,
    antiAirActionsBefore,
    "Bot must not waste Cannon or ground-only cards against a flying threat"
)

local botStatus = Bot.status(bot, botState)
assertTrue(botStatus.enabled and botStatus.playerId == 2, "Bot status must report P2 enabled")

local sharedModeState = Game.new()
local sharedModeLayout = {
    modeButton = { x1 = 1, y1 = 1, x2 = 10, y2 = 3 },
    botDifficultyButton = { x1 = 1, y1 = 5, x2 = 10, y2 = 7 },
    readyButton = { x1 = 20, y1 = 20, x2 = 30, y2 = 22 },
    collectionCards = {},
}

-- If P2 requests VS BOT, P2 must remain human and P1 becomes the AI.
Game.handleTouch(sharedModeState, 2, 5, 2, sharedModeLayout)
assertEq(sharedModeState.gameMode, "bot", "P2 monitor must be able to switch to VS BOT")
assertEq(sharedModeState.botPlayerId, 1, "P2 selecting VS BOT must make P1 the bot")

Game.handleTouch(sharedModeState, 2, 5, 2, sharedModeLayout)
assertEq(sharedModeState.gameMode, "pvp", "P2 monitor must be able to switch back to PVP")

-- If P1 requests VS BOT, preserve the traditional P2 AI behavior.
Game.handleTouch(sharedModeState, 1, 5, 2, sharedModeLayout)
assertEq(sharedModeState.gameMode, "bot", "P1 monitor must be able to switch to VS BOT")
assertEq(sharedModeState.botPlayerId, 2, "P1 selecting VS BOT must make P2 the bot")

Game.handleTouch(sharedModeState, 1, 5, 2, sharedModeLayout)
assertEq(sharedModeState.gameMode, "pvp", "P1 monitor must be able to switch back to PVP")

-- P2-human path must also auto-ready the dynamically selected P1 bot.
Game.handleTouch(sharedModeState, 2, 5, 2, sharedModeLayout)
assertEq(sharedModeState.botPlayerId, 1, "P2-human bot match must keep P1 as AI")
Game.handleTouch(sharedModeState, 2, 25, 21, sharedModeLayout)
assertEq(sharedModeState.phase, "countdown", "P2 human READY must auto-ready P1 bot and start")

local modeState = Game.new()
assertTrue(Game.setGameMode(modeState, "bot"), "Game must support VS BOT mode")
assertEq(modeState.gameMode, "bot", "VS BOT mode must be stored on state")

local liveBot = Bot.new(2)
Bot.prepare(liveBot, modeState)
assertTrue(cards.isValidDeck(modeState.players[2].deck), "Live bot must prepare a valid eight-card deck")

modeState.players[1].ready = true
modeState.players[2].ready = true
Game.startCountdown(modeState)
for _ = 1, 13 do Game.update(modeState, 0.25) end
assertEq(modeState.phase, "battle", "VS BOT countdown must start a normal battle")

local p1 = modeState.players[1]
p1.emeralds = 10
local played = Game.playCardFromSlot(modeState, 1, 1, 25, 112)
assertTrue(played, "Shared play API must deploy a normal player card")
assertEq(modeState.stats.players[1].cardsPlayed, 1, "Match telemetry must count card plays")
assertTrue(modeState.stats.players[1].emeraldSpent > 0, "Match telemetry must count Emerald spending")

-- Telemetry must attribute spell damage to the card that caused it.
modeState.players[2].emeralds = 10
Game.playCardFromSlot(modeState, 2, 1, 50, 55)
modeState.players[1].hand[1] = "arrows"
modeState.players[1].emeralds = 10
Game.playCardFromSlot(modeState, 1, 1, 50, 55)
assertTrue(modeState.stats.players[1].unitDamage > 0, "Telemetry must record unit damage")
assertTrue(
    modeState.stats.players[1].cards.arrows
        and modeState.stats.players[1].cards.arrows.unitDamage > 0,
    "Arrow Volley damage must be attributed to Arrow Volley"
)

Bot.beginMatch(liveBot)
liveBot.enabled = true
modeState.players[2].emeralds = 10
local botActionsBefore = liveBot.actions
for _ = 1, 12 do
    Game.update(modeState, 0.25)
    Bot.update(liveBot, modeState, 0.25)
end
assertTrue(liveBot.actions > botActionsBefore, "Live VS BOT must play through the normal card API")

for _, card in ipairs(cards.list) do
    local info = cards.getInfo(card.id)
    assertTrue(info ~= nil, "Every selectable card must have Unit Info metadata")
    assertTrue(type(info.description) == "string" and #info.description > 10, "Unit Info needs a useful description")
    assertTrue(type(info.role) == "string" and #info.role > 0, "Unit Info needs a role")
end

local infoState = Game.new()
local infoLayout = {
    infoButton = { x1 = 1, y1 = 1, x2 = 5, y2 = 3 },
    modeButton = { x1 = 20, y1 = 1, x2 = 25, y2 = 3 },
    readyButton = { x1 = 1, y1 = 20, x2 = 10, y2 = 22 },
    collectionCards = {},
    collectionPageButtons = {
        prev = { x1 = 30, y1 = 12, x2 = 34, y2 = 12 },
        next = { x1 = 35, y1 = 12, x2 = 39, y2 = 12 },
    },
}
for i = 1, 16 do
    infoLayout.collectionCards[i] = { x1 = i, y1 = 10, x2 = i, y2 = 10 }
end

Game.handleTouch(infoState, 1, 2, 2, infoLayout)
assertTrue(infoState.players[1].infoOpen, "UNIT INFO button must open the card database")

Game.handleTouch(infoState, 1, 2, 10, infoLayout)
assertEq(infoState.players[1].infoCardId, cards.list[2].id, "Tapping a card in Unit Info must inspect that card")

Game.handleTouch(infoState, 1, 36, 12, infoLayout)
assertEq(infoState.players[1].collectionPage, 2, "Card browser NEXT must open page two")
Game.handleTouch(infoState, 1, 1, 10, infoLayout)
assertEq(infoState.players[1].infoCardId, "falling_anvil", "Page-two first slot must expose Falling Anvil")
Game.handleTouch(infoState, 1, 2, 10, infoLayout)
assertEq(infoState.players[1].infoCardId, "nether_portal", "Page-two second slot must expose Nether Portal")

Game.handleTouch(infoState, 1, 2, 21, infoLayout)
assertTrue(not infoState.players[1].infoOpen, "BACK TO DECK must close Unit Info")

local featureState = Game.new()
assertEq(featureState.botDifficulty, "normal", "Bot difficulty should default to normal")
assertTrue(Game.setGameMode(featureState, "bot"), "Feature test must enter bot mode")
assertTrue(Game.cycleBotDifficulty(featureState), "Bot difficulty button must cycle")
assertEq(featureState.botDifficulty, "hard", "Difficulty should cycle normal -> hard")

local featureBot = Bot.new(2)
assertTrue(Bot.setDifficulty(featureBot, "easy"), "Bot must accept EASY difficulty")
assertEq(featureBot.mode, "easy", "Bot mode must store EASY difficulty")
assertTrue(Bot.setDifficulty(featureBot, "hard"), "Bot must accept HARD difficulty")
assertEq(featureBot.mode, "hard", "Bot mode must store HARD difficulty")

-- Deck presets work in memory even in the plain Lua smoke-test environment
-- where ComputerCraft's fs/textutils persistence APIs are unavailable.
local presetState = Game.new()
local originalPresetDeck = {}
for i, id in ipairs(presetState.players[1].deck) do originalPresetDeck[i] = id end
assertEq(presetState.players[1].presetSlot, 1, "Preset selector should start at slot 1")
assertTrue(Game.cycleDeckPresetSlot(presetState, 1, 1), "Preset selector must move right")
assertEq(presetState.players[1].presetSlot, 2, "Preset selector should move to slot 2")
assertTrue(Game.cycleDeckPresetSlot(presetState, 1, 1), "Preset selector must move right again")
assertEq(presetState.players[1].presetSlot, 3, "Preset selector should move to slot 3")
assertTrue(Game.cycleDeckPresetSlot(presetState, 1, 1), "Preset selector must wrap right")
assertEq(presetState.players[1].presetSlot, 1, "Preset selector should wrap 3 -> 1")
assertTrue(Game.cycleDeckPresetSlot(presetState, 1, -1), "Preset selector must wrap left")
assertEq(presetState.players[1].presetSlot, 3, "Preset selector should wrap 1 -> 3")
presetState.players[1].presetSlot = 1

assertTrue(Game.saveDeckPreset(presetState, 1, presetState.players[1].presetSlot), "Selected preset must save")
Game.toggleDeckCard(presetState, 1, originalPresetDeck[1])
Game.toggleDeckCard(presetState, 1, "blaze")
assertTrue(Game.loadDeckPreset(presetState, 1, presetState.players[1].presetSlot), "Selected preset must load")
for i = 1, 8 do
    assertEq(presetState.players[1].deck[i], originalPresetDeck[i], "Loaded preset must restore deck order")
end

assertTrue(Game.randomizeDeck(presetState, 1), "Random deck button must work")
assertTrue(cards.isValidDeck(presetState.players[1].deck), "Random deck must contain eight unique valid cards")

-- Battle starts with the reduced tower HP values and a real next-card queue.
local featureBattle = Game.new()
featureBattle.players[1].ready = true
featureBattle.players[2].ready = true
Game.startCountdown(featureBattle)
for _ = 1, 13 do Game.update(featureBattle, 0.25) end
assertEq(featureBattle.phase, "battle", "Feature battle must start")
assertTrue(featureBattle.players[1].queue[1] ~= nil, "Battle must expose a next card in the cycle")

local sawPrincess, sawKing = false, false
for _, entity in ipairs(featureBattle.entities) do
    if entity.kind == "tower" and entity.towerType == "princess" then
        assertEq(entity.maxHp, 1501, "Princess Tower must use the latest five-percent HP nerf")
        assertEq(entity.damage, 80, "Princess Tower must use the latest two-percent damage nerf")
        sawPrincess = true
    elseif entity.kind == "tower" and entity.towerType == "king" then
        assertEq(entity.maxHp, 2565, "King Tower must use five-percent HP nerf")
        sawKing = true
    end
end
assertTrue(sawPrincess and sawKing, "Feature battle must contain both tower types")

local overtimeEconomyState = Game.new()
overtimeEconomyState.players[1].ready = true
overtimeEconomyState.players[2].ready = true
Game.startCountdown(overtimeEconomyState)
for _ = 1, 13 do Game.update(overtimeEconomyState, 0.25) end
assertEq(overtimeEconomyState.phase, "battle", "Overtime economy test must enter battle")

overtimeEconomyState.overtime = true
overtimeEconomyState.players[1].emeralds = 0
overtimeEconomyState.players[2].emeralds = 0
overtimeEconomyState.timeLeft = 60
Game.update(overtimeEconomyState, 0.25)
local expectedDoubleGain = config.MATCH.emeraldPerSecond * 2 * 0.25
assertTrue(
    math.abs(overtimeEconomyState.players[1].emeralds - expectedDoubleGain) < 0.000001,
    "Overtime before the final thirty seconds must generate Emeralds at 2x"
)

overtimeEconomyState.players[1].emeralds = 0
overtimeEconomyState.players[2].emeralds = 0
overtimeEconomyState.timeLeft = 30
Game.update(overtimeEconomyState, 0.25)
local expectedTripleGain = config.MATCH.emeraldPerSecond * 3 * 0.25
assertTrue(
    math.abs(overtimeEconomyState.players[1].emeralds - expectedTripleGain) < 0.000001,
    "Final thirty seconds of overtime must generate Emeralds at 3x"
)

overtimeEconomyState.players[1].feedback = nil
overtimeEconomyState.players[2].feedback = nil
overtimeEconomyState.players[1].emeralds = 0
overtimeEconomyState.players[2].emeralds = 0
overtimeEconomyState.timeLeft = 30.10
Game.update(overtimeEconomyState, 0.20)
assertEq(
    overtimeEconomyState.players[1].feedback,
    "FINAL 30 - 3X EMERALDS",
    "Crossing thirty seconds in overtime must announce the 3x boost"
)
local expectedBoundaryGain = config.MATCH.emeraldPerSecond * (0.10 * 2 + 0.10 * 3)
assertTrue(
    math.abs(overtimeEconomyState.players[1].emeralds - expectedBoundaryGain) < 0.000001,
    "A tick crossing 0:30 must split Emerald generation exactly between 2x and 3x"
)

local tiebreakState = Game.new()
tiebreakState.players[1].ready = true
tiebreakState.players[2].ready = true
Game.startCountdown(tiebreakState)
for _ = 1, 13 do Game.update(tiebreakState, 0.25) end
assertEq(tiebreakState.phase, "battle", "Tiebreaker test must enter battle")

local p1LowTower, p2LowTower
for _, entity in ipairs(tiebreakState.entities) do
    if entity.kind == "tower" and entity.towerType == "princess" then
        if entity.owner == 1 and not p1LowTower then p1LowTower = entity end
        if entity.owner == 2 and not p2LowTower then p2LowTower = entity end
    end
end
assertTrue(p1LowTower and p2LowTower, "Tiebreaker test needs one side tower per player")

p1LowTower.hp = 100
p2LowTower.hp = 200
tiebreakState.overtime = true
tiebreakState.timeLeft = 0.10
Game.update(tiebreakState, 0.10)

assertTrue(tiebreakState.tiebreaker, "Expired overtime must start the tiebreaker")
assertEq(tiebreakState.phase, "battle", "Tiebreaker must remain visible as a battle phase")

tiebreakState.players[1].emeralds = 10
local tiePlayOk = Game.playCardFromSlot(tiebreakState, 1, 1, 25, 120)
assertTrue(not tiePlayOk, "Cards must be locked during the tiebreaker")

tiebreakState.players[1].selectedSlot = nil
Game.handleTouch(tiebreakState, 1, 5, 47, layout)
assertEq(
    tiebreakState.players[1].selectedSlot,
    nil,
    "Hidden hand touches must be ignored during tiebreaker"
)

for _ = 1, 8 do
    if tiebreakState.phase == "result" then break end
    Game.update(tiebreakState, 0.25)
end
assertEq(tiebreakState.phase, "result", "Tiebreaker must resolve the match")
assertEq(tiebreakState.winner, 2, "Player with the healthier lowest tower must win the tiebreaker")
assertEq(tiebreakState.resultReason, "TIEBREAKER", "Tiebreaker win must use a clear result reason")

local exactTieState = Game.new()
exactTieState.players[1].ready = true
exactTieState.players[2].ready = true
Game.startCountdown(exactTieState)
for _ = 1, 13 do Game.update(exactTieState, 0.25) end

local tieP1Tower, tieP2Tower
for _, entity in ipairs(exactTieState.entities) do
    if entity.kind == "tower" and entity.towerType == "princess" then
        if entity.owner == 1 and not tieP1Tower then tieP1Tower = entity end
        if entity.owner == 2 and not tieP2Tower then tieP2Tower = entity end
    end
end
tieP1Tower.hp = 100
tieP2Tower.hp = 100
exactTieState.overtime = true
exactTieState.timeLeft = 0.10
Game.update(exactTieState, 0.10)

for _ = 1, 8 do
    if exactTieState.phase == "result" then break end
    Game.update(exactTieState, 0.25)
end
assertEq(exactTieState.winner, nil, "Exactly equal lowest tower HP must remain a true draw")
assertEq(exactTieState.resultReason, "TIEBREAKER DRAW", "Exact tiebreak must be labelled as a draw")

local effectsBefore = #featureBattle.effects
featureBattle.players[1].emeralds = 10
assertTrue(Game.playCardFromSlot(featureBattle, 1, 1, 25, 112), "Playing a troop must succeed")
assertTrue(#featureBattle.effects > effectsBefore, "Deploying a troop must create combat feedback")

assertEq(#musicManifest.tracks, 34, "Battle music playlist must expose 34 shuffled tracks")
assertEq(musicManifest.sourceRate, 48000, "Battle music pack must use native 48 kHz DFPWM")
assertEq(musicManifest.outputRate, 48000, "Speaker output must stay at native 48 kHz")
assertEq(musicManifest.repeatFactor, 1, "Native 48 kHz music must not duplicate samples")
assertEq(musicManifest.chunkBytes, 16384, "Music chunks should fill the speaker buffer efficiently")

assertEq(#musicManifest.packs, 2, "HQ battle music must be split into two GitHub-safe packs")
assertTrue(musicManifest.packs[1].size < 25000000, "Music pack 1 must stay below GitHub's 25 MB web limit")
assertTrue(musicManifest.packs[2].size < 25000000, "Music pack 2 must stay below GitHub's 25 MB web limit")

local packOffsets = { [1] = 0, [2] = 0 }
local totalMusicBytes = 0
for i, track in ipairs(musicManifest.tracks) do
    assertEq(track.id, i, "Music track IDs must be sequential")
    assertTrue(track.pack == 1 or track.pack == 2, "Music track must reference a valid pack")
    assertEq(track.offset, packOffsets[track.pack], "Music track offsets must be contiguous inside each pack")
    assertTrue(track.bytes > 0, "Music track must contain audio bytes")
    packOffsets[track.pack] = packOffsets[track.pack] + track.bytes
    totalMusicBytes = totalMusicBytes + track.bytes
end

assertEq(packOffsets[1], musicManifest.packs[1].size, "Music pack 1 manifest size mismatch")
assertEq(packOffsets[2], musicManifest.packs[2].size, "Music pack 2 manifest size mismatch")
assertEq(totalMusicBytes, musicManifest.totalSize, "Music manifest must cover the whole HQ playlist")

-- CLI help/validation must not erase a previous simulation report.
local oldFs = fs
local simulateOpenCalls = 0
fs = {
    open = function()
        simulateOpenCalls = simulateOpenCalls + 1
        return nil
    end,
}

local simulateChunk = assert(loadfile("simulate.lua"))
simulateChunk("help")
simulateChunk("99")
assertEq(
    simulateOpenCalls,
    0,
    "simulate help/invalid input must not open or truncate balance_results.txt"
)
fs = oldFs

print("Smoke tests passed")

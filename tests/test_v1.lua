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
local sprites = require("src.sprites")

local function assertEq(actual, expected, message)
    if actual ~= expected then
        error((message or "assertEq failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function assertTrue(value, message)
    if not value then error(message or "assertTrue failed") end
end

assertEq(#cards.list, 8, "V1 must contain exactly eight test cards")
assertEq(#cards.defaultDeck(), 8, "Default deck must contain eight cards")

local seen = {}
for _, card in ipairs(cards.list) do
    assertTrue(not seen[card.id], "Card IDs must be unique: " .. tostring(card.id))
    seen[card.id] = true
    assertTrue(card.cost > 0, "Card must have a positive cost: " .. tostring(card.id))
    assertTrue(card.kind == "unit" or card.kind == "building" or card.kind == "spell", "Unknown card kind")
end

local config = require("config")
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

for _, card in ipairs(cards.list) do
    local sprite = sprites.forCard(card)
    assertTrue(sprite.width >= 3, "Every V2 card must have a readable sprite: " .. card.id)
    assertTrue(sprite.height >= 1, "Every V2 card sprite must have at least one row: " .. card.id)
end

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

print("Smoke tests passed")

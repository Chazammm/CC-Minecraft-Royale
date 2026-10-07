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

local function assertEq(actual, expected, message)
    if actual ~= expected then
        error((message or "assertEq failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function assertTrue(value, message)
    if not value then error(message or "assertTrue failed") end
end

assertEq(#cards.list, 16, "V2 card pool must contain exactly sixteen cards")
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

local botStatus = Bot.status(bot, botState)
assertTrue(botStatus.enabled and botStatus.playerId == 2, "Bot status must report P2 enabled")

local sharedModeState = Game.new()
local sharedModeLayout = {
    modeButton = { x1 = 1, y1 = 1, x2 = 10, y2 = 3 },
    readyButton = { x1 = 20, y1 = 20, x2 = 30, y2 = 22 },
    collectionCards = {},
}
Game.handleTouch(sharedModeState, 2, 5, 2, sharedModeLayout)
assertEq(sharedModeState.gameMode, "bot", "P2 monitor must be able to switch to VS BOT")
Game.handleTouch(sharedModeState, 2, 5, 2, sharedModeLayout)
assertEq(sharedModeState.gameMode, "pvp", "P2 monitor must be able to switch back to PVP")

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
}
for i = 1, 16 do
    infoLayout.collectionCards[i] = { x1 = i, y1 = 10, x2 = i, y2 = 10 }
end

Game.handleTouch(infoState, 1, 2, 2, infoLayout)
assertTrue(infoState.players[1].infoOpen, "UNIT INFO button must open the card database")

Game.handleTouch(infoState, 1, 2, 10, infoLayout)
assertEq(infoState.players[1].infoCardId, cards.list[2].id, "Tapping a card in Unit Info must inspect that card")

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
        assertEq(entity.maxHp, 1663, "Princess Tower must use five-percent HP nerf")
        sawPrincess = true
    elseif entity.kind == "tower" and entity.towerType == "king" then
        assertEq(entity.maxHp, 2565, "King Tower must use five-percent HP nerf")
        sawKing = true
    end
end
assertTrue(sawPrincess and sawKing, "Feature battle must contain both tower types")

local effectsBefore = #featureBattle.effects
featureBattle.players[1].emeralds = 10
assertTrue(Game.playCardFromSlot(featureBattle, 1, 1, 25, 112), "Playing a troop must succeed")
assertTrue(#featureBattle.effects > effectsBefore, "Deploying a troop must create combat feedback")

print("Smoke tests passed")

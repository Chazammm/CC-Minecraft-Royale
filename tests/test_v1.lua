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

local config = require("config")
local cards = require("src.cards")
local arena = require("src.arena")
local Game = require("src.game")
local pixelArena = require("src.pixel_arena")
local Bot = require("src.bot")
local render = require("src.render")
local adminRender = require("src.admin_render")
local musicManifest = require("src.music_manifest")

local function assertEq(actual, expected, message)
    if actual ~= expected then
        error((message or "assertEq failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function assertTrue(value, message)
    if not value then error(message or "assertTrue failed") end
end

assertEq(#cards.list, 22, "Card pool must contain twenty-two selectable cards with Evoker added")
assertEq(#cards.all, 23, "Card registry must contain selectable cards plus dev-only Guardian")
assertTrue(not cards.isSelectable("guardian"), "Guardian must be DEV ONLY and absent from normal card selection")
assertEq(#cards.defaultDeck(), 8, "Default deck must contain eight cards")
assertTrue(cards.isValidDeck(cards.defaultDeck()), "Default deck must be valid")
assertEq(cards.get("arrows").spell.cast, "arrows", "Arrow Volley must declare its explicit spell handler")
assertEq(cards.get("falling_anvil").spell.cast, "falling_anvil", "Falling Anvil must declare its explicit spell handler")

local seen = {}
for _, card in ipairs(cards.list) do
    assertTrue(not seen[card.id], "Card IDs must be unique: " .. tostring(card.id))
    seen[card.id] = true
    assertTrue(card.cost > 0, "Card must have a positive cost: " .. tostring(card.id))
    assertTrue(card.kind == "unit" or card.kind == "building" or card.kind == "spell", "Unknown card kind")

    local info = cards.getInfo(card.id)
    assertTrue(info ~= nil, "Every selectable card must have Unit Info text: " .. tostring(card.id))
    assertTrue(type(info.role) == "string" and #info.role > 0, "Every card needs a useful role label")
    assertTrue(type(info.description) == "string" and #info.description > 0, "Every card needs a description")

    -- The 57-wide monitor gives descriptions 53 columns. Keep copy short
    -- enough to fit the two-line tactical description budget.
    local width = 53
    local lineLength, lineCount = 0, 1
    for word in info.description:gmatch("%S+") do
        if lineLength == 0 then
            lineLength = #word
        elseif lineLength + 1 + #word <= width then
            lineLength = lineLength + 1 + #word
        else
            lineCount = lineCount + 1
            lineLength = #word
        end
    end
    assertTrue(
        lineCount <= 2,
        "Card description must fit two Unit Info lines: " .. tostring(card.id)
    )
end

local deckState = Game.new()
assertEq(#deckState.players[1].deck, 0, "Player 1 must boot with an empty deck")
assertEq(#deckState.players[2].deck, 0, "Player 2 must boot with an empty deck")
assertEq(#deckState.players[1].hand, 0, "Empty boot deck must not create a hand")
assertEq(#deckState.players[1].queue, 0, "Empty boot deck must not create a queue")
assertTrue(not cards.isValidDeck(deckState.players[1].deck), "Empty boot deck must be invalid for READY")

for _, cardId in ipairs(cards.defaultDeck()) do
    assertTrue(Game.toggleDeckCard(deckState, 1, cardId), "Boot deck must allow adding " .. cardId)
end
assertEq(#deckState.players[1].deck, 8, "Selecting eight cards must fill the boot deck")
assertTrue(cards.isValidDeck(deckState.players[1].deck), "Selected eight-card deck must be valid")

local villagerCard = cards.get("villager")
assertTrue(villagerCard and villagerCard.kind == "unit", "Villager must be a unit, not a building")
assertEq(villagerCard.cost, 7, "Villager must cost seven Emeralds")
assertTrue(villagerCard.unit.passive, "Villager must be passive")
assertEq(villagerCard.unit.lifetime, 50, "Villager must last fifty seconds")
assertEq(villagerCard.unit.emeraldBoost, 0.616, "Villager boost must target four-Emerald net value")

local bankEvo = cards.evolvedCopy("villager")
assertTrue(bankEvo ~= nil, "Villager must expose Emerald Bank Evolution")
assertEq(cards.evolutionCycles("villager"), 3, "Emerald Bank must evolve on the fourth Villager play")
assertEq(bankEvo.name, "Emerald Bank", "Villager Evolution must be Emerald Bank")
assertTrue(math.abs(bankEvo.unit.maxHp - 194.25) < 0.000001, "Emerald Bank must have exactly five percent more HP")
assertEq(bankEvo.unit.lifetime, 70, "Emerald Bank must last twenty seconds longer")
assertEq(bankEvo.unit.emeraldBoost, villagerCard.unit.emeraldBoost, "Emerald Bank must preserve Villager Emerald production")

local ironGolemCard = cards.get("iron_golem")
local diamondGolem = cards.evolvedCopy("iron_golem")
assertTrue(diamondGolem ~= nil, "Iron Golem must expose Diamond Golem Evolution")
assertEq(cards.evolutionCycles("iron_golem"), 2, "Diamond Golem must evolve on the third Iron Golem play")
assertEq(cards.evolutionCost("iron_golem"), 5, "Diamond Golem must keep the base 5E cost")
assertEq(diamondGolem.name, "Diamond Golem", "Iron Golem Evolution must be Diamond Golem")
assertTrue(
    math.abs(diamondGolem.unit.maxHp - ironGolemCard.unit.maxHp * 1.095) < 0.000001,
    "Diamond Golem must have exactly 9.5 percent more HP"
)
assertEq(diamondGolem.unit.groundPulse.interval, 2.0, "Diamond Golem stomp must trigger every two seconds")
assertEq(diamondGolem.unit.groundPulse.damage, 25, "Diamond Golem stomp must deal twenty-five damage")
assertEq(diamondGolem.unit.groundPulse.radius, 8.0, "Diamond Golem stomp must use eight range")
assertEq(diamondGolem.unit.visualVariant, "diamond_golem", "Diamond Golem needs its cyan visual variant")

local evokerCard = cards.get("evoker")
local vexUnit = cards.getInternalUnit("vex")
assertTrue(evokerCard ~= nil and cards.isSelectable("evoker"), "Evoker must be a normal selectable card")
assertEq(evokerCard.cost, 6, "Evoker must cost six Emeralds")
assertEq(evokerCard.unit.maxHp, 400, "Evoker must start with 400 HP")
assertEq(evokerCard.unit.attackRange, 18.0, "Evoker fangs must use 18 range")
assertEq(evokerCard.unit.attackCooldown, 2.40, "Evoker fang cooldown must be 2.4 seconds")
assertEq(evokerCard.unit.fangAttack.damage, 85, "Evoker fangs must deal 85 damage")
assertEq(evokerCard.unit.fangAttack.warning, 0.40, "Evoker fangs must have a short warning")
assertEq(evokerCard.unit.fangAttack.closeRange, 4.0, "Evoker must switch to close ring fangs at four range")
assertEq(evokerCard.unit.periodicSpawn.template, "vex", "Evoker must summon Vexes")
assertEq(evokerCard.unit.periodicSpawn.initialDelay, 4, "First Vex wave must arrive after four seconds")
assertEq(evokerCard.unit.periodicSpawn.interval, 14, "Vex summon cooldown must be fourteen seconds")
assertEq(evokerCard.unit.periodicSpawn.count, 3, "Evoker must summon three Vexes per wave")
assertEq(evokerCard.unit.periodicSpawn.maxAlive, 3, "Evoker must cap its living Vexes at three")
assertTrue(vexUnit ~= nil and vexUnit.flying, "Vex must be an internal flying unit")
assertEq(vexUnit.maxHp, 75, "Vex must have 75 HP")
assertEq(vexUnit.damage, 30, "Vex damage must stay at the user-approved 30")
assertEq(vexUnit.attackCooldown, 0.80, "Vex attack cooldown must be 0.8 seconds")
assertEq(vexUnit.moveSpeed, 11.5, "Vex must be a very fast flyer")
assertEq(vexUnit.lifetime, 9.0, "Vex must expire after nine seconds")

local guardianCard = cards.get("guardian")
assertTrue(guardianCard ~= nil and guardianCard.kind == "unit", "Guardian must remain registered as a dev-only unit")
assertTrue(guardianCard.devOnly == true, "Guardian must be marked devOnly")
assertEq(guardianCard.cost, 6, "Guardian must cost six Emeralds")
assertEq(guardianCard.placement, "water", "Guardian must be water-only")
assertEq(guardianCard.unit.maxHp, 90, "Guardian must die to exactly three 30-damage Skeleton arrows")
assertEq(guardianCard.unit.maxHp, cards.get("skeleton").unit.damage * 3, "Guardian HP must equal exactly three Skeleton arrows")
assertEq(guardianCard.unit.moveSpeed, 0, "Guardian must be stationary")
assertTrue(guardianCard.unit.waterOnly, "Guardian unit stats must be water-only")
assertTrue(guardianCard.unit.canAttackAir, "Guardian beam must be able to target flying units")
assertEq(guardianCard.unit.attackRange, 18.0, "Guardian must use the improved 18-range beam")
assertEq(guardianCard.unit.beam.baseDps, 35, "Guardian beam must start at 35 DPS")
assertEq(guardianCard.unit.beam.maxDps, 350, "Guardian beam must ramp to 350 DPS")
assertEq(guardianCard.unit.beam.rampSeconds, 4.0, "Guardian beam must take four seconds to fully ramp")
assertEq(guardianCard.unit.beam.chargeLossOnHit, 0.20, "Guardian must lose twenty percent current beam charge when hit")
assertEq(guardianCard.unit.spikeReflectFlying, 0.05, "Guardian spikes must reflect five percent damage to flying attackers")

local elderEvo = cards.evolvedCopy("guardian")
assertTrue(elderEvo ~= nil, "Guardian must expose Elder Guardian Evolution")
assertEq(cards.evolutionCycles("guardian"), 2, "Elder Guardian must evolve on the third Guardian play")
assertEq(cards.evolutionCost("guardian"), 6, "Elder Guardian must keep the base 6E cost")
assertEq(elderEvo.name, "Elder Guardian", "Guardian Evolution must be Elder Guardian")
assertEq(elderEvo.unit.maxHp, 180, "Elder Guardian must have exactly double Guardian HP")
assertEq(elderEvo.unit.attackRange, 18.0, "Elder Guardian must inherit Guardian's improved range")
assertEq(elderEvo.unit.aggroRange, 18.0, "Elder Guardian must inherit Guardian's improved aggro range")
assertTrue(elderEvo.unit.waterOnly, "Elder Guardian must preserve Guardian water-only targetability")

local benchedDeck = cards.defaultDeck()
benchedDeck[8] = "guardian"
assertTrue(not cards.isValidDeck(benchedDeck), "A normal deck containing Guardian must be invalid while it is benched")

local benchedState = Game.new()
benchedState.players[1].deck = cards.defaultDeck()
assertTrue(
    not Game.toggleDeckCard(benchedState, 1, "guardian"),
    "Normal deck API must reject dev-only Guardian"
)
benchedState.players[1].deck[8] = "guardian"
assertTrue(
    not Game.setEvolutionCard(benchedState, 1, "guardian"),
    "Normal Evolution Slot API must reject dev-only Elder Guardian"
)
assertEq(elderEvo.unit.globalEnemyMoveSlow, 0.05, "Elder Guardian must globally slow enemy movement by five percent")
assertEq(elderEvo.unit.beam.maxDps, guardianCard.unit.beam.maxDps, "Elder Guardian beam must otherwise stay identical")
assertEq(elderEvo.unit.spikeReflectFlying, guardianCard.unit.spikeReflectFlying, "Elder Guardian spikes must stay identical")

local riverMid = (config.ARENA.riverTop + config.ARENA.riverBottom) / 2
assertTrue(arena.placementAllowed(1, 50, riverMid, "water", Game.new()), "Guardian must be placeable in open river water")
assertTrue(not arena.placementAllowed(1, 27, riverMid, "water", Game.new()), "Guardian must not be placeable on a bridge")
assertTrue(not arena.placementAllowed(1, 50, 110, "water", Game.new()), "Guardian must not be placeable on land")

local zombieCard = cards.get("zombie")
assertEq(zombieCard.unit.maxHp, 523, "Zombie HP must reflect the latest five-percent nerf")

local endermiteCard = cards.get("endermite")
assertEq(endermiteCard.cost, 1, "Endermite must cost one Emerald")
assertTrue(endermiteCard.unit.maxHp < 150, "Endermite should have low HP")
assertTrue(endermiteCard.unit.damage < 25, "Endermite should have low DPS damage")

local batCard = cards.get("bat_swarm")
assertEq(batCard.unit.maxHp, 45, "Bat Swarm must be extremely fragile")
assertEq(batCard.unit.damage, 17, "Bat Swarm damage must reflect the controlled-analysis nerf")
assertTrue(batCard.unit.maxHp < 80, "Princess Tower must one-shot each Bat")

local skeletonCard = cards.get("skeleton")
local snowGolemCard = cards.get("snow_golem")
local witchCard = cards.get("witch")
assertEq(skeletonCard.unit.maxHp, 168, "Skeleton HP must reflect the latest five-percent nerf")
assertEq(skeletonCard.unit.damage, 30, "Skeleton damage must stay at thirty")
assertEq(skeletonCard.unit.attackRange, 15.0, "Skeleton range must reflect the controlled-analysis nerf")
assertEq(skeletonCard.unit.retreatSpeedMultiplier, 0.85, "Skeleton retreat speed must reflect the controlled-analysis nerf")
assertTrue(
    skeletonCard.unit.preferredMinRange ~= nil,
    "Skeleton must keep its kiting distance"
)
assertTrue(
    snowGolemCard.unit.preferredMinRange == nil,
    "Snow Golem must not kite like Skeleton"
)
assertEq(snowGolemCard.unit.onHitSlow.duration, 1.0, "Snow Golem slow must last one second")
assertEq(witchCard.cost, 5, "Witch must cost five Emeralds")

local ironGolemCard = cards.get("iron_golem")
local cannonCard = cards.get("cannon")
local blazeCard = cards.get("blaze")
local creeperCard = cards.get("creeper")
assertEq(ironGolemCard.cost, 5, "Iron Golem must cost five Emeralds")
assertEq(ironGolemCard.unit.maxHp, 1514.7, "Iron Golem HP must include the ten-percent buff")
assertEq(cannonCard.building.maxHp, 618, "Cannon HP must reflect the five-percent nerf")
assertEq(cannonCard.building.damage, 64, "Cannon damage must reflect the two-percent nerf")
assertEq(blazeCard.unit.maxHp, 257, "Blaze HP must reflect the latest five-percent nerf")
assertEq(creeperCard.unit.maxHp, 404, "Creeper HP must include the one-percent buff")
assertEq(creeperCard.unit.proximityExplosion.fuseTime, 0.65, "Creeper fuse must be very short")

local anvilCard = cards.get("falling_anvil")
assertTrue(anvilCard and anvilCard.kind == "spell", "Falling Anvil must be a selectable spell")
assertEq(anvilCard.cost, 3, "Falling Anvil must cost three Emeralds")
assertEq(anvilCard.spell.delay, 2.7, "Falling Anvil must have a 2.7-second delay")
assertEq(anvilCard.spell.damage, 549, "Falling Anvil damage must stay at 549")
assertEq(anvilCard.spell.radius, 6.05, "Falling Anvil radius must be ten percent larger")
assertTrue(anvilCard.spell.groundOnly == false, "Falling Anvil must hit flying and grounded units")

local portalCard = cards.get("nether_portal")
assertTrue(portalCard and portalCard.kind == "building", "Nether Portal must be a selectable building")
assertEq(portalCard.cost, 3, "Nether Portal must cost three Emeralds")
assertTrue(portalCard.building.periodicSpawn ~= nil, "Nether Portal must periodically spawn Piglins")
assertEq(portalCard.building.periodicSpawn.template, "piglin", "Nether Portal must spawn the internal Piglin")
assertEq(portalCard.building.lifetime, 23, "Nether Portal must expire before its fourth scheduled Piglin spawn")

local piglinTemplate = cards.getInternalUnit("piglin")
assertTrue(piglinTemplate ~= nil, "Piglin must exist as an internal unit")
assertTrue(cards.get("piglin") == nil, "Piglin must not be directly selectable as a card")
assertEq(piglinTemplate.lifetime, 10.0, "Piglin must zombify/despawn after ten seconds")
assertTrue(piglinTemplate.hybridAttack ~= nil, "Piglin must support ranged and melee attacks")
assertTrue(
    piglinTemplate.hybridAttack.meleeDamage > piglinTemplate.hybridAttack.rangedDamage,
    "Piglin axe hit should be stronger than its crossbow shot"
)

do
local witherSkeletonCard = cards.get("wither_skeleton")
assertEq(witherSkeletonCard.cost, 3, "Wither Skeleton must cost three Emeralds")
assertTrue(
    witherSkeletonCard.unit.maxHp < zombieCard.unit.maxHp,
    "Wither Skeleton must trade HP away versus Zombie"
)
assertTrue(
    witherSkeletonCard.unit.damage > zombieCard.unit.damage,
    "Wither Skeleton must gain damage versus Zombie"
)
assertEq(witherSkeletonCard.unit.maxHp, 470, "Wither Skeleton starting HP must be 470")
assertEq(witherSkeletonCard.unit.damage, 88, "Wither Skeleton starting damage must be 88")

local slimeCard = cards.get("slime")
local magmaCubeCard = cards.get("magma_cube")
assertEq(magmaCubeCard.cost, slimeCard.cost, "Magma Cube must cost the same as Slime")
assertTrue(
    math.abs(magmaCubeCard.unit.maxHp - slimeCard.unit.maxHp * 0.95) < 0.000001,
    "Magma Cube must have five percent less HP than Slime"
)
assertTrue(
    math.abs(magmaCubeCard.unit.damage - slimeCard.unit.damage * 1.05) < 0.000001,
    "Magma Cube must have five percent more damage than Slime"
)
assertEq(magmaCubeCard.unit.splitOnDeath.template, "mini_magma_cube", "Magma Cube must split into Mini Magma Cubes")

local miniSlime = cards.getInternalUnit("mini_slime")
local miniMagma = cards.getInternalUnit("mini_magma_cube")
assertTrue(
    math.abs(miniMagma.maxHp - miniSlime.maxHp * 0.95) < 0.000001,
    "Mini Magma Cube must have five percent less HP than Mini Slime"
)
assertTrue(
    math.abs(miniMagma.damage - miniSlime.damage * 1.05) < 0.000001,
    "Mini Magma Cube must have five percent more damage than Mini Slime"
)

local outpostCard = cards.get("pillager_outpost")
assertEq(outpostCard.cost, cannonCard.cost, "Pillager Outpost must cost the same as Cannon")
assertEq(outpostCard.building.lifetime, cannonCard.building.lifetime, "Pillager Outpost must last as long as Cannon")
assertEq(outpostCard.building.maxHp, cannonCard.building.maxHp * 0.75, "Pillager Outpost must have exactly 25 percent less HP")
assertEq(outpostCard.building.damage, cannonCard.building.damage * 0.75, "Pillager Outpost must have exactly 25 percent less damage")
assertTrue(outpostCard.building.canAttackAir, "Pillager Outpost must attack flying units")
end

assertEq(config.MATCH.normalTime, 150, "Regulation must last two minutes thirty")
assertEq(config.MATCH.overtimeTime, 150, "Overtime must last two minutes thirty")
assertEq(config.MATCH.overtimeMultiplier, 2, "Most of overtime must use double Emerald generation")
assertEq(config.MATCH.overtimeFinalSeconds, 30, "Final overtime boost must begin with thirty seconds left")
assertEq(config.MATCH.overtimeFinalMultiplier, 3, "Final thirty seconds must use triple Emerald generation")
assertEq(config.MATCH.tiebreakerDamagePerSecond, 300, "Tiebreaker drain rate must stay deterministic")
assertEq(config.BUILDINGS.lifetimeDecayMultiplier, 1.15, "Buildings must naturally lose HP fifteen percent faster")
assertEq(config.TOWERS.princessRange, 42.5, "Princess Towers must engage shortly after a bridge exit")
assertEq(config.TOWERS.kingRange, 27, "King Tower range must remain unchanged")
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
assertEq(#state.players[1].deck, 0, "Normal lobby must boot with an empty P1 deck")
assertEq(#state.players[2].deck, 0, "Normal lobby must boot with an empty P2 deck")
assertEq(#state.players[1].hand, 0, "Lobby boot must not pre-deal a hand")
assertEq(#state.players[1].queue, 0, "Lobby boot must not pre-fill a queue")

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
assertTrue(not state.players[1].ready, "READY must reject an empty boot deck")
assertEq(state.players[1].feedback, "SELECT EXACTLY 8 CARDS", "Empty READY must explain the deck requirement")

state.players[1].deck = cards.defaultDeck()
state.players[2].deck = cards.defaultDeck()

Game.handleTouch(state, 1, 15, 11, layout)
assertTrue(state.players[1].ready, "Player 1 ready toggle failed with a valid deck")
Game.handleTouch(state, 2, 15, 11, layout)
assertEq(state.phase, "countdown", "Both valid decks ready must start countdown")

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

-- Headless benchmark mode may remove only presentation work. A deterministic
-- projectile fight must produce exactly the same combat state as normal mode.
local function headlessParitySnapshot(headless)
    local options = headless and { headlessSimulation = true } or nil
    local parityState = Game.new(nil, options)
    Game.debugLoadScenario(parityState, "empty")
    Game.debugSpawnCard(parityState, 1, "skeleton", 50, 100)
    Game.debugSpawnCard(parityState, 2, "zombie", 50, 84)
    Game.debugSetPaused(parityState, false)

    for _ = 1, 80 do Game.update(parityState, 0.10) end

    local snapshot = {}
    for _, entity in ipairs(parityState.entities) do
        snapshot[#snapshot + 1] = {
            id = entity.id,
            owner = entity.owner,
            name = entity.name,
            hp = entity.hp,
            x = entity.x,
            y = entity.y,
            targetId = entity.targetId,
            lockedTargetId = entity.lockedTargetId,
            attackCooldownLeft = entity.attackCooldownLeft,
        }
    end

    return parityState, snapshot
end

local normalParityState, normalParity = headlessParitySnapshot(false)
local fastParityState, fastParity = headlessParitySnapshot(true)

assertTrue(fastParityState.headlessSimulation, "Benchmark state must explicitly enable headless simulation")
assertEq(#fastParityState.effects, 0, "Headless simulation must not allocate visual effects")

-- The benchmark may skip countdown updates only because those ticks are inert.
-- Verify the direct headless start produces the same battle-start state.
local countdownStartState = Game.new(nil, { headlessSimulation = true })
local directStartState = Game.new(nil, { headlessSimulation = true })
countdownStartState.players[1].deck = cards.defaultDeck()
countdownStartState.players[2].deck = cards.defaultDeck()
directStartState.players[1].deck = cards.defaultDeck()
directStartState.players[2].deck = cards.defaultDeck()

Game.startCountdown(countdownStartState)
for _ = 1, math.ceil(config.MATCH.countdown / config.TICK_RATE) + 2 do
    if countdownStartState.phase == "battle" then break end
    Game.update(countdownStartState, config.TICK_RATE)
end

local directStarted = Game.startHeadlessBattle(directStartState)
assertTrue(directStarted, "Headless benchmark must support direct battle start")
assertEq(countdownStartState.phase, "battle", "Normal countdown reference must reach battle")
assertEq(directStartState.phase, countdownStartState.phase, "Direct headless start must preserve phase")
assertEq(directStartState.timeLeft, countdownStartState.timeLeft, "Direct headless start must preserve match clock")
assertEq(directStartState.combatTick, countdownStartState.combatTick, "Direct headless start must preserve combat tick")
assertEq(directStartState.nextEntityId, countdownStartState.nextEntityId, "Direct headless start must preserve entity ids")
assertEq(directStartState.stats.elapsed, countdownStartState.stats.elapsed, "Direct headless start must preserve elapsed stats")
assertEq(#directStartState.entities, #countdownStartState.entities, "Direct headless start must create the same towers")

for playerId = 1, 2 do
    local directPlayer = directStartState.players[playerId]
    local countdownPlayer = countdownStartState.players[playerId]
    assertEq(directPlayer.emeralds, countdownPlayer.emeralds, "Direct headless start must preserve starting Emeralds")
    for slot = 1, 4 do
        assertEq(directPlayer.hand[slot], countdownPlayer.hand[slot], "Direct headless start must preserve starting hand")
    end
    for slot = 1, #countdownPlayer.queue do
        assertEq(directPlayer.queue[slot], countdownPlayer.queue[slot], "Direct headless start must preserve card queue")
    end
end

for i = 1, #countdownStartState.entities do
    local directTower = directStartState.entities[i]
    local countdownTower = countdownStartState.entities[i]
    assertEq(directTower.id, countdownTower.id, "Direct headless start must preserve tower ids")
    assertEq(directTower.owner, countdownTower.owner, "Direct headless start must preserve tower owners")
    assertEq(directTower.towerType, countdownTower.towerType, "Direct headless start must preserve tower types")
    assertEq(directTower.hp, countdownTower.hp, "Direct headless start must preserve tower HP")
    assertEq(directTower.x, countdownTower.x, "Direct headless start must preserve tower X")
    assertEq(directTower.y, countdownTower.y, "Direct headless start must preserve tower Y")
end

local rejectedDirectStart = Game.startHeadlessBattle(Game.new())
assertTrue(not rejectedDirectStart, "Direct battle start must stay headless-only")
assertEq(#normalParity, #fastParity, "Headless mode must preserve surviving entity count")
for i = 1, #normalParity do
    local normal = normalParity[i]
    local fast = fastParity[i]
    assertEq(fast.id, normal.id, "Headless mode must preserve entity ids/order")
    assertEq(fast.owner, normal.owner, "Headless mode must preserve entity owners")
    assertEq(fast.name, normal.name, "Headless mode must preserve entity identity")
    assertEq(fast.hp, normal.hp, "Headless mode must preserve exact HP outcomes")
    assertEq(fast.x, normal.x, "Headless mode must preserve exact X positions")
    assertEq(fast.y, normal.y, "Headless mode must preserve exact Y positions")
    assertEq(fast.targetId, normal.targetId, "Headless mode must preserve target acquisition")
    assertEq(fast.lockedTargetId, normal.lockedTargetId, "Headless mode must preserve target locks")
    assertEq(
        fast.attackCooldownLeft,
        normal.attackCooldownLeft,
        "Headless mode must preserve attack timing"
    )
end


local forwardOrderState = Game.new()
Game.debugLoadScenario(forwardOrderState, "empty")
Game.debugSpawnCard(forwardOrderState, 1, "zombie", 50, 80)
Game.debugSpawnCard(forwardOrderState, 2, "zombie", 50, 80)
for _, entity in ipairs(forwardOrderState.entities) do entity.hp = 30 end
Game.debugSetPaused(forwardOrderState, false)
forwardOrderState.combatTick = 0
Game.update(forwardOrderState, 0.10)

local forwardP1Alive, forwardP2Alive = false, false
for _, entity in ipairs(forwardOrderState.entities) do
    if entity.owner == 1 and entity.alive then forwardP1Alive = true end
    if entity.owner == 2 and entity.alive then forwardP2Alive = true end
end
assertTrue(
    forwardP1Alive and not forwardP2Alive,
    "Odd combat ticks must process the forward entity order"
)

local reverseOrderState = Game.new()
Game.debugLoadScenario(reverseOrderState, "empty")
Game.debugSpawnCard(reverseOrderState, 1, "zombie", 50, 80)
Game.debugSpawnCard(reverseOrderState, 2, "zombie", 50, 80)
for _, entity in ipairs(reverseOrderState.entities) do entity.hp = 30 end
Game.debugSetPaused(reverseOrderState, false)
reverseOrderState.combatTick = 1
Game.update(reverseOrderState, 0.10)

local reverseP1Alive, reverseP2Alive = false, false
for _, entity in ipairs(reverseOrderState.entities) do
    if entity.owner == 1 and entity.alive then reverseP1Alive = true end
    if entity.owner == 2 and entity.alive then reverseP2Alive = true end
end
assertTrue(
    reverseP2Alive and not reverseP1Alive,
    "Even combat ticks must reverse update order instead of permanently favoring earlier entities"
)

do
local outpostCard = cards.get("pillager_outpost")
local buildingDecayState = Game.new()
Game.debugLoadScenario(buildingDecayState, "empty")
Game.debugSpawnCard(buildingDecayState, 1, "cannon", 50, 100)

local decayCannon
for _, entity in ipairs(buildingDecayState.entities) do
    if entity.name == "Cannon" then decayCannon = entity end
end
assertTrue(decayCannon ~= nil, "Building decay test must spawn a Cannon")
assertEq(decayCannon.hp, cannonCard.building.maxHp, "Building must spawn at full HP")

Game.debugSetPaused(buildingDecayState, false)
local buildingDecayMultiplier = config.BUILDINGS.lifetimeDecayMultiplier
for _ = 1, 70 do Game.update(buildingDecayState, 0.25) end
assertTrue(decayCannon.alive, "Cannon must still be alive halfway through its nominal lifetime")
local expectedHalfNominalHp = cannonCard.building.maxHp * (1 - 0.5 * buildingDecayMultiplier)
assertTrue(
    math.abs(decayCannon.hp - expectedHalfNominalHp) < 0.01,
    "Building HP must use the configured faster lifetime decay"
)

-- 35s / 1.15 ~= 30.43s effective natural lifetime.
for _ = 1, 51 do Game.update(buildingDecayState, 0.25) end
assertTrue(decayCannon.alive, "Cannon must survive just before its faster natural decay endpoint")
Game.update(buildingDecayState, 0.25)
assertTrue(not decayCannon.alive, "Cannon must die around nominal lifetime / decay multiplier")

local outpostDecayState = Game.new()
Game.debugLoadScenario(outpostDecayState, "empty")
Game.debugSpawnCard(outpostDecayState, 1, "pillager_outpost", 50, 100)
Game.debugSetPaused(outpostDecayState, false)

local decayOutpost
for _, entity in ipairs(outpostDecayState.entities) do
    if entity.name == "Pillager Outpost" then decayOutpost = entity end
end
for _ = 1, 70 do Game.update(outpostDecayState, 0.25) end
local expectedOutpostHalfHp = outpostCard.building.maxHp * (1 - 0.5 * buildingDecayMultiplier)
assertTrue(
    math.abs(decayOutpost.hp - expectedOutpostHalfHp) < 0.01,
    "Pillager Outpost must use the same faster lifetime HP-decay system"
)

local outpostAirState = Game.new()
Game.debugLoadScenario(outpostAirState, "empty")
Game.debugSpawnCard(outpostAirState, 1, "pillager_outpost", 50, 100)
Game.debugSpawnCard(outpostAirState, 2, "bat_swarm", 50, 85)
Game.debugSetPaused(outpostAirState, false)

local outpostBatHp = {}
for _, entity in ipairs(outpostAirState.entities) do
    if entity.name == "Bat Swarm" then outpostBatHp[entity.id] = entity.hp end
end

for _ = 1, 12 do Game.update(outpostAirState, 0.10) end

local survivingBatHp = {}
for _, entity in ipairs(outpostAirState.entities) do
    if entity.name == "Bat Swarm" then
        survivingBatHp[entity.id] = entity.hp
    end
end

local outpostHitAir = false
for id, before in pairs(outpostBatHp) do
    local after = survivingBatHp[id]
    if after == nil or after < before then
        outpostHitAir = true
        break
    end
end
assertTrue(outpostHitAir, "Pillager Outpost must actually shoot flying troops")

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

-- A target assignment is not yet a combat lock. Before either troop attacks,
-- a nearer enemy may still distract it away from the distant tower.
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

-- The Golem is marching toward a tower but has not attacked it yet. A Cannon
-- placed inside aggro range must still be able to pull it before lock-on.
pullGolem.targetId = distantEnemyTower.id
Game.debugSetPaused(golemPullState, false)
Game.update(golemPullState, 0.10)

assertEq(
    pullGolem.targetId,
    pullCannon.id,
    "Iron Golem must retarget from a tower to a closer Cannon before lock-on"
)
assertTrue(
    pullGolem.lockedTargetId == nil,
    "Being pulled while approaching must not count as an attack lock"
)

-- Normal troop: once the first tower attack starts, a newly spawned troop
-- beside it must not steal aggro.
local troopLockState = Game.new()
Game.debugLoadScenario(troopLockState, "king")
Game.debugSpawnCard(troopLockState, 1, "zombie", 50, 100)

local lockZombie, lockEnemyKing
for _, entity in ipairs(troopLockState.entities) do
    if entity.name == "Zombie" and entity.owner == 1 then lockZombie = entity end
    if entity.kind == "tower" and entity.towerType == "king" and entity.owner == 2 then
        lockEnemyKing = entity
    end
end
assertTrue(lockZombie and lockEnemyKing, "Troop lock test needs Zombie and enemy King")

lockZombie.x = lockEnemyKing.x
lockZombie.y = lockEnemyKing.y + 2
Game.debugSetPaused(troopLockState, false)
Game.update(troopLockState, 0.10)

assertEq(lockZombie.targetId, lockEnemyKing.id, "Zombie must attack the nearby King Tower")
assertEq(
    lockZombie.lockedTargetId,
    lockEnemyKing.id,
    "First attack must lock the Zombie onto its target"
)

Game.debugSpawnCard(
    troopLockState,
    2,
    "endermite",
    lockZombie.x + 1,
    lockZombie.y
)
Game.update(troopLockState, 0.10)

assertEq(
    lockZombie.targetId,
    lockEnemyKing.id,
    "Newly spawned troop must not pull a Zombie off a tower after lock-on"
)
assertEq(
    lockZombie.lockedTargetId,
    lockEnemyKing.id,
    "Zombie tower lock must persist while the tower remains alive"
)

-- Killing the locked target must release the lock and permit retargeting.
lockEnemyKing.hp = 1
lockZombie.attackCooldownLeft = 0
Game.update(troopLockState, 0.10)
Game.update(troopLockState, 0.10)
assertTrue(
    lockZombie.lockedTargetId ~= lockEnemyKing.id,
    "Target death must release the old combat lock"
)

-- Building-targeting unit: Cannon can pull before the first hit, but not after
-- the Golem has actually connected with the tower.
local golemLockState = Game.new()
Game.debugLoadScenario(golemLockState, "full")
Game.debugSpawnCard(golemLockState, 1, "iron_golem", 50, 100)

local lockedGolem, lockedTower
for _, entity in ipairs(golemLockState.entities) do
    if entity.name == "Iron Golem" and entity.owner == 1 then lockedGolem = entity end
    if entity.kind == "tower" and entity.owner == 2 then
        if not lockedTower or entity.y > lockedTower.y then
            lockedTower = entity
        end
    end
end
assertTrue(lockedGolem and lockedTower, "Golem lock test needs Golem and enemy tower")

lockedGolem.x = lockedTower.x
lockedGolem.y = lockedTower.y + 2
Game.debugSetPaused(golemLockState, false)
Game.update(golemLockState, 0.10)
assertEq(
    lockedGolem.lockedTargetId,
    lockedTower.id,
    "Iron Golem must lock the tower after its first hit"
)

Game.debugSpawnCard(
    golemLockState,
    2,
    "cannon",
    lockedGolem.x + 1,
    lockedGolem.y + 1
)
Game.update(golemLockState, 0.10)

assertEq(
    lockedGolem.targetId,
    lockedTower.id,
    "Cannon spawned after tower lock must not pull the Iron Golem"
)
assertEq(
    lockedGolem.lockedTargetId,
    lockedTower.id,
    "Iron Golem must remain locked to the tower until it dies"
)
end

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
assertEq(
    testCreeper.lockedTargetId,
    testZombie.id,
    "Starting the Creeper fuse must count as attack commitment and lock its target"
)
assertTrue(
    math.abs(testCreeper.fuseRemaining - 0.65) < 0.000001,
    "Creeper must start with the new 0.65-second fuse"
)

Game.update(creeperState, 0.25)
Game.update(creeperState, 0.25)
Game.update(creeperState, 0.14)
assertTrue(testCreeper.alive, "Creeper must still be alive just before the 0.65-second fuse ends")
Game.update(creeperState, 0.02)

assertTrue(not testCreeper.alive, "Creeper must self-destruct after its short fuse")
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
local expectedKiteDistance = 7.5 * 0.5 * 0.85 * 0.20
assertTrue(
    math.abs(kiteDistance - expectedKiteDistance) < 0.05,
    "Skeleton retreat speed must combine active slow with its fifteen-percent retreat penalty"
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

local magmaSplitState = Game.new()
Game.debugLoadScenario(magmaSplitState, "empty")
Game.debugSpawnCard(magmaSplitState, 1, "magma_cube", 50, 100)
Game.debugSpawnCard(magmaSplitState, 2, "zombie", 50, 98)

local testMagma
for _, entity in ipairs(magmaSplitState.entities) do
    if entity.name == "Magma Cube" then testMagma = entity end
end
assertTrue(testMagma ~= nil, "Magma split test must spawn a Magma Cube")
testMagma.hp = 1
Game.debugSetPaused(magmaSplitState, false)
Game.update(magmaSplitState, 0.10)

local miniMagmaCount = 0
for _, entity in ipairs(magmaSplitState.entities) do
    if entity.name == "Mini Magma Cube" then miniMagmaCount = miniMagmaCount + 1 end
end
assertEq(miniMagmaCount, 2, "Dead Magma Cube must split into two Mini Magma Cubes")

local bridgeSplitState = Game.new()
Game.debugLoadScenario(bridgeSplitState, "empty")
local bridgeX = config.ARENA.bridgeCenters[1]
local bridgeY = (config.ARENA.riverTop + config.ARENA.riverBottom) / 2
Game.debugSpawnCard(bridgeSplitState, 1, "slime", bridgeX, bridgeY)
Game.debugSpawnCard(bridgeSplitState, 2, "zombie", bridgeX, bridgeY - 2)

local bridgeSlime
for _, entity in ipairs(bridgeSplitState.entities) do
    if entity.name == "Slime" then bridgeSlime = entity end
end
bridgeSlime.hp = 1
Game.debugSetPaused(bridgeSplitState, false)
Game.update(bridgeSplitState, 0.10)

local bridgeMiniCount = 0
for _, entity in ipairs(bridgeSplitState.entities) do
    if entity.name == "Mini Slime" then bridgeMiniCount = bridgeMiniCount + 1 end
end
assertEq(
    bridgeMiniCount,
    2,
    "Slime splits must not disappear when offset positions fall beside a bridge"
)

local anvilState = Game.new()
Game.debugLoadScenario(anvilState, "empty")
Game.debugSpawnCard(anvilState, 2, "zombie", 50, 80)
local anvilZombie
for _, entity in ipairs(anvilState.entities) do
    if entity.name == "Zombie" then anvilZombie = entity end
end
assertTrue(anvilZombie ~= nil, "Anvil test Zombie must exist")
assertTrue(Game.debugSpawnCard(anvilState, 1, "falling_anvil", 50, 80), "Admin must cast Falling Anvil")
assertEq(anvilZombie.hp, 523, "Falling Anvil must not deal instant damage")
assertEq(#anvilState.pendingSpells, 1, "Falling Anvil must wait as a pending spell")

Game.debugSetPaused(anvilState, false)
for _ = 1, 10 do Game.update(anvilState, 0.25) end
Game.update(anvilState, 0.19)
assertEq(anvilZombie.hp, 523, "Falling Anvil must still be harmless before 2.7 seconds")
Game.update(anvilState, 0.02)
assertTrue(not anvilZombie.alive, "Falling Anvil must now one-shot the lower-HP Zombie")
assertEq(#anvilState.pendingSpells, 0, "Falling Anvil must resolve after its 2.7-second delay")

-- Regression: resolving one pending spell may end the match and replace the
-- pending-spell table while another delayed spell is still queued. The update
-- must stop cleanly instead of indexing the new empty table with the old count.
local pendingFinishState = Game.new()
pendingFinishState.players[1].deck = cards.defaultDeck()
pendingFinishState.players[2].deck = cards.defaultDeck()
Game.handleTouch(pendingFinishState, 1, 15, 11, layout)
Game.handleTouch(pendingFinishState, 2, 15, 11, layout)
for _ = 1, 13 do Game.update(pendingFinishState, 0.25) end
assertEq(pendingFinishState.phase, "battle", "Pending-spell finish regression must reach battle")

local pendingFinishKing
for _, entity in ipairs(pendingFinishState.entities) do
    if entity.kind == "tower" and entity.owner == 2 and entity.towerType == "king" then
        pendingFinishKing = entity
        break
    end
end
assertTrue(pendingFinishKing ~= nil, "Pending-spell finish regression needs the enemy King Tower")
pendingFinishKing.hp = 1

local regressionAnvilSpell = cards.get("falling_anvil").spell
pendingFinishState.pendingSpells = {
    {
        kind = "falling_anvil",
        owner = 1,
        cardId = "falling_anvil",
        x = pendingFinishKing.x,
        y = pendingFinishKing.y,
        remaining = 0.01,
        delay = 0.01,
        spell = regressionAnvilSpell,
    },
    {
        kind = "falling_anvil",
        owner = 1,
        cardId = "falling_anvil",
        x = 2,
        y = 2,
        remaining = 0.01,
        delay = 0.01,
        spell = regressionAnvilSpell,
    },
}
Game.update(pendingFinishState, 0.02)
assertEq(pendingFinishState.phase, "result", "Lethal delayed spell must end the match")
assertEq(#pendingFinishState.pendingSpells, 0, "Match finish must leave no pending spells")

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

local snapshotSpawnState = Game.new()
Game.debugLoadScenario(snapshotSpawnState, "empty")
Game.debugSpawnCard(snapshotSpawnState, 1, "nether_portal", 25, 100)
Game.debugSetPaused(snapshotSpawnState, false)
for _ = 1, 8 do Game.update(snapshotSpawnState, 0.25) end

local freshPiglin
for _, entity in ipairs(snapshotSpawnState.entities) do
    if entity.name == "Piglin" then freshPiglin = entity end
end
assertTrue(freshPiglin ~= nil, "Snapshot test must spawn a Piglin at two seconds")
assertEq(
    freshPiglin.remainingLifetime,
    10.0,
    "A summon created during a combat tick must not lose lifetime or act until the next tick"
)

-- Generic spawner caps must hold even when one pulse asks for multiple units.
do
local portal = cards.get("nether_portal")
local originalSpawn = require("src.util").deepcopy(portal.building.periodicSpawn)

portal.building.periodicSpawn.count = 3
portal.building.periodicSpawn.initialDelay = 0.10
portal.building.periodicSpawn.maxTotal = 2
portal.building.periodicSpawn.maxAlive = 5

local capState = Game.new()
Game.debugLoadScenario(capState, "empty")
Game.debugSpawnCard(capState, 1, "nether_portal", 50, 110)
Game.debugSetPaused(capState, false)
Game.update(capState, 0.10)

local cappedTotal = 0
for _, entity in ipairs(capState.entities) do
    if entity.name == "Piglin" then cappedTotal = cappedTotal + 1 end
end
assertEq(cappedTotal, 2, "periodicSpawn maxTotal must cap a multi-unit spawn pulse exactly")

portal.building.periodicSpawn = require("src.util").deepcopy(originalSpawn)
portal.building.periodicSpawn.count = 3
portal.building.periodicSpawn.initialDelay = 0.10
portal.building.periodicSpawn.maxTotal = nil
portal.building.periodicSpawn.maxAlive = 1

local aliveCapState = Game.new()
Game.debugLoadScenario(aliveCapState, "empty")
Game.debugSpawnCard(aliveCapState, 1, "nether_portal", 50, 110)
Game.debugSetPaused(aliveCapState, false)
Game.update(aliveCapState, 0.10)

local cappedAlive = 0
for _, entity in ipairs(aliveCapState.entities) do
    if entity.alive and entity.name == "Piglin" then cappedAlive = cappedAlive + 1 end
end
assertEq(cappedAlive, 1, "periodicSpawn maxAlive must cap a multi-unit spawn pulse exactly")

portal.building.periodicSpawn = originalSpawn
end


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

local historyState = Game.new()
historyState.players[1].deck = cards.defaultDeck()
historyState.players[2].deck = cards.defaultDeck()
Game.startCountdown(historyState)
for _ = 1, 13 do Game.update(historyState, 0.25) end

historyState.players[1].emeralds = 10
historyState.players[1].hand[1] = "zombie"
assertTrue(Game.playCardFromSlot(historyState, 1, 1, 25, 112), "History test must play Zombie")
historyState.players[1].emeralds = 10
historyState.players[1].hand[1] = "skeleton"
assertTrue(Game.playCardFromSlot(historyState, 1, 1, 30, 112), "History test must play Skeleton")
assertEq(historyState.stats.players[1].playHistory[1], "zombie", "Play history must preserve first card order")
assertEq(historyState.stats.players[1].playHistory[2], "skeleton", "Play history must preserve second card order")

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

local portalLifetimeState = Game.new()
Game.debugLoadScenario(portalLifetimeState, "empty")
Game.debugSpawnCard(portalLifetimeState, 1, "nether_portal", 25, 100)
Game.debugSetPaused(portalLifetimeState, false)

local seenPiglins = {}
for _ = 1, 100 do
    Game.update(portalLifetimeState, 0.25)
    for _, entity in ipairs(portalLifetimeState.entities) do
        if entity.name == "Piglin" then
            seenPiglins[entity.id] = true
        end
    end
end

local totalPortalPiglins = 0
for _ in pairs(seenPiglins) do totalPortalPiglins = totalPortalPiglins + 1 end
assertEq(
    totalPortalPiglins,
    3,
    "A 23-second Nether Portal must spawn exactly three Piglins instead of four"
)

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

local singleAnvilBotState = Game.new()
Game.debugLoadScenario(singleAnvilBotState, "full")
local singleAnvilBot = Bot.new(2)
Bot.setDifficulty(singleAnvilBot, "hard")
Bot.setEnabled(singleAnvilBot, singleAnvilBotState, true)
singleAnvilBotState.players[2].hand = {
    "falling_anvil",
    "iron_golem",
    "villager",
    "witch",
}
singleAnvilBotState.players[2].queue = {
    "zombie",
    "slime",
    "creeper",
    "endermite",
}
singleAnvilBotState.players[2].emeralds = 3
Game.debugSpawnCard(singleAnvilBotState, 1, "zombie", 50, 62)
Game.debugSetPaused(singleAnvilBotState, false)
singleAnvilBot.thinkTimer = 0
Bot.update(singleAnvilBot, singleAnvilBotState, 0.5)
assertEq(
    #singleAnvilBotState.pendingSpells,
    0,
    "Bot must not waste Falling Anvil on one ordinary moving target"
)

local clusterAnvilBotState = Game.new()
Game.debugLoadScenario(clusterAnvilBotState, "full")
local clusterAnvilBot = Bot.new(2)
Bot.setDifficulty(clusterAnvilBot, "hard")
Bot.setEnabled(clusterAnvilBot, clusterAnvilBotState, true)
clusterAnvilBotState.players[2].hand = {
    "falling_anvil",
    "iron_golem",
    "villager",
    "witch",
}
clusterAnvilBotState.players[2].queue = {
    "zombie",
    "slime",
    "creeper",
    "endermite",
}
clusterAnvilBotState.players[2].emeralds = 3
Game.debugSpawnCard(clusterAnvilBotState, 1, "zombie", 48, 62)
Game.debugSpawnCard(clusterAnvilBotState, 1, "zombie", 52, 62)
Game.debugSetPaused(clusterAnvilBotState, false)
clusterAnvilBot.thinkTimer = 0
Bot.update(clusterAnvilBot, clusterAnvilBotState, 0.5)
assertEq(
    #clusterAnvilBotState.pendingSpells,
    1,
    "Bot must prefer Falling Anvil when multiple predicted targets cluster"
)

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
sharedModeState.players[2].deck = cards.defaultDeck()
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
    assertTrue(type(info.goodAgainst) == "string" and #info.goodAgainst > 0, "Unit Info needs GOOD VS guidance")
    assertTrue(type(info.badAgainst) == "string" and #info.badAgainst > 0, "Unit Info needs WEAK VS guidance")
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
assertEq(infoState.players[1].infoCardId, "wolf", "Page-two first slot must expose Wolf after Evoker joins page one")
Game.handleTouch(infoState, 1, 2, 10, infoLayout)
assertEq(infoState.players[1].infoCardId, "falling_anvil", "Page-two second slot must expose Falling Anvil")
Game.handleTouch(infoState, 1, 3, 10, infoLayout)
assertEq(infoState.players[1].infoCardId, "nether_portal", "Page-two third slot must expose Nether Portal")
Game.handleTouch(infoState, 1, 4, 10, infoLayout)
assertEq(infoState.players[1].infoCardId, "wither_skeleton", "Page-two fourth slot must expose Wither Skeleton")
Game.handleTouch(infoState, 1, 5, 10, infoLayout)
assertEq(infoState.players[1].infoCardId, "magma_cube", "Page-two fifth slot must expose Magma Cube")
Game.handleTouch(infoState, 1, 6, 10, infoLayout)
assertEq(infoState.players[1].infoCardId, "pillager_outpost", "Page-two sixth slot must expose Pillager Outpost")

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
presetState.players[1].deck = cards.defaultDeck()
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

local oldFsForPreset = fs
local oldTextutilsForPreset = textutils
fs = {
    open = function() return nil end,
}
textutils = {
    serialize = function() return "{}" end,
}
local presetFailureState = Game.new()
presetFailureState.players[1].deck = cards.defaultDeck()
local oldSlot2 = presetFailureState.deckPresets[1][2]
assertTrue(
    not Game.saveDeckPreset(presetFailureState, 1, 2),
    "A real filesystem write failure must be reported instead of pretending the preset was saved"
)
assertEq(
    presetFailureState.deckPresets[1][2],
    oldSlot2,
    "Failed preset persistence must restore the previous in-memory slot"
)
fs = oldFsForPreset
textutils = oldTextutilsForPreset

-- Lane objectives must stay Clash-like: same-lane Princess first, then King.
local laneState = Game.new()
laneState.players[1].ready = true
laneState.players[2].ready = true
Game.startCountdown(laneState)
for _ = 1, 13 do Game.update(laneState, 0.25) end
assertEq(laneState.phase, "battle", "Lane objective test must enter battle")

local enemyLeftPrincess, enemyRightPrincess, enemyKing
for _, entity in ipairs(laneState.entities) do
    if entity.owner == 2 and entity.kind == "tower" then
        if entity.towerType == "king" then
            enemyKing = entity
        elseif entity.x < config.ARENA.width / 2 then
            enemyLeftPrincess = entity
        else
            enemyRightPrincess = entity
        end
    end
end
assertTrue(
    enemyLeftPrincess and enemyRightPrincess and enemyKing,
    "Lane objective test needs all three enemy Crown Towers"
)

assertTrue(
    not arena.placementAllowed(1, 25, 50, nil, laneState),
    "Enemy left lane must be locked before its Princess Tower falls"
)

laneState.players[1].hand[1] = "zombie"
laneState.players[1].emeralds = 10
assertTrue(
    Game.playCardFromSlot(laneState, 1, 1, 25, 100),
    "Lane test Zombie must deploy on the normal own half"
)

local laneZombie
for _, entity in ipairs(laneState.entities) do
    if entity.owner == 1 and entity.name == "Zombie" then
        laneZombie = entity
        break
    end
end
assertTrue(laneZombie ~= nil, "Lane objective test must spawn a Zombie")

Game.update(laneState, 0.10)
assertEq(
    laneZombie.targetId,
    enemyLeftPrincess.id,
    "A left-lane troop must target the left Princess Tower first"
)

-- Kill exactly the left Princess Tower through the real battle API so the
-- destroyed-lane deployment state is exercised too.
enemyLeftPrincess.hp = 1
laneState.players[1].hand[1] = "arrows"
laneState.players[1].emeralds = 10
assertTrue(
    Game.playCardFromSlot(
        laneState,
        1,
        1,
        enemyLeftPrincess.x,
        enemyLeftPrincess.y
    ),
    "Arrow Volley must be able to finish the lane tower in the test"
)
assertTrue(not enemyLeftPrincess.alive, "Left Princess Tower must be destroyed")
assertTrue(
    laneState.destroyedSideTowers[2].left,
    "Destroying the left Princess Tower must unlock only its lane"
)

Game.update(laneState, 0.10)
assertEq(
    laneZombie.targetId,
    enemyKing.id,
    "After its lane tower falls, a left-lane troop must target the King Tower"
)
assertTrue(
    laneZombie.targetId ~= enemyRightPrincess.id,
    "A left-lane troop must not cross-map to the opposite Princess Tower"
)

assertTrue(
    arena.placementAllowed(1, 25, 50, nil, laneState),
    "Destroyed left Princess Tower must unlock the left enemy pocket"
)
assertTrue(
    not arena.placementAllowed(1, 75, 50, nil, laneState),
    "Destroying left Princess Tower must not unlock the right enemy pocket"
)
assertTrue(
    not arena.placementAllowed(1, 50, 50, nil, laneState),
    "The centre King-Tower corridor must remain locked"
)
assertTrue(
    not arena.placementAllowed(1, 25, 20, nil, laneState),
    "Pocket deployment must not extend too far behind the old Princess Tower"
)

laneState.players[1].hand[1] = "zombie"
laneState.players[1].emeralds = 10
assertTrue(
    Game.playCardFromSlot(laneState, 1, 1, 25, 50),
    "Normal card API must allow deployment inside the unlocked lane pocket"
)

-- Pocket buildings must be punishable by Crown Towers; otherwise post-tower
-- building placement would be an exploit.
laneState.players[1].hand[1] = "cannon"
laneState.players[1].emeralds = 10
assertTrue(
    Game.playCardFromSlot(laneState, 1, 1, 44, 24),
    "A building may be placed in the unlocked pocket"
)

local pocketCannon
for _, entity in ipairs(laneState.entities) do
    if entity.owner == 1 and entity.name == "Cannon" then
        pocketCannon = entity
    end
end
assertTrue(pocketCannon ~= nil, "Pocket building test must spawn a Cannon")

Game.update(laneState, 0.10)
assertEq(
    enemyKing.targetId,
    pocketCannon.id,
    "King Tower must defend against an enemy building placed in its pocket range"
)
assertTrue(
    enemyKing.attackCooldownLeft > 0,
    "King Tower must actively shoot when an enemy is in range"
)

-- Symmetric P2 pocket rule.
local mirrorPocketState = {
    phase = "battle",
    destroyedSideTowers = {
        [1] = { left = false, right = true },
        [2] = { left = false, right = false },
    },
}
assertTrue(
    arena.placementAllowed(2, 75, 110, nil, mirrorPocketState),
    "P2 must get the symmetric right-lane pocket after destroying P1 right tower"
)
assertTrue(
    not arena.placementAllowed(2, 25, 110, nil, mirrorPocketState),
    "P2 pocket unlock must also remain lane-specific"
)

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
        assertEq(entity.attackRange, 42.5, "Princess Tower must use the bridge-exit defensive range")
        sawPrincess = true
    elseif entity.kind == "tower" and entity.towerType == "king" then
        assertEq(entity.maxHp, 2565, "King Tower must use five-percent HP nerf")
        assertEq(entity.damage, 105, "King Tower must remain an active attacking tower")
        assertEq(entity.attackRange, 27, "King Tower range must remain unchanged")
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

-- Evolution framework: only explicitly evolved cards may occupy the extra
-- slot. Timing, evolved Emerald cost, stats and existing engine abilities are
-- all configured per card.
do
local zombieEvolutionBefore = cards.get("zombie").evolution
cards.get("zombie").evolution = {
    cycles = 3, -- three normal plays, fourth play evolves
    cost = { delta = 1 }, -- 3E base -> 4E evolved play
    name = "Evolved Zombie",
    statMultipliers = {
        maxHp = 1.10,
        damage = 1.50,
    },
    abilities = {
        canAttackAir = true,
        onHitSlow = {
            factor = 0.75,
            duration = 2.0,
        },
    },
}

assertTrue(cards.hasEvolution("zombie"), "Synthetic Zombie evolution must be discoverable")
assertEq(cards.evolutionCycles("zombie"), 3, "Evolution timing must be configurable per card")
assertEq(cards.evolutionPlayNumber("zombie"), 4, "Three charge plays must make the fourth play evolve")
assertEq(cards.evolutionCost("zombie"), 4, "Evolution Emerald cost delta must be applied")
assertEq(
    cards.evolutionCycles({ evolution = { cycles = 0 } }),
    0,
    "Zero-cycle evolution must be supported for cards that evolve every play"
)
assertTrue(not cards.hasEvolution("skeleton"), "Cards without definitions must not be evolution eligible")

local evolvedCopy = cards.evolvedCopy("zombie")
assertTrue(evolvedCopy ~= nil and evolvedCopy.isEvolution, "Evolution must create an evolved card copy")
assertEq(evolvedCopy.unit.damage, 120, "Evolution stat multipliers must apply to unit damage")
assertTrue(math.abs(evolvedCopy.unit.maxHp - 575.3) < 0.000001, "Evolution HP multiplier must apply exactly")
assertTrue(evolvedCopy.unit.canAttackAir, "Evolution abilities must be able to add air targeting")
assertTrue(evolvedCopy.unit.onHitSlow ~= nil, "Evolution abilities must be deep-merged into unit data")
assertEq(evolvedCopy.unit.onHitSlow.factor, 0.75, "Evolution ability data must preserve configured values")
assertEq(evolvedCopy.unit.onHitSlow.duration, 2.0, "Evolution ability duration must be configurable")

local evoState = Game.new()
evoState.players[1].deck = cards.defaultDeck()
evoState.players[2].deck = cards.defaultDeck()

assertTrue(
    not Game.setEvolutionCard(evoState, 1, "skeleton"),
    "A card without an evolution must be rejected by the Evolution Slot"
)
assertTrue(
    Game.setEvolutionCard(evoState, 1, "zombie"),
    "An eligible card already in deck must enter the Evolution Slot"
)
assertEq(evoState.players[1].evolutionCardId, "zombie", "Evolution Slot must duplicate the deck card, not remove it")

Game.startCountdown(evoState)
for _ = 1, 13 do Game.update(evoState, 0.25) end
assertEq(evoState.phase, "battle", "Evolution cycle test must enter battle")
assertEq(evoState.players[1].evolutionCardId, "zombie", "Valid Evolution Slot selection must survive match reset")
assertEq(evoState.players[1].evolutionProgress, 0, "Evolution progress must start at zero")

local function newestSourceEntity(state, owner, cardId)
    local newest = nil
    for _, entity in ipairs(state.entities) do
        if entity.owner == owner and entity.sourceCardId == cardId then
            if not newest or entity.id > newest.id then newest = entity end
        end
    end
    return newest
end

for playIndex = 1, 3 do
    evoState.players[1].hand[1] = "zombie"
    evoState.players[1].emeralds = 10

    assertTrue(
        Game.playCardFromSlot(evoState, 1, 1, 25, 112),
        "Evolution charge play " .. tostring(playIndex) .. " must succeed"
    )

    local spawned = newestSourceEntity(evoState, 1, "zombie")
    assertTrue(spawned ~= nil, "Evolution charge play must spawn the source card")
    assertTrue(spawned.isEvolution ~= true, "Configured charge plays must remain normal")
    assertEq(spawned.damage, 80, "Normal charge plays must retain base stats")
    assertEq(evoState.players[1].emeralds, 7, "Normal charge play must spend the base 3E cost")
    assertEq(
        evoState.players[1].evolutionProgress,
        playIndex,
        "Normal evolution play must advance the configured charge counter"
    )
end

-- A ready evolution with a higher configured cost must not deploy or consume
-- its charge until the player can actually afford the evolved card.
evoState.players[1].hand[1] = "zombie"
evoState.players[1].emeralds = 3
local rejectedForCost = not Game.playCardFromSlot(evoState, 1, 1, 25, 112)
assertTrue(rejectedForCost, "Ready 4E evolution must reject a player holding only 3E")
assertEq(evoState.players[1].evolutionProgress, 3, "Failed evolved play must not consume evolution charge")
assertEq(evoState.players[1].emeralds, 3, "Failed evolved play must not spend Emeralds")

evoState.players[1].hand[1] = "zombie"
evoState.players[1].emeralds = 10
assertTrue(
    Game.playCardFromSlot(evoState, 1, 1, 25, 112),
    "Configured fourth-play evolution must succeed with enough Emeralds"
)

local evolvedEntity = newestSourceEntity(evoState, 1, "zombie")
assertTrue(evolvedEntity ~= nil and evolvedEntity.isEvolution == true, "Fourth play must deploy the evolution")
assertEq(evolvedEntity.name, "Evolved Zombie", "Evolved entity must use evolution display name")
assertEq(evolvedEntity.damage, 120, "Evolved play must use configured stat multipliers")
assertTrue(evolvedEntity.canAttackAir, "Evolved entity must receive configured ability flags")
assertEq(evolvedEntity.onHitSlow.factor, 0.75, "Evolved entity must receive configured ability data")
assertEq(evoState.players[1].emeralds, 6, "Evolved play must deduct its configured 4E cost")
assertEq(evoState.players[1].evolutionProgress, 0, "Evolution use must reset the counter")
assertEq(evoState.stats.players[1].evolutionPlays, 1, "Evolution telemetry must count evolved plays")
assertEq(evoState.stats.players[1].cards.zombie.evolutionPlays, 1, "Card telemetry must attribute evolved play")
assertEq(evoState.stats.players[1].cards.zombie.emeraldSpent, 13, "Telemetry must count 3+3+3+4 evolved Emerald spending")

local lobbyClearState = Game.new()
lobbyClearState.players[1].deck = cards.defaultDeck()
assertTrue(Game.setEvolutionCard(lobbyClearState, 1, "zombie"), "Evolution clear test must select Zombie")
assertTrue(Game.toggleDeckCard(lobbyClearState, 1, "zombie"), "Removing selected evolution card must still remove deck card")
assertEq(lobbyClearState.players[1].evolutionCardId, nil, "Removing the deck card must clear the Evolution Slot")

cards.get("zombie").evolution = zombieEvolutionBefore
end

-- First real Evolution set.
do
local creeperEvo = cards.evolvedCopy("creeper")
assertTrue(creeperEvo ~= nil, "Creeper must expose a real Evolution")
assertEq(cards.evolutionCycles("creeper"), 2, "Charged Creeper must evolve on the third play")
assertEq(cards.evolutionCost("creeper"), 4, "Charged Creeper must keep the base 4E cost")
assertEq(creeperEvo.name, "Charged Creeper", "Creeper Evolution must use Charged Creeper form")
assertEq(creeperEvo.unit.visualVariant, "charged_creeper", "Charged Creeper needs its blue visual variant")
assertEq(creeperEvo.unit.proximityExplosion.radius, 12, "Charged Creeper gameplay blast must be larger")
assertEq(creeperEvo.unit.proximityExplosion.damage, 580, "Charged Creeper blast damage must be exactly double the base Creeper")
assertEq(creeperEvo.unit.proximityExplosion.effectKind, "charged_explosion", "Charged Creeper must use the enhanced explosion effect")
assertTrue(
    creeperEvo.unit.proximityExplosion.visualRadius > creeperEvo.unit.proximityExplosion.radius,
    "Charged Creeper visual explosion must read larger than its gameplay AoE"
)

local portalEvo = cards.evolvedCopy("nether_portal")
assertTrue(portalEvo ~= nil, "Nether Portal must expose a real Evolution")
assertEq(cards.evolutionCycles("nether_portal"), 2, "Ghast Portal must evolve on the third play")
assertEq(cards.evolutionCost("nether_portal"), 3, "Ghast Portal must keep the base 3E cost")
assertEq(portalEvo.name, "Ghast Portal", "Nether Portal Evolution must use Ghast Portal form")
assertEq(portalEvo.building.visualVariant, "ghast_portal", "Ghast Portal needs the turquoise visual variant")
assertEq(portalEvo.building.periodicSpawn.template, "ghast", "Ghast Portal must summon Ghasts")
assertEq(portalEvo.building.periodicSpawn.maxTotal, 2, "Ghast Portal must summon exactly two Ghasts total")

local ghast = cards.getInternalUnit("ghast")
assertTrue(ghast ~= nil and ghast.flying, "Ghast must be a flying internal unit")
assertEq(ghast.damage, 130, "Ghast must deal 130 damage per artillery shot")
assertTrue(ghast.damage < cards.get("blaze").unit.maxHp, "Ghast must not one-shot a full-health Blaze")
assertTrue(ghast.damage * 2 >= cards.get("blaze").unit.maxHp, "Ghast must two-shot a full-health Blaze")
assertTrue(ghast.attackRange >= 24, "Ghast must have long artillery range")
assertTrue(ghast.attackCooldown >= 2.8, "Ghast must fire slowly like fragile artillery")
assertTrue(ghast.maxHp < cards.get("blaze").unit.maxHp, "Ghast must remain more fragile than Blaze")
assertTrue(ghast.projectileSplashRadius > 0, "Ghast fireball must deal splash damage")
assertTrue(ghast.projectileSlowPrimaryOnly, "Ghast slow must apply only to the primary target")
assertTrue(ghast.onHitSlow ~= nil, "Ghast primary hit must apply a slow")

local miteEvo = cards.evolvedCopy("endermite")
assertTrue(miteEvo ~= nil, "Endermite must expose a real Evolution")
assertEq(cards.evolutionCycles("endermite"), 4, "Mega Mite must evolve on the fifth play")
assertEq(cards.evolutionCost("endermite"), 1, "Mega Mite must keep the base 1E cost")
assertEq(miteEvo.name, "Mega Mite", "Endermite Evolution must use Mega Mite form")
assertEq(miteEvo.unit.maxHp, cards.get("endermite").unit.maxHp * 5, "Mega Mite must have exactly five times Endermite HP")
assertEq(miteEvo.unit.damage, cards.get("endermite").unit.damage, "Mega Mite damage must stay unchanged")
assertEq(miteEvo.unit.moveSpeed, cards.get("endermite").unit.moveSpeed, "Mega Mite movement speed must stay unchanged")
assertEq(miteEvo.unit.attackCooldown, cards.get("endermite").unit.attackCooldown, "Mega Mite attack speed must stay unchanged")
assertEq(miteEvo.unit.visualVariant, "mega_mite", "Mega Mite needs its larger visual variant")
end

-- Simulation/Bot Evolution integration: simulation entry points use Bot.prepare,
-- so the bot must actually occupy the single Evolution Slot when its deck
-- contains eligible cards.
do
local simState = Game.new()
local simDeck = {
    "zombie",
    "skeleton",
    "creeper",
    "nether_portal",
    "endermite",
    "cannon",
    "arrows",
    "wolf",
}
local simBot = Bot.new(1, simDeck)
Bot.prepare(simBot, simState)

assertTrue(
    cards.hasEvolution(simState.players[1].evolutionCardId),
    "Bot.prepare must select an eligible Evolution card for normal simulations"
)

local reorderedDeck = {
    "zombie",
    "skeleton",
    "nether_portal",
    "creeper",
    "endermite",
    "cannon",
    "arrows",
    "wolf",
}
local reorderedState = Game.new()
local reorderedBot = Bot.new(1, reorderedDeck)
Bot.prepare(reorderedBot, reorderedState)
assertEq(
    reorderedState.players[1].evolutionCardId,
    simState.players[1].evolutionCardId,
    "Bot Evolution choice must be strategic and independent of deck ordering"
)
assertEq(
    simState.players[1].evolutionProgress,
    0,
    "Simulation Evolution charge must start at zero"
)
end

-- Shared match Ruleset: Evolutions can be disabled without losing the saved
-- Evolution Slot selection. While disabled, no charge, evolved cost or evolved
-- form may leak into gameplay.
do
local rulesState = Game.new()
assertTrue(Game.rulesetEnabled(rulesState, "evolutions"), "Evolutions must default ON")

rulesState.players[1].deck = {
    "zombie",
    "skeleton",
    "iron_golem",
    "bat_swarm",
    "cannon",
    "arrows",
    "creeper",
    "endermite",
}
rulesState.players[2].deck = cards.defaultDeck()

assertTrue(Game.setEvolutionCard(rulesState, 1, "creeper"), "Ruleset test must save Creeper in the Evolution Slot")
rulesState.players[1].ready = true
rulesState.players[2].ready = true

assertTrue(
    Game.setRulesetRule(rulesState, "evolutions", false, 1),
    "Lobby must allow Evolutions to be disabled"
)
assertTrue(not Game.rulesetEnabled(rulesState, "evolutions"), "Ruleset must report Evolutions OFF")
assertTrue(
    not rulesState.players[1].ready and not rulesState.players[2].ready,
    "Changing a shared Ruleset option must unready both players"
)
assertEq(
    rulesState.players[1].evolutionCardId,
    "creeper",
    "Disabling Evolutions must preserve the saved Evolution Slot card"
)
assertEq(rulesState.players[1].evolutionProgress, 0, "Disabling Evolutions must reset its charge")

rulesState.players[1].ready = true
rulesState.players[2].ready = true
Game.startCountdown(rulesState)
for _ = 1, 13 do Game.update(rulesState, 0.25) end
assertEq(rulesState.phase, "battle", "Ruleset Evolution test must enter battle")

rulesState.players[1].evolutionProgress = 2
rulesState.players[1].hand[1] = "creeper"
rulesState.players[1].emeralds = 10

local offCost = Game.getCardPlayCost(rulesState, 1, "creeper")
assertEq(offCost, cards.get("creeper").cost, "Evolution OFF must always expose base Emerald cost")
assertTrue(
    Game.playCardFromSlot(rulesState, 1, 1, 25, 112),
    "Base Creeper must still play while Evolutions are disabled"
)

local spawnedBaseCreeper
for _, entity in ipairs(rulesState.entities) do
    if entity.owner == 1 and entity.sourceCardId == "creeper" then
        if not spawnedBaseCreeper or entity.id > spawnedBaseCreeper.id then
            spawnedBaseCreeper = entity
        end
    end
end

assertTrue(spawnedBaseCreeper ~= nil, "Evolution OFF test must spawn Creeper")
assertEq(spawnedBaseCreeper.name, "Creeper", "Evolution OFF must spawn the base form")
assertTrue(spawnedBaseCreeper.isEvolution ~= true, "Evolution OFF must never mark the entity evolved")
assertEq(
    rulesState.players[1].evolutionProgress,
    2,
    "Evolution OFF must not charge or consume the saved Evolution counter during battle"
)
assertEq(
    rulesState.stats.players[1].evolutionPlays,
    0,
    "Evolution OFF must record zero evolved plays"
)
end

-- Admin spawn catalog exposes base cards plus direct Evolution forms. These
-- bypass charge/cost because the sandbox is for isolated mechanic testing.
do
local adminCatalog = cards.adminSpawnCards()
assertEq(
    #adminCatalog,
    #cards.all + #cards.evolutionCards(true),
    "Admin spawn catalog must include production and dev-only base/Evolution forms"
)
assertEq(#cards.evolutionCards(), 5, "Normal Evolution selection must expose five production Evolutions")
assertEq(#cards.evolutionCards(true), 6, "Dev/admin Evolution registry must retain Elder Guardian")

local adminKeys = {}
for _, entry in ipairs(adminCatalog) do
    adminKeys[entry.key] = entry
end

assertTrue(adminKeys["evo:creeper"] ~= nil, "Admin catalog must expose Charged Creeper")
assertTrue(adminKeys["evo:nether_portal"] ~= nil, "Admin catalog must expose Ghast Portal")
assertTrue(adminKeys["evo:endermite"] ~= nil, "Admin catalog must expose Mega Mite")

local adminEvoState = Game.new()
Game.debugLoadScenario(adminEvoState, "empty")

assertTrue(
    Game.debugSpawnCard(adminEvoState, 1, "evo:creeper", 30, 110),
    "Admin must directly spawn Charged Creeper"
)
assertTrue(
    Game.debugSpawnCard(adminEvoState, 1, "evo:nether_portal", 50, 110),
    "Admin must directly spawn Ghast Portal"
)
assertTrue(
    Game.debugSpawnCard(adminEvoState, 1, "evo:endermite", 70, 110),
    "Admin must directly spawn Mega Mite"
)
assertTrue(
    Game.debugSpawnCard(adminEvoState, 1, "evo:guardian", 50, 80),
    "Admin must directly spawn Elder Guardian"
)
assertTrue(
    Game.debugSpawnCard(adminEvoState, 1, "evo:villager", 80, 110),
    "Admin must directly spawn Emerald Bank"
)
assertTrue(
    Game.debugSpawnCard(adminEvoState, 1, "evo:iron_golem", 35, 110),
    "Admin must directly spawn Diamond Golem"
)

local foundCharged, foundPortal, foundMega = false, false, false
local foundElder, foundBank, foundDiamond = false, false, false
for _, entity in ipairs(adminEvoState.entities) do
    if entity.name == "Charged Creeper" and entity.isEvolution then foundCharged = true end
    if entity.name == "Ghast Portal" and entity.isEvolution then foundPortal = true end
    if entity.name == "Mega Mite" and entity.isEvolution then foundMega = true end
    if entity.name == "Elder Guardian" and entity.isEvolution then foundElder = true end
    if entity.name == "Emerald Bank" and entity.isEvolution then foundBank = true end
    if entity.name == "Diamond Golem" and entity.isEvolution then foundDiamond = true end
end
assertTrue(foundCharged, "Direct admin spawn must create evolved Charged Creeper entity")
assertTrue(foundPortal, "Direct admin spawn must create evolved Ghast Portal entity")
assertTrue(foundMega, "Direct admin spawn must create evolved Mega Mite entity")
assertTrue(foundElder, "Direct admin spawn must create evolved Elder Guardian entity")
assertTrue(foundBank, "Direct admin spawn must create evolved Emerald Bank entity")
assertTrue(foundDiamond, "Direct admin spawn must create evolved Diamond Golem entity")

assertTrue(type(adminRender.draw) == "function", "Admin renderer with Evolution catalog must load")
end

-- Water-only admin placement and combat targetability. Ground units should not
-- aggro a Guardian they can never bring inside attack range, while ranged
-- units that can actually reach it should still target it.
do
local waterAdmin = Game.new()
Game.debugLoadScenario(waterAdmin, "empty")
Game.debugSetPaused(waterAdmin, false)
local riverY = (config.ARENA.riverTop + config.ARENA.riverBottom) / 2

local landOk, landReason = Game.debugSpawnCard(waterAdmin, 1, "guardian", 50, 110)
assertTrue(not landOk, "Admin must reject Guardian spawning on land")
assertEq(landReason, "WATER ONLY - PLACE IN OPEN RIVER", "Admin land rejection should explain water-only placement")

local bridgeOk = Game.debugSpawnCard(
    waterAdmin,
    1,
    "evo:guardian",
    config.ARENA.bridgeCenters[1],
    riverY
)
assertTrue(not bridgeOk, "Admin must reject Elder Guardian spawning on a bridge")

local waterOk = Game.debugSpawnCard(waterAdmin, 1, "guardian", 50, riverY)
assertTrue(waterOk, "Admin must allow Guardian spawning in open river water")

local guardian
for _, entity in ipairs(waterAdmin.entities) do
    if entity.name == "Guardian" then guardian = entity end
end
assertTrue(guardian ~= nil, "Water placement test must create Guardian")
guardian.passive = true
guardian.targetMode = "none"

assertTrue(
    Game.debugSpawnCard(waterAdmin, 2, "zombie", 50, config.ARENA.riverTop - 6),
    "Targetability test must spawn Zombie"
)
Game.update(waterAdmin, 0.10)

local zombie
for _, entity in ipairs(waterAdmin.entities) do
    if entity.owner == 2 and entity.name == "Zombie" then zombie = entity end
end
assertTrue(zombie ~= nil, "Targetability test must find Zombie")
assertTrue(
    zombie.targetId == nil,
    "Ground melee Zombie must ignore a mid-river Guardian it cannot reach"
)

assertTrue(
    Game.debugSpawnCard(waterAdmin, 2, "skeleton", 50, config.ARENA.riverTop - 6),
    "Targetability test must spawn Skeleton"
)
Game.update(waterAdmin, 0.10)

local skeleton
for _, entity in ipairs(waterAdmin.entities) do
    if entity.owner == 2 and entity.name == "Skeleton" then skeleton = entity end
end
assertTrue(skeleton ~= nil, "Targetability test must find Skeleton")
assertEq(
    skeleton.targetId,
    guardian.id,
    "Ranged Skeleton must still target a Guardian it can actually reach"
)
end

assertEq(#musicManifest.tracks, 34, "Battle music playlist must expose 34 shuffled tracks")
assertEq(musicManifest.sourceRate, 48000, "Battle music pack must use native 48 kHz DFPWM")
assertEq(musicManifest.outputRate, 48000, "Speaker output must stay at native 48 kHz")
assertEq(musicManifest.repeatFactor, 1, "Native 48 kHz music must not duplicate samples")
assertEq(musicManifest.chunkBytes, 16384, "Music chunks should fill the speaker buffer efficiently")

assertEq(#musicManifest.packs, 2, "HQ battle music must be split into two GitHub-safe packs")
assertTrue(musicManifest.packs[1].size < 25000000, "Music pack 1 must stay below GitHub's 25 MB web limit")
assertTrue(musicManifest.packs[2].size < 25000000, "Music pack 2 must stay below GitHub's 25 MB web limit")

-- Unit Info must fit useful mechanics on the real 57x52 target monitor.
do
local oldToBlit = colors.toBlit
colors.toBlit = function() return "0" end

local function renderInfoCard(cardId)
    local rows = {}
    local cursorY = 1
    local monitor = {
        getSize = function() return 57, 52 end,
        setCursorPos = function(_, y) cursorY = y end,
        blit = function(chars)
            rows[cursorY] = chars
        end,
    }

    local infoState = Game.new()
    infoState.players[1].infoOpen = true
    infoState.players[1].infoCardId = cardId
    render.draw(monitor, infoState, 1, "test_monitor")
    return table.concat(rows, "\n")
end

local guardianInfoScreen = renderInfoCard("guardian")
assertTrue(
    guardianInfoScreen:find("GOOD VS:", 1, true) ~= nil
        and guardianInfoScreen:find("Iron Golem", 1, true) ~= nil,
    "Guardian Unit Info must show tactical GOOD VS guidance"
)
assertTrue(
    guardianInfoScreen:find("WEAK VS:", 1, true) ~= nil
        and guardianInfoScreen:find("Skeleton", 1, true) ~= nil,
    "Guardian Unit Info must show tactical WEAK VS guidance"
)
assertTrue(
    guardianInfoScreen:find("EVO: Elder Guardian | PLAY 3 | 6E", 1, true) ~= nil,
    "Guardian Unit Info must show Elder Guardian timing and cost"
)
assertTrue(
    guardianInfoScreen:find("2x HP and slows all enemy movement by 5%", 1, true) ~= nil,
    "Guardian Unit Info must show the Elder Guardian description"
)

local portalInfoScreen = renderInfoCard("nether_portal")
assertTrue(
    portalInfoScreen:find("SPAWN LIMIT BY LIFETIME: 3", 1, true) ~= nil,
    "Nether Portal info must visibly show the real three-Piglin lifetime limit"
)
assertTrue(
    portalInfoScreen:find("PIGLIN AIR: CROSSBOW 28", 1, true) ~= nil,
    "Nether Portal info must visibly explain the Piglin air weapon"
)
assertTrue(
    portalInfoScreen:find("DMG 0", 1, true) == nil,
    "Passive Nether Portal info must not waste space on meaningless zero damage"
)

local villagerInfoScreen = renderInfoCard("villager")
assertTrue(
    villagerInfoScreen:find("ECONOMY: +62% Emerald generation while alive", 1, true) ~= nil,
    "Villager info must visibly show its Emerald-generation mechanic"
)
assertTrue(
    villagerInfoScreen:find("DMG 0", 1, true) == nil,
    "Villager info must not waste space on meaningless zero damage"
)

local creeperInfoScreen = renderInfoCard("creeper")
assertTrue(
    creeperInfoScreen:find("BLAST 290 dmg", 1, true) ~= nil,
    "Creeper info must visibly show explosion damage instead of generic zero DPS"
)
assertTrue(
    creeperInfoScreen:find("DPS 0", 1, true) == nil,
    "Creeper info must not show misleading zero DPS"
)

local outpostInfoScreen = renderInfoCard("pillager_outpost")
assertTrue(
    outpostInfoScreen:find("TARGETS AIR + GROUND", 1, true) ~= nil,
    "Pillager Outpost info must visibly show air and ground targeting"
)
assertTrue(
    outpostInfoScreen:find("HP DECAY", 1, true) ~= nil
        and outpostInfoScreen:find("NATURAL LIFE", 1, true) ~= nil,
    "Building info must show the accelerated HP decay and effective natural life"
)

local magmaInfoScreen = renderInfoCard("magma_cube")
assertTrue(
    magmaInfoScreen:find("ON DEATH: splits into 2x Mini Magma Cube", 1, true) ~= nil,
    "Magma Cube info must visibly show its own Mini Magma Cube split"
)

local function renderLobbyState(lobbyState)
    local rows = {}
    local cursorY = 1
    local monitor = {
        getSize = function() return 57, 52 end,
        setCursorPos = function(_, y) cursorY = y end,
        blit = function(chars)
            rows[cursorY] = chars
        end,
    }
    render.draw(monitor, lobbyState, 1, "test_monitor")
    return table.concat(rows, "\n")
end

local lobbyScreen = renderLobbyState(Game.new())
assertTrue(
    lobbyScreen:find("EVOLUTION SLOT", 1, true) ~= nil,
    "Lobby must visibly expose the Evolution Slot below the eight deck slots"
)
assertTrue(
    lobbyScreen:find("RANDOM 8", 1, true) ~= nil,
    "Random deck action should remain visible beside the Evolution Slot"
)
assertTrue(
    lobbyScreen:find("RULESET: EVO ON", 1, true) ~= nil,
    "Lobby must visibly expose the shared Ruleset button"
)
assertTrue(
    lobbyScreen:find("EVO > SLOT 1", 1, true) == nil,
    "Empty deck slots must never be mistaken for the selected Evolution slot"
)
assertTrue(
    lobbyScreen:find("E-CARDS ARE MARKED WITH E", 1, true) == nil,
    "Lobby must not use legacy single-letter Evolution instructions"
)

local rulesetRenderState = Game.new()
rulesetRenderState.players[1].rulesetOpen = true
local rulesetScreen = renderLobbyState(rulesetRenderState)
assertTrue(
    rulesetScreen:find("MATCH RULESET", 1, true) ~= nil
        and rulesetScreen:find("EVOLUTIONS: ON", 1, true) ~= nil,
    "Ruleset screen must visibly expose the Evolution ON/OFF rule"
)

Game.setRulesetRule(rulesetRenderState, "evolutions", false, 1)
rulesetScreen = renderLobbyState(rulesetRenderState)
assertTrue(
    rulesetScreen:find("EVOLUTIONS: OFF", 1, true) ~= nil,
    "Ruleset screen must visibly reflect Evolutions OFF"
)
assertTrue(
    lobbyScreen:find("PRESET", 1, true) == nil
        and lobbyScreen:find("SAVE", 1, true) == nil
        and lobbyScreen:find("LOAD", 1, true) == nil,
    "Preset/loadout controls must remain hidden from the normal lobby GUI"
)

colors.toBlit = oldToBlit
end

print("Smoke tests passed")

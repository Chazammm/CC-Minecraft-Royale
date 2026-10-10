-- End-to-end guards for the October 2026 installer/combat audit.
-- Kept separate to avoid Lua's per-chunk local-variable limit.
colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768,
}
package.path = "./?.lua;./?/init.lua;" .. package.path

local Game = require("src.game")
local cards = require("src.cards")

local function assertEq(actual, expected, message)
    if actual ~= expected then
        error((message or "assertEq failed") ..
            ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function assertTrue(value, message)
    if not value then error(message or "assertTrue failed") end
end

local function findOwned(state, owner, index)
    local found = 0
    for _, entity in ipairs(state.entities) do
        if entity.alive and entity.owner == owner then
            found = found + 1
            if found == index then return entity end
        end
    end
    return nil
end

-- Valid ordinary 8-card decks remain untouched, but hidden/sparse slots
-- and non-array metadata cannot enter a preset or a real match.
do
    local deck = cards.defaultDeck()
    assertTrue(cards.isValidDeck(deck), "Standard deck is valid")

    local withExtra = cards.defaultDeck()
    withExtra[9] = "evoker"
    assertTrue(not cards.isValidDeck(withExtra), "Extra ninth slot rejected")

    local withMetadata = cards.defaultDeck()
    withMetadata.metadata = "corrupt"
    assertTrue(not cards.isValidDeck(withMetadata), "Unexpected key rejected")

    local withHole = cards.defaultDeck()
    withHole[4] = nil
    withHole[9] = "evoker"
    assertTrue(not cards.isValidDeck(withHole), "Sparse/oversized deck rejected")
end

-- Until the first attack, nearby distractions must also pull a troop which
-- was already marching toward ANOTHER troop (not only toward a tower).
do
    local state = Game.new(nil, { headlessSimulation = true })
    Game.debugLoadScenario(state, "empty")
    assertTrue(Game.debugSpawnCard(state, 1, "zombie", 25, 110))
    assertTrue(Game.debugSpawnCard(state, 2, "zombie", 25, 99))
    local attacker = findOwned(state, 1, 1)
    local farEnemy = findOwned(state, 2, 1)

    Game.debugSetPaused(state, false)
    Game.update(state, 0.05)
    assertEq(attacker.targetId, farEnemy.id, "Initial enemy acquired")
    assertEq(attacker.lockedTargetId, nil, "Still approaching, not locked")

    assertTrue(Game.debugSpawnCard(state, 2, "zombie", 25, 105))
    local nearEnemy = findOwned(state, 2, 2)
    Game.update(state, 0.05)

    assertEq(attacker.targetId, nearEnemy.id, "Closer troop can pull before attack")
    assertEq(attacker.lockedTargetId, nil, "Approach still unlocked")
end

-- Once the initial shot/attack committed, lock on the same live target even
-- after a closer distraction is spawned.
do
    local state = Game.new(nil, { headlessSimulation = true })
    Game.debugLoadScenario(state, "empty")
    assertTrue(Game.debugSpawnCard(state, 1, "skeleton", 25, 110))
    assertTrue(Game.debugSpawnCard(state, 2, "zombie", 25, 103))
    local attacker = findOwned(state, 1, 1)
    local first = findOwned(state, 2, 1)

    Game.debugSetPaused(state, false)
    Game.update(state, 0.05)
    assertEq(attacker.lockedTargetId, first.id, "First attack locks target")

    assertTrue(Game.debugSpawnCard(state, 2, "zombie", 25, 109))
    Game.update(state, 0.05)
    assertEq(attacker.targetId, first.id, "New spawn cannot break committed lock")
end

-- AoE projectiles should land at the last live target coordinates when the
-- original target dies in flight. This is a behavioral change for AoE ONLY.
do
    local state = Game.new(nil, { headlessSimulation = true })
    Game.debugLoadScenario(state, "empty")
    assertTrue(Game.debugSpawnCard(state, 2, "zombie", 65, 110))
    assertTrue(Game.debugSpawnCard(state, 2, "zombie", 67, 110))
    local original = findOwned(state, 2, 1)
    local bystander = findOwned(state, 2, 2)
    local hpBefore = bystander.hp
    assertTrue(Game.debugKillEntity(state, original.id))

    state.projectiles[#state.projectiles + 1] = {
        x = 60, y = 110, targetId = original.id,
        lastTargetX = 65, lastTargetY = 110,
        owner = 1, damage = 47, speed = 100,
        splashRadius = 5, alive = true,
    }

    Game.debugSetPaused(state, false)
    Game.update(state, 0.10)
    assertEq(hpBefore - bystander.hp, 47, "Splash survives target death")
    assertEq(#state.projectiles, 0, "Resolved splash projectile cleaned up")
end

-- Installer marker must be observed before either launcher loads the engine,
-- and installer snapshots must complete before the marker/application phase.
do
    local function read(path)
        local handle = assert(io.open(path, "r"))
        local text = handle:read("*a")
        handle:close()
        return text
    end

    local startup = read("startup.lua")
    local main = read("main.lua")
    local admin = read("admin.lua")
    local installer = read("install.lua")

    local startupGuard = assert(startup:find('fs.exists(".cc_royale_installing")', 1, true))
    local startupLaunch = assert(startup:find('shell.run("main.lua")', 1, true))
    assertTrue(startupGuard < startupLaunch, "Startup guards incomplete installs")

    local mainGuard = assert(main:find('fs.exists(".cc_royale_installing")', 1, true))
    local adminGuard = assert(admin:find('fs.exists(".cc_royale_installing")', 1, true))
    assertTrue(mainGuard < assert(main:find('require("config")', 1, true)),
        "Main entrypoint guards before require")
    assertTrue(adminGuard < assert(admin:find('require("config")', 1, true)),
        "Admin entrypoint guards before require")

    local snapshots = assert(installer:find("local snapshot = {}", 1, true))
    local verifiedRead = assert(installer:find("Cannot snapshot managed file ", snapshots, true))
    local marker = assert(installer:find("local markerOk, markerErr = writeFile(INSTALL_MARKER", 1, true))
    local apply = assert(installer:find("local applyOk, applyErr = pcall(function()", 1, true))
    assertTrue(snapshots < verifiedRead and verifiedRead < marker and marker < apply,
        "Installer snapshots precede destructive updates")
end

-- The accelerated Arrow evaluator must choose exactly the same position and
-- score as the old all-pairs scan. Check several tactical layouts for BOTH
-- sides, including overlapping clusters and symmetric/tied priorities.
do
    local Bot = require("src.bot")
    local arrow = cards.get("arrows")
    local radiusSq = arrow.spell.radius * arrow.spell.radius

    local function legacyArrowTarget(state, playerId)
        local opponents, towers = {}, {}
        for _, entity in ipairs(state.entities) do
            if entity.alive and entity.owner ~= playerId then
                if entity.kind == "tower" then
                    towers[#towers + 1] = entity
                else
                    opponents[#opponents + 1] = entity
                end
            end
        end

        local best, bestScore = nil, 0
        for _, center in ipairs(opponents) do
            local score = 0
            for _, target in ipairs(opponents) do
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
                best, bestScore = center, score
            end
        end

        local towerDamage = (arrow.spell.damage or 0)
            * (arrow.spell.towerMultiplier or 1)
        for _, tower in ipairs(towers) do
            if towerDamage > 0 and tower.hp <= towerDamage + 0.001 then
                local score = tower.towerType == "king" and 80 or 35
                if state.overtime then score = score + 25 end
                if score > bestScore then
                    best, bestScore = tower, score
                end
            end
        end

        if best then return best.x, best.y, bestScore end
        return nil, nil, bestScore
    end

    for scenario = 1, 3 do
        local state = Game.new(nil, { headlessSimulation = true })
        Game.debugLoadScenario(state, "full")
        for i = 1, 14 do
            local owner = i % 2 + 1
            local cardId = i % 7 == 0 and "villager"
                or (i % 4 == 0 and "endermite" or "zombie")
            local x = scenario == 1 and (9 + i * 5)
                or (scenario == 2 and 50 + (i % 5) * 1.7
                    or 25 + (i % 4) * 8)
            local y = scenario == 1 and (30 + i * 7)
                or (scenario == 2 and 98 + (i % 3) * 2
                    or 105 + (i % 6) * 5)
            assertTrue(Game.debugSpawnCard(state, owner, cardId, x, y))
        end

        for playerId = 1, 2 do
            local ax, ay, ascore = Bot.debugArrowTarget(state, playerId)
            local ex, ey, escore = legacyArrowTarget(state, playerId)
            assertEq(ax, ex, "Arrow X parity scenario " .. scenario)
            assertEq(ay, ey, "Arrow Y parity scenario " .. scenario)
            assertEq(ascore, escore, "Arrow score parity scenario " .. scenario)
        end
    end
end

-- PixelBox still computes every pixel, but an unchanged second frame must not
-- transmit any additional monitor rows. Phase changes invalidate that cache.
do
    local pixelArena = require("src.pixel_arena")
    local previousWindow = window
    local blits = 0

    window = {
        create = function(_, _, _, width, height)
            return {
                getSize = function() return width, height end,
                getBackgroundColor = function() return colors.black end,
                setBackgroundColor = function() end,
                clear = function() end,
                setCursorPos = function() end,
                blit = function() blits = blits + 1 end,
            }
        end,
    }

    local monitor = {}
    local rect = { x1 = 1, y1 = 3, x2 = 48, y2 = 38 }
    local state = Game.new(nil, { headlessSimulation = true })
    Game.debugLoadScenario(state, "empty")

    pixelArena.draw(monitor, state, 1, rect)
    local first = blits
    assertTrue(first > 0, "First arena frame must transmit rows")

    pixelArena.draw(monitor, state, 1, rect)
    assertEq(blits, first, "Identical frame must send zero new rows")

    state.phase = "battle"
    pixelArena.draw(monitor, state, 1, rect)
    assertTrue(blits > first, "Phase transition must invalidate skipped rows")

    window = previousWindow
end

print("October 2026 audit hardening tests passed")

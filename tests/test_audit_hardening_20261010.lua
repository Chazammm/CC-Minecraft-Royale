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

print("October 2026 audit hardening tests passed")

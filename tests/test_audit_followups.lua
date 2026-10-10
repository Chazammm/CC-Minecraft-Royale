-- Focused regressions for the second full-project technical audit.
colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768,
}

package.path = "./?.lua;./?/init.lua;" .. package.path

local function assertEq(actual, expected, message)
    if actual ~= expected then
        error((message or "assertEq failed")
            .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual))
    end
end

local function assertNear(actual, expected, epsilon, message)
    if math.abs(actual - expected) > (epsilon or 1e-9) then
        error((message or "assertNear failed")
            .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual))
    end
end

local function assertTrue(value, message)
    if not value then error(message or "assertTrue failed") end
end

local config = require("config")
local util = require("src.util")
local cards = require("src.cards")
local arena = require("src.arena")
local Game = require("src.game")
local Bot = require("src.bot")
local benchmark = require("src.benchmark_utils")
local render = require("src.render")

-- Student-t interpolation/approximation must not understate df=31 the way the
-- old fixed df=40 bucket did.
assertNear(
    benchmark.critical95(32),
    2.039513446,
    0.00001,
    "95% Student-t critical value must be accurate at df=31"
)
assertNear(
    benchmark.critical95(100),
    1.984216952,
    0.00001,
    "95% Student-t critical value must be accurate at df=99"
)

-- Asking only for an Evolution cost must not deepcopy the complete card tree.
do
    local oldDeepcopy = util.deepcopy
    local deepcopyCalls = 0
    util.deepcopy = function(value)
        deepcopyCalls = deepcopyCalls + 1
        return oldDeepcopy(value)
    end

    local fastCost = cards.evolutionCost("iron_golem")
    util.deepcopy = oldDeepcopy
    local evolved = cards.evolvedCopy("iron_golem")

    assertEq(deepcopyCalls, 0, "Evolution cost lookup must not deepcopy the card")
    assertNear(
        fastCost,
        evolved.cost,
        1e-9,
        "Fast Evolution cost must exactly match evolvedCopy"
    )
end

-- The real affordability hotpath must use the same allocation-free
-- Evolution-cost helper as the dedicated cards API.
do
    local state = Game.new(nil, { headlessSimulation = true })
    assertTrue(Game.startHeadlessBattle(state, config.TICK_RATE), "Cost hotpath needs battle")
    state.players[1].evolutionCardId = "iron_golem"
    state.players[1].evolutionProgress = cards.evolutionCycles("iron_golem")

    local oldDeepcopy = util.deepcopy
    local deepcopyCalls = 0
    util.deepcopy = function(value)
        deepcopyCalls = deepcopyCalls + 1
        return oldDeepcopy(value)
    end

    local cost = Game.getCardPlayCost(state, 1, "iron_golem")
    util.deepcopy = oldDeepcopy

    assertEq(deepcopyCalls, 0, "Game.getCardPlayCost must not build an evolved card")
    assertNear(
        cost,
        cards.evolutionCost("iron_golem"),
        1e-9,
        "Game affordability cost must match the Evolution helper"
    )
end

-- Internal summon templates are immutable engine data. Reading one through the
-- engine-only path must not copy it before spawnUnitFromStats performs its one
-- defensive live-entity copy.
do
    local oldDeepcopy = util.deepcopy
    local deepcopyCalls = 0
    util.deepcopy = function(value)
        deepcopyCalls = deepcopyCalls + 1
        return oldDeepcopy(value)
    end

    local template = cards.getInternalUnitTemplate("vex")
    util.deepcopy = oldDeepcopy

    assertTrue(template ~= nil, "Vex internal template must exist")
    assertEq(deepcopyCalls, 0, "Internal engine template lookup must not deepcopy")
end

-- Emerald-generation bonuses are maintained as lifecycle state, not rebuilt by
-- rescanning every entity each tick/render.
do
    local state = Game.new(nil, { headlessSimulation = true })
    Game.debugLoadScenario(state, "empty")
    assertEq(state.emeraldBoost[1], 0, "Emerald cache starts empty")

    assertTrue(
        Game.debugSpawnCard(state, 1, "villager", 50, 120),
        "Emerald cache regression needs a Villager"
    )
    local villager
    for _, entity in ipairs(state.entities) do
        if entity.owner == 1 and entity.emeraldBoost then
            villager = entity
            break
        end
    end
    assertTrue(villager ~= nil, "Villager must exist")
    assertNear(
        state.emeraldBoost[1],
        villager.emeraldBoost,
        1e-9,
        "Spawn must register Emerald boost immediately"
    )

    assertTrue(Game.debugKillEntity(state, villager.id), "Villager debug kill must work")
    assertNear(state.emeraldBoost[1], 0, 1e-9, "Death must unregister Emerald boost immediately")

    assertTrue(
        Game.debugSpawnCard(state, 1, "villager", 55, 120),
        "Admin clear regression needs another Villager"
    )
    assertTrue(state.emeraldBoost[1] > 0, "Second Villager must register before CLEAR")
    Game.debugClearUnits(state)
    assertNear(
        state.emeraldBoost[1],
        0,
        1e-9,
        "Admin CLEAR must remove cached Emerald generation"
    )
    assertEq(
        next(state.emeraldBoostSources[1]),
        nil,
        "Admin CLEAR must remove cached Emerald boost sources"
    )
end

-- Config validation must reject settings that the runtime cannot simulate
-- consistently while leaving the live config object untouched.
do
    local invalidTick = util.deepcopy(config)
    invalidTick.TICK_RATE = 0.50
    local okTick = pcall(config.validate, invalidTick)
    assertTrue(not okTick, "TICK_RATE above Game.update's 0.25s ceiling must be rejected")

    local invalidEconomy = util.deepcopy(config)
    invalidEconomy.MATCH.emeraldStart = invalidEconomy.MATCH.emeraldMax + 1
    local okEconomy = pcall(config.validate, invalidEconomy)
    assertTrue(not okEconomy, "emeraldStart above emeraldMax must be rejected")

    assertTrue(config.validate(), "Live config must remain valid after candidate checks")
end

-- Strong and weak slows must retain their own durations. A later weak slow may
-- outlive the strong effect, but may never extend the strong factor itself.
do
    local state = Game.new(nil, { headlessSimulation = true })
    Game.debugLoadScenario(state, "empty")
    local ok = Game.debugSpawnCard(state, 2, "zombie", 50, 120)
    assertTrue(ok, "Slow regression needs a Zombie")

    local zombie
    for _, entity in ipairs(state.entities) do
        if entity.owner == 2 and entity.name == "Zombie" then zombie = entity end
    end
    assertTrue(zombie ~= nil, "Slow regression Zombie must exist")
    zombie.passive = true
    zombie.moveSpeed = 0

    Game.debugSetPaused(state, false)
    assertTrue(
        Game.debugApplySlow(state, zombie.id, 0.65, 1.5),
        "Strong slow must apply"
    )

    for _ = 1, 11 do Game.update(state, 0.10) end
    assertNear(zombie.slowFactor, 0.65, 1e-9, "Strong slow still active")

    assertTrue(
        Game.debugApplySlow(state, zombie.id, 0.80, 1.0),
        "Weak slow should add a later tail after the strong slow"
    )
    assertNear(
        zombie.slowFactor,
        0.65,
        1e-9,
        "Weak slow must not overwrite the active stronger factor"
    )

    for _ = 1, 5 do Game.update(state, 0.10) end
    assertNear(
        zombie.slowFactor,
        0.80,
        1e-9,
        "Weak slow must take over after the strong effect expires"
    )

    for _ = 1, 6 do Game.update(state, 0.10) end
    assertNear(zombie.slowFactor, 1, 1e-9, "All slows must expire independently")
    assertNear(zombie.slowRemaining, 0, 1e-9, "Aggregate slow timer must clear")
end

-- A successful card play must preserve the difficulty-specific think cadence.
local function postPlayDelay(mode)
    local state = Game.new(nil, { headlessSimulation = true })
    local bot = Bot.new(2, Bot.defaultDeck())
    Bot.prepare(bot, state)
    Game.debugLoadScenario(state, "full")
    Game.debugSetPaused(state, false)
    assertTrue(Bot.setDifficulty(bot, mode), "Difficulty must be accepted")
    Bot.setEnabled(bot, state, true, false)
    bot.thinkTimer = 0
    Bot.update(bot, state, 0.10)
    assertEq(bot.actions, 1, mode .. " bot should make one deterministic play")
    return bot.thinkTimer
end

do
    local easy = postPlayDelay("easy")
    local normal = postPlayDelay("normal")
    local hard = postPlayDelay("hard")
    assertTrue(
        hard < normal and normal < easy,
        "Successful plays must keep HARD < NORMAL < EASY think delays"
    )
end

-- The advertised 45x42 minimum must have non-overlapping touch zones.
do
    local monitor = {
        getSize = function()
            return config.MIN_RECOMMENDED_WIDTH, config.MIN_RECOMMENDED_HEIGHT
        end,
    }
    local layout = render.layoutFor(monitor)
    assertTrue(layout.compactLobby, "Minimum-height lobby should use compact controls")

    local function overlaps(a, b)
        return a.x1 <= b.x2 and a.x2 >= b.x1
            and a.y1 <= b.y2 and a.y2 >= b.y1
    end

    local lower = {
        layout.infoButton,
        layout.modeButton,
        layout.rulesetButton,
        layout.botDifficultyButton,
        layout.readyButton,
    }
    local fixed = { layout.evolutionSlot, layout.randomButton }
    for _, z in ipairs(layout.deckSlots) do fixed[#fixed + 1] = z end

    for _, a in ipairs(lower) do
        assertTrue(a.y1 >= 39 and a.y2 <= layout.height, "Compact control out of bounds")
        for _, b in ipairs(fixed) do
            assertTrue(not overlaps(a, b), "Compact lobby control overlaps deck/Evolution area")
        end
    end

    for i = 1, #lower do
        for j = i + 1, #lower do
            assertTrue(not overlaps(lower[i], lower[j]), "Compact lobby controls overlap each other")
        end
    end
end

-- Explicit monitor config must never assign both players to the same physical
-- peripheral.
do
    local oldPeripheral = peripheral
    local old1, old2 = config.MONITOR_NAMES[1], config.MONITOR_NAMES[2]
    local oldHardware = package.loaded["src.hardware"]

    config.MONITOR_NAMES[1] = "same_monitor"
    config.MONITOR_NAMES[2] = "same_monitor"
    peripheral = {}
    package.loaded["src.hardware"] = nil
    local hardware = require("src.hardware")
    local ok, err = pcall(hardware.init)
    assertTrue(not ok, "Duplicate configured monitors must be rejected")
    assertTrue(
        tostring(err):find("two different monitor", 1, true) ~= nil,
        "Duplicate-monitor error should explain the configuration problem"
    )

    config.MONITOR_NAMES[1], config.MONITOR_NAMES[2] = old1, old2
    peripheral = oldPeripheral
    package.loaded["src.hardware"] = oldHardware
end

-- A reboot after old->backup but before temp->final must recover the valid
-- preset backup instead of silently booting with empty saved loadouts.
do
    local oldFs = fs
    local oldTextutils = textutils
    local oldGameLoaded = package.loaded["src.game"]

    local stored = {
        ["deck_presets.db.bak"] = "VALID_PRESET_BACKUP",
    }

    fs = {
        exists = function(path) return stored[path] ~= nil end,
        isDir = function() return false end,
        open = function(path, mode)
            if mode == "r" and stored[path] ~= nil then
                return {
                    readAll = function() return stored[path] end,
                    close = function() end,
                }
            end
            return nil
        end,
        move = function(from, to)
            assert(stored[from] ~= nil, "fake move source missing")
            stored[to] = stored[from]
            stored[from] = nil
        end,
        delete = function(path) stored[path] = nil end,
    }

    textutils = {
        unserialize = function(raw)
            if raw ~= "VALID_PRESET_BACKUP" then return nil end
            return {
                [1] = { [1] = cards.defaultDeck() },
                [2] = {},
            }
        end,
    }

    package.loaded["src.game"] = nil
    local RecoveredGame = require("src.game")
    local recoveredState = RecoveredGame.new()

    assertTrue(
        cards.isValidDeck(recoveredState.deckPresets[1][1]),
        "Valid .bak preset must be recovered on boot"
    )
    assertEq(
        stored["deck_presets.db"],
        "VALID_PRESET_BACKUP",
        "Recovered preset backup should be promoted to the final path"
    )
    assertEq(stored["deck_presets.db.bak"], nil, "Recovered backup should be cleaned")

    package.loaded["src.game"] = oldGameLoaded
    fs = oldFs
    textutils = oldTextutils
end

-- Exact geometry ties are deliberate and deterministic: center lane maps right,
-- while an exactly symmetric cross-river route chooses the first (left) bridge.
assertEq(arena.laneForX(config.ARENA.width / 2), "right", "Center-line lane tie")
do
    local entity = { x = 50, y = 120, flying = false }
    local target = { x = 50, y = 40 }
    local x = arena.navigationPoint(entity, target)
    assertEq(x, config.ARENA.bridgeCenters[1], "Exact bridge tie must be deterministic")
end

-- Projectile ordering is also explicit: if two King-killing projectiles land
-- in one simulation tick, the earlier projectile resolves first and ends play.
do
    local state = Game.new(nil, { headlessSimulation = true })
    local started = Game.startHeadlessBattle(state, config.TICK_RATE)
    assertTrue(started, "Simultaneous projectile test must enter battle")

    local p1King, p2King
    for _, entity in ipairs(state.entities) do
        if entity.kind == "tower" and entity.towerType == "king" then
            if entity.owner == 1 then p1King = entity else p2King = entity end
        end
    end
    assertTrue(p1King and p2King, "Both King Towers must exist")
    p1King.hp, p2King.hp = 1, 1

    state.projectiles[1] = {
        x = p2King.x, y = p2King.y, targetId = p2King.id,
        owner = 1, sourceCardId = "skeleton", damage = 1,
        speed = 60, alive = true,
    }
    state.projectiles[2] = {
        x = p1King.x, y = p1King.y, targetId = p1King.id,
        owner = 2, sourceCardId = "skeleton", damage = 1,
        speed = 60, alive = true,
    }

    Game.update(state, config.TICK_RATE)
    assertEq(state.winner, 1, "Earlier simultaneous lethal projectile must resolve first")
end

-- syncAll should write all available report history/latest pairs through one
-- Git transaction rather than one commit per report.
do
    local oldFs = fs
    local oldHttp = http
    local oldTextutils = textutils
    local oldReportSync = package.loaded["src.report_sync"]

    local reportBodies = {
        mechanics_report = "MECHANICS",
        balance_results = "BALANCE",
        comparison_results = "COMPARISON",
        evolution_results = "EVOLUTION",
    }
    local pathBodies = {
        [".cc_royale/github_token.txt"] =
            "dummy-token-value-long-enough-for-tests",
        ["mechanics_report.txt"] = reportBodies.mechanics_report,
        ["balance_results.txt"] = reportBodies.balance_results,
        ["comparison_results.txt"] = reportBodies.comparison_results,
        ["evolution_results.txt"] = reportBodies.evolution_results,
    }

    local getCount = 0
    local rawGetCount = 0
    local blobCount = 0
    local treeCount = 0
    local commitCount = 0
    local patchCount = 0

    local function response(body, code)
        return {
            getResponseCode = function() return code or 200 end,
            readAll = function() return body end,
            close = function() end,
        }
    end

    fs = {
        exists = function(path) return pathBodies[path] ~= nil end,
        isDir = function() return false end,
        open = function(path, mode)
            if mode == "r" and pathBodies[path] ~= nil then
                return {
                    readAll = function() return pathBodies[path] end,
                    close = function() end,
                }
            end
            return nil
        end,
        getName = function(path) return path:match("([^/]+)$") end,
    }

    textutils = {
        serializeJSON = function() return "PAYLOAD" end,
        unserializeJSON = function(body)
            if body == "REF" then return { object = { sha = "parent" } } end
            if body == "PARENT" then return { tree = { sha = "base-tree" } } end
            if body == "BLOB" then return { sha = "blob-sha" } end
            if body == "TREE" then return { sha = "tree-sha" } end
            if body == "COMMIT" then return { sha = "commit-sha" } end
            if body == "{}" then return {} end
            return nil, "unexpected fake JSON"
        end,
    }

    http = {
        get = function(options)
            local url = type(options) == "table" and options.url or options
            if url:find("raw.githubusercontent.com", 1, true) then
                rawGetCount = rawGetCount + 1
                return response("REMOTE_OLD_CONTENT", 200)
            end
            getCount = getCount + 1
            if url:find("/git/ref/heads/main", 1, true) then
                return response("REF", 200)
            end
            if url:find("/git/commits/parent", 1, true) then
                return response("PARENT", 200)
            end
            return nil, "unexpected GET"
        end,
        post = function(options)
            if options.url:find("/git/blobs", 1, true) then
                blobCount = blobCount + 1
                return response("BLOB", 201)
            elseif options.url:find("/git/trees", 1, true) then
                treeCount = treeCount + 1
                return response("TREE", 201)
            elseif options.url:find("/git/commits", 1, true) then
                commitCount = commitCount + 1
                return response("COMMIT", 201)
            elseif options.url:find("/git/refs/heads/main", 1, true)
                and options.method == "PATCH"
            then
                patchCount = patchCount + 1
                return response("{}", 200)
            end
            return nil, "unexpected write"
        end,
    }

    package.loaded["src.report_sync"] = nil
    local ReportSync = require("src.report_sync")
    local ok, result = ReportSync.syncAll()

    assertTrue(ok, "Batch report sync must succeed")
    assertEq(#result.uploaded, 4, "All four reports should share the batch")
    assertEq(#result.failures, 0, "Batch report sync should have no failures")
    assertEq(rawGetCount, 4, "Batch sync should compare each remote latest once")
    assertEq(getCount, 2, "Batch sync should read branch and parent only once")
    assertEq(blobCount, 8, "Four changed reports need history + latest blobs")
    assertEq(treeCount, 1, "Batch sync should create one tree")
    assertEq(commitCount, 1, "Batch sync should create one commit")
    assertEq(patchCount, 1, "Batch sync should advance main once")
    for _, uploaded in ipairs(result.uploaded) do
        assertEq(uploaded.commitSha, "commit-sha", "All reports must share one commit")
    end

    package.loaded["src.report_sync"] = oldReportSync
    fs = oldFs
    http = oldHttp
    textutils = oldTextutils
end

do
    -- Byte-identical reports are successful no-ops and must not create another
    -- timestamped history blob.
    local oldFs = fs
    local oldHttp = http
    local oldTextutils = textutils
    local oldReportSync = package.loaded["src.report_sync"]

    local token = "dummy-token-value-long-enough-for-tests"
    local reportBody = "UNCHANGED_MECHANICS"
    fs = {
        exists = function(path)
            return path == ".cc_royale/github_token.txt"
                or path == "mechanics_report.txt"
        end,
        isDir = function() return false end,
        open = function(path, mode)
            if mode ~= "r" then return nil end
            local value = path == ".cc_royale/github_token.txt"
                and token
                or reportBody
            return {
                readAll = function() return value end,
                close = function() end,
            }
        end,
        getName = function(path) return path:match("([^/]+)$") end,
    }

    local writes = 0
    http = {
        get = function(options)
            local url = type(options) == "table" and options.url or options
            if url:find("raw.githubusercontent.com", 1, true) then
                return response(reportBody, 200)
            end
            error("Unchanged report must not reach Git Data reads")
        end,
        post = function()
            writes = writes + 1
            return nil, "unexpected write"
        end,
    }
    textutils = {
        serializeJSON = function() return "{}" end,
        unserializeJSON = function() return {} end,
    }

    package.loaded["src.report_sync"] = nil
    local ReportSync = require("src.report_sync")
    local ok, result = ReportSync.syncAll()
    assertTrue(ok, "Unchanged report sync should be a successful no-op")
    assertEq(#result.uploaded, 0, "Unchanged report must not upload")
    assertEq(#result.skipped, 1, "Unchanged report must be reported as skipped")
    assertEq(writes, 0, "Unchanged report must create no Git objects")

    package.loaded["src.report_sync"] = oldReportSync
    fs = oldFs
    http = oldHttp
    textutils = oldTextutils
end

do
    -- A malformed token path must never be recursively deleted.
    local oldFs = fs
    local oldReportSync = package.loaded["src.report_sync"]
    local deleteCalls = 0

    fs = {
        exists = function(path)
            return path == ".cc_royale/github_token.txt"
        end,
        isDir = function(path)
            return path == ".cc_royale/github_token.txt"
        end,
        delete = function()
            deleteCalls = deleteCalls + 1
        end,
    }

    package.loaded["src.report_sync"] = nil
    local ReportSync = require("src.report_sync")
    local ok = ReportSync.clearToken()
    assertTrue(not ok, "Directory token path must be rejected")
    assertEq(deleteCalls, 0, "Directory token path must never call recursive fs.delete")

    package.loaded["src.report_sync"] = oldReportSync
    fs = oldFs
end

do
    -- Targeting owner index must stay synchronized across spawn, death and
    -- cleanup while preserving insertion order.
    local state = Game.new(nil, { headlessSimulation = true })
    Game.debugLoadScenario(state, "empty")
    assertTrue(Game.debugSpawnCard(state, 1, "zombie", 40, 110))
    assertTrue(Game.debugSpawnCard(state, 2, "zombie", 40, 50))
    assertEq(#state.entitiesByOwner[1], 1, "P1 owner index must register spawn")
    assertEq(#state.entitiesByOwner[2], 1, "P2 owner index must register spawn")

    local p2 = state.entitiesByOwner[2][1]
    assertTrue(Game.debugKillEntity(state, p2.id), "Indexed entity kill must work")
    Game.debugSetPaused(state, false)
    Game.update(state, 0.10)
    assertEq(#state.entitiesByOwner[2], 0, "Cleanup must remove dead owner-index entries")
end

do
    -- maxAlive spawners use a lifecycle counter instead of rescanning every
    -- entity, and child death immediately frees one slot.
    local state = Game.new(nil, { headlessSimulation = true })
    Game.debugLoadScenario(state, "empty")
    assertTrue(Game.debugSpawnCard(state, 1, "evoker", 50, 110))
    local evoker
    for _, entity in ipairs(state.entities) do
        if entity.owner == 1 and entity.sourceCardId == "evoker" then
            evoker = entity
            break
        end
    end
    assertTrue(evoker ~= nil, "Summon counter regression needs Evoker")
    evoker.periodicSpawn = {
        template = "vex",
        interval = 10,
        initialDelay = 0.01,
        count = 2,
        maxAlive = 2,
        radius = 1,
    }
    evoker.periodicSpawnTimer = 0.01
    Game.debugSetPaused(state, false)
    Game.update(state, 0.02)
    assertEq(evoker.periodicSpawnAlive, 2, "Spawner must count living children")

    local child
    for _, entity in ipairs(state.entities) do
        if entity.summonerId == evoker.id and entity.alive then
            child = entity
            break
        end
    end
    assertTrue(child ~= nil, "Summon counter regression needs child")
    assertTrue(Game.debugKillEntity(state, child.id), "Summoned child debug kill must work")
    assertEq(evoker.periodicSpawnAlive, 1, "Child death must free maxAlive slot immediately")
end

do
    -- Spatial buckets must track movement across cell boundaries and keep
    -- bounded targeting behavior identical to the owner-list fallback.
    local state = Game.new(nil, { headlessSimulation = true })
    Game.debugLoadScenario(state, "empty")
    assertTrue(Game.debugSpawnCard(state, 1, "skeleton", 20, 110))
    assertTrue(Game.debugSpawnCard(state, 2, "zombie", 20, 70))
    assertTrue(Game.debugSpawnCard(state, 2, "zombie", 80, 70))
    Game.debugSetPaused(state, false)

    local skeleton = state.entitiesByOwner[1][1]
    local nearZombie = state.entitiesByOwner[2][1]
    skeleton.moveSpeed = 0
    skeleton.attackRange = 50
    skeleton.aggroRange = 50
    skeleton.attackCooldownLeft = 0

    local hpBefore = nearZombie.hp
    Game.update(state, 0.10)
    assertTrue(
        nearZombie.hp < hpBefore or skeleton.targetId == nearZombie.id,
        "Spatial bounded targeting must retain nearest-target behavior"
    )

    assertTrue(
        state.spatialIndex and state.spatialIndex.buckets,
        "Active combat tick must maintain spatial buckets"
    )
end

do
    -- Spatial AoE lookup must preserve deterministic multi-target damage.
    local state = Game.new(nil, { headlessSimulation = true })
    Game.debugLoadScenario(state, "empty")
    assertTrue(Game.debugSpawnCard(state, 1, "creeper", 50, 100))
    assertTrue(Game.debugSpawnCard(state, 2, "zombie", 48, 96))
    assertTrue(Game.debugSpawnCard(state, 2, "zombie", 52, 96))
    local creeper = state.entitiesByOwner[1][1]
    local enemies = state.entitiesByOwner[2]
    creeper.proximityExplosion.fuseTime = 0.01
    creeper.proximityExplosion.triggerRange = 10
    creeper.proximityExplosion.cancelRange = 12
    creeper.proximityExplosion.radius = 12

    local hp1, hp2 = enemies[1].hp, enemies[2].hp
    Game.debugSetPaused(state, false)
    Game.update(state, 0.10)
    Game.update(state, 0.10)

    assertTrue(enemies[1].hp < hp1, "Spatial explosion must hit first nearby enemy")
    assertTrue(enemies[2].hp < hp2, "Spatial explosion must hit second nearby enemy")
end

do
    -- Spatial radius queries must exactly match a full-scan reference across
    -- many deterministic positions/radii/owners.
    local state = Game.new(nil, { headlessSimulation = true })
    Game.debugLoadScenario(state, "empty")

    for i = 1, 28 do
        local owner = i % 2 == 0 and 1 or 2
        assertTrue(
            Game.debugSpawnCard(state, owner, "zombie", 10 + (i % 8) * 10, 20 + (i % 12) * 10),
            "Spatial fuzz setup spawn failed"
        )
    end

    local rng = 24681357
    local function nextInt(maximum)
        rng = (rng * 48271) % 2147483647
        return (rng % maximum) + 1
    end

    for round = 1, 160 do
        for _, entity in ipairs(state.entities) do
            entity.x = nextInt(9900) / 100 + 0.5
            entity.y = nextInt(15900) / 100 + 0.5
        end

        local owner = nextInt(2)
        local x = nextInt(10000) / 100
        local y = nextInt(16000) / 100
        local radius = 1 + nextInt(4500) / 100

        local actual = Game.debugSpatialRadiusIds(state, owner, x, y, radius)
        local expected = {}
        local radiusSq = radius * radius
        for _, entity in ipairs(state.entities) do
            if entity.alive
                and entity.owner == owner
                and util.distanceSquared(x, y, entity.x, entity.y) <= radiusSq
            then
                expected[#expected + 1] = entity.id
            end
        end
        table.sort(expected)

        assertEq(#actual, #expected, "Spatial fuzz candidate count mismatch")
        for i = 1, #expected do
            assertEq(actual[i], expected[i], "Spatial fuzz candidate order/content mismatch")
        end
    end
end

do
    -- Equal-distance target ties must preserve the historical lower-ID winner
    -- even though nearest-target queries no longer sort candidate tables.
    local state = Game.new(nil, { headlessSimulation = true })
    Game.debugLoadScenario(state, "empty")
    assertTrue(Game.debugSpawnCard(state, 1, "skeleton", 50, 110))
    assertTrue(Game.debugSpawnCard(state, 2, "zombie", 45, 100))
    assertTrue(Game.debugSpawnCard(state, 2, "zombie", 55, 100))

    local skeleton = state.entitiesByOwner[1][1]
    local firstEnemy = state.entitiesByOwner[2][1]
    skeleton.moveSpeed = 0
    skeleton.aggroRange = 30
    Game.debugSetPaused(state, false)
    Game.update(state, 0.10)

    assertEq(
        skeleton.targetId,
        firstEnemy.id,
        "Nearest spatial tie must resolve to lower entity ID"
    )
end

print("Audit follow-up tests passed")

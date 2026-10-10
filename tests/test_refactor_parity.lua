-- Focused behavioral guards for code moved out of src/game/render modules.
colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768,
}
colors.toBlit = function() return "0" end

package.path = "./?.lua;./?/init.lua;" .. package.path

local function assertEq(actual, expected, message)
    if actual ~= expected then
        error((message or "assertEq failed")
            .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual))
    end
end

local function assertTrue(value, message)
    if not value then error(message or "assertTrue failed") end
end

local Game = require("src.game")
local spatial = require("src.spatial")
local uiBuffer = require("src.ui_buffer")
local adminRender = require("src.admin_render")
local pixelArena = require("src.pixel_arena")

local function assertSpatialOrderMatchesEntities(state, owner, message)
    local actual = spatial.candidatesInRadius(state, owner, 50, 80, 500)
    local expected = {}
    for _, entity in ipairs(state.entities) do
        if entity.alive and entity.owner == owner then
            expected[#expected + 1] = entity
        end
    end

    assertEq(#actual, #expected, (message or "Spatial order") .. " count")
    for i = 1, #expected do
        assertEq(
            actual[i].id,
            expected[i].id,
            (message or "Spatial order") .. " at index " .. tostring(i)
        )
    end
end

-- Cleanup compaction must update the order metadata stored on the same entity
-- references already held by spatial buckets. No rebuild is allowed here: the
-- regression is specifically about live incremental battle state.
do
    local state = Game.new(nil, { headlessSimulation = true })
    Game.debugLoadScenario(state, "empty")

    for i = 1, 4 do
        assertTrue(
            Game.debugSpawnCard(state, 2, "zombie", 20 + i * 8, 80),
            "Order regression setup spawn failed"
        )
    end

    local first = state.entitiesByOwner[2][1]
    local second = state.entitiesByOwner[2][2]
    assertTrue(Game.debugKillEntity(state, first.id), "First cleanup kill failed")
    assertTrue(Game.debugKillEntity(state, second.id), "Second cleanup kill failed")

    Game.debugSetPaused(state, false)
    Game.update(state, 0.01) -- performs cleanupEntities
    Game.debugSetPaused(state, true)

    assertTrue(
        Game.debugSpawnCard(state, 2, "zombie", 70, 80),
        "Post-cleanup spawn failed"
    )
    assertSpatialOrderMatchesEntities(
        state,
        2,
        "Cleanup -> respawn must preserve ordered AoE traversal"
    )

    -- Repeat once so stale order cannot hide behind a single compaction.
    local survivor = state.entitiesByOwner[2][1]
    assertTrue(Game.debugKillEntity(state, survivor.id), "Repeated cleanup kill failed")
    Game.debugSetPaused(state, false)
    Game.update(state, 0.01)
    Game.debugSetPaused(state, true)
    assertTrue(
        Game.debugSpawnCard(state, 2, "zombie", 76, 80),
        "Second post-cleanup spawn failed"
    )
    assertSpatialOrderMatchesEntities(
        state,
        2,
        "Repeated cleanup -> respawn must preserve ordered AoE traversal"
    )
end

-- Non-flaky performance guard: bounded bucket traversal must actually prune
-- candidate visits compared with scanning the full owner list. This checks
-- operation count, not wall-clock timing.
do
    local state = Game.new(nil, { headlessSimulation = true })
    Game.debugLoadScenario(state, "empty")

    local positions = {
        { 8, 20 }, { 30, 20 }, { 52, 20 }, { 76, 20 }, { 96, 20 },
        { 8, 60 }, { 30, 60 }, { 52, 60 }, { 76, 60 }, { 96, 60 },
        { 8, 100 }, { 30, 100 }, { 52, 100 }, { 76, 100 }, { 96, 100 },
        { 8, 140 }, { 30, 140 }, { 52, 140 }, { 76, 140 }, { 96, 140 },
    }
    for _, pos in ipairs(positions) do
        assertTrue(Game.debugSpawnCard(state, 2, "zombie", pos[1], pos[2]))
    end

    local visited = 0
    spatial.forEachInBounds(state, 2, 2, 14, 18, 30, function()
        visited = visited + 1
    end)

    assertTrue(visited > 0, "Bounded Spatial query must visit nearby candidates")
    assertTrue(
        visited < #state.entitiesByOwner[2],
        "Bounded Spatial query must prune candidates versus full owner scan"
    )
end

-- Shared UI buffer: skip rows stay untouched, an identical second flush emits
-- no monitor traffic, and exposing a previously skipped row invalidates it.
do
    local rows = {}
    local blits = 0
    local cursorY = 1
    local monitor = {
        setCursorPos = function(_, y) cursorY = y end,
        blit = function(chars)
            blits = blits + 1
            rows[cursorY] = chars
        end,
    }

    local skip = { y1 = 2, y2 = 2 }
    local buffer = uiBuffer.newBuffer(
        8,
        4,
        colors.white,
        colors.black,
        skip
    )
    uiBuffer.writeText(buffer, 1, 1, "ABC", colors.white, colors.black)
    uiBuffer.flush(buffer, monitor, skip)
    assertEq(blits, 3, "Initial flush must skip exactly one row")
    assertEq(rows[2], nil, "Skipped UI row must not be blitted")

    uiBuffer.flush(buffer, monitor, skip)
    assertEq(blits, 3, "Identical second flush must emit no extra blits")

    buffer = uiBuffer.newBuffer(
        8,
        4,
        colors.white,
        colors.black,
        nil,
        buffer
    )
    uiBuffer.flush(buffer, monitor)
    assertEq(
        blits,
        5,
        "Unskipping must redraw newly exposed row plus row whose content changed"
    )
    assertTrue(rows[2] ~= nil, "Previously skipped row must be rendered when exposed")
end

-- Admin renderer must still produce its UI through the shared buffer, and an
-- unchanged second draw must not re-blit text rows. Pixel Arena is isolated
-- here because this test is specifically about the refactored text/UI layer.
do
    local oldPixelDraw = pixelArena.draw
    pixelArena.draw = function() end

    local rows = {}
    local blits = 0
    local cursorY = 1
    local monitor = {
        getSize = function() return 57, 52 end,
        setCursorPos = function(_, y) cursorY = y end,
        blit = function(chars)
            blits = blits + 1
            rows[cursorY] = chars
        end,
    }

    local state = Game.new(nil, { headlessSimulation = true })
    Game.debugLoadScenario(state, "empty")
    local catalog = require("src.cards").adminSpawnCards()
    local ui = {
        owner = 1,
        selectedCard = catalog[1] and catalog[1].key or nil,
        cardPage = 1,
        spawnCatalog = catalog,
        bot = { enabled = false, playerId = 2 },
    }

    adminRender.draw(monitor, state, 1, ui)
    local firstBlits = blits
    assertTrue(
        rows[1] and rows[1]:find("ADMIN SANDBOX", 1, true) ~= nil,
        "Admin renderer must still draw its title through shared UI buffer"
    )
    assertTrue(firstBlits > 0, "First admin draw must emit text rows")

    adminRender.draw(monitor, state, 1, ui)
    assertEq(
        blits,
        firstBlits,
        "Unchanged second admin draw must not re-blit text rows"
    )

    pixelArena.draw = oldPixelDraw
end

print("Refactor parity tests passed")

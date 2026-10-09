-- Focused side-symmetry checks for arena geometry, bot identity, and
-- paired benchmark scheduling.

colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768,
}

package.path = "./?.lua;./?/init.lua;" .. package.path

local config = require("config")
local arena = require("src.arena")
local Game = require("src.game")
local Bot = require("src.bot")
local Runner = require("src.headless_match")

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

local H = config.ARENA.height

do
    -- Every Crown Tower must have a vertically mirrored counterpart.
    local towers = arena.towerBlueprints()
    for _, p1 in ipairs(towers) do
        if p1.owner == 1 then
            local mirror = nil
            for _, p2 in ipairs(towers) do
                if p2.owner == 2
                    and p2.towerType == p1.towerType
                    and p2.x == p1.x
                    and p2.y == H - p1.y
                then
                    mirror = p2
                    break
                end
            end
            assertEq(
                mirror ~= nil,
                true,
                "Every P1 tower needs an exact P2 vertical mirror"
            )
        end
    end
end

do
    -- Normal deployment boundaries must be identical after swapping sides and
    -- reflecting Y through the arena midpoint.
    local xs = { 4, 25, 50, 75, 96 }
    local ys = { 4, 20, 69, 70, 73, 74, 80, 86, 87, 90, 120, 140, 156 }
    for _, x in ipairs(xs) do
        for _, y in ipairs(ys) do
            assertEq(
                arena.placementAllowed(1, x, y, "ground", nil),
                arena.placementAllowed(2, x, H - y, "ground", nil),
                ("Ground placement mirror mismatch at %.1f, %.1f"):format(x, y)
            )
        end
    end
end

do
    -- Bridge/path navigation must reflect exactly in Y for equivalent units.
    local probes = {
        { ex = 25, ey = 120, tx = 25, ty = 40 },
        { ex = 50, ey = 120, tx = 75, ty = 40 },
        { ex = 82, ey = 100, tx = 18, ty = 55 },
    }

    for _, p in ipairs(probes) do
        local entity1 = { x = p.ex, y = p.ey, flying = false }
        local target1 = { x = p.tx, y = p.ty }
        local x1, y1 = arena.navigationPoint(entity1, target1)

        local entity2 = { x = p.ex, y = H - p.ey, flying = false }
        local target2 = { x = p.tx, y = H - p.ty }
        local x2, y2 = arena.navigationPoint(entity2, target2)

        assertNear(x2, x1, 1e-9, "Navigation X must be side-symmetric")
        assertNear(y2, H - y1, 1e-9, "Navigation Y must be side-symmetric")
    end
end

do
    -- Bot micro-variation must follow the deck, never P1/P2 identity.
    local deck = {
        "zombie", "skeleton", "iron_golem", "bat_swarm",
        "cannon", "arrows", "villager", "wolf",
    }
    local p1 = Bot.new(1, deck)
    local p2 = Bot.new(2, deck)
    assertEq(
        p1.styleSeed,
        p2.styleSeed,
        "Identical decks must get identical bot style seeds on both sides"
    )

    local state = Game.new()
    Bot.prepare(p1, state)
    Bot.prepare(p2, state)
    assertEq(
        p1.styleSeed,
        p2.styleSeed,
        "Bot.prepare must preserve side-independent deck style"
    )
end

do
    -- Side-swapped benchmark matches can reverse who is updated first without
    -- changing the underlying alternating schedule.
    assertEq(Runner.debugFirstBotForTick(10, 0), 1, "Default even tick order")
    assertEq(Runner.debugFirstBotForTick(10, 1), 2, "Reversed even tick order")
    assertEq(Runner.debugFirstBotForTick(11, 0), 2, "Default odd tick order")
    assertEq(Runner.debugFirstBotForTick(11, 1), 1, "Reversed odd tick order")
end

print("Side symmetry tests passed")

-- Reproducible CPU microprofile. Diagnostic only: NEVER threshold raw times
-- in CI; shared GitHub runners and CC:Tweaked computers have different CPUs.
-- Run: lua5.4 tests/performance_profile.lua
--      lua5.2 tests/performance_profile.lua
-- Reports CPU time and frame/decision counts, not visual or hardware latency.
colors = {
    white=1, orange=2, magenta=4, lightBlue=8,
    yellow=16, lime=32, pink=64, gray=128,
    lightGray=256, cyan=512, purple=1024, blue=2048,
    brown=4096, green=8192, red=16384, black=32768,
}
package.path = "./?.lua;./?/init.lua;" .. package.path

local Game = require("src.game")
local Bot = require("src.bot")
local Runner = require("src.headless_match")
local config = require("config")

local function printMetric(name, count, seconds, extra)
    print(("PROFILE|%s|count=%d|cpu_s=%.6f|mean_ms=%.4f%s"):format(
        name, count, seconds,
        count > 0 and seconds * 1000 / count or 0,
        extra and ("|" .. extra) or ""
    ))
end

-- Time the real functions used by Runner, without changing its decisions.
-- Instrumentation has some overhead; compare ratios, not microseconds.
local originalGameUpdate = Game.update
local originalBotUpdate = Bot.update
local totals = {
    game = 0, gameCalls = 0,
    bot = 0, botCalls = 0,
}
Game.update = function(...)
    local t = os.clock()
    local result = originalGameUpdate(...)
    totals.game = totals.game + os.clock() - t
    totals.gameCalls = totals.gameCalls + 1
    return result
end
Bot.update = function(...)
    local t = os.clock()
    local result = originalBotUpdate(...)
    totals.bot = totals.bot + os.clock() - t
    totals.botCalls = totals.botCalls + 1
    return result
end

local deckA = Bot.defaultDeck()
local deckB = {
    "skeleton", "iron_golem", "bat_swarm", "creeper",
    "slime", "witch", "spider", "wolf",
}
local caseStart = os.clock()
local totalTicks, totalActions = 0, 0
for i = 1, 3 do
    local left = (i % 2 == 1) and deckA or deckB
    local right = (i % 2 == 1) and deckB or deckA
    local state, bot1, bot2, ticks = Runner.run(left, right, {
        dt = config.TICK_RATE,
        gameplaySeed = 20261010 + i,
        botOrderOffset = i % 2,
    })
    assert(state.phase == "result", "Headless profiling match did not finish")
    totalTicks = totalTicks + ticks
    totalActions = totalActions + bot1.actions + bot2.actions
end
local fullCpu = os.clock() - caseStart
Game.update = originalGameUpdate
Bot.update = originalBotUpdate
printMetric("headless_3_matches", 3, fullCpu,
    "ticks=" .. totalTicks .. "|bot_actions=" .. totalActions)
printMetric("headless_game_update", totals.gameCalls, totals.game)
printMetric("headless_bot_update", totals.botCalls, totals.bot)
printMetric("headless_other", 3,
    math.max(0, fullCpu - totals.game - totals.bot))

-- Stress decision scoring at fixed bot state density. Explicitly force a
-- decision every iteration: normal games generally decide far less often.
-- Thus these numbers are the upper-end decision cost, NOT average tick cost.
local function congestedState()
    local state = Game.new(nil, {headlessSimulation=true})
    Game.debugLoadScenario(state, "full")
    for i = 1, 30 do
        local x = 13 + (i % 6) * 14
        local y = 27 + math.floor((i - 1) / 6) * 16
        assert(Game.debugSpawnCard(state, 2, "zombie", x, y),
            "Failed to populate bot stress scenario")
    end
    for i = 1, 10 do
        local x = 19 + (i % 5) * 15
        local y = 105 + math.floor((i - 1) / 5) * 19
        assert(Game.debugSpawnCard(state, 1, "zombie", x, y))
    end
    Game.debugSetPaused(state, false)
    return state
end

local crowdedDeck = {
    "falling_anvil", "arrows", "zombie", "cannon",
    "villager", "skeleton", "creeper", "iron_golem",
}
local function decisionStress(withAnvil)
    local state = congestedState()
    local bot = Bot.new(1, crowdedDeck)
    Bot.prepare(bot, state)
    bot.enabled = true
    Bot.setDifficulty(bot, "hard")
    local calls = 35
    local t = os.clock()
    for i = 1, calls do
        bot.thinkTimer = 0
        state.players[1].emeralds = 10
        if withAnvil then
            state.players[1].hand[1] = "falling_anvil"
        else
            state.players[1].hand[1] = "zombie"
        end
        state.pendingSpells = {}
        Bot.update(bot, state, config.TICK_RATE)
    end
    local duration = os.clock() - t
    printMetric(
        withAnvil and "crowded_bot_anvil_decisions"
            or "crowded_bot_regular_decisions",
        calls, duration, "enemy_units=30"
    )
end

decisionStress(false)
decisionStress(true)

-- Render the same static scene on two virtual 55x40 text windows.
-- This tests real PixelBox conversion and line-diffing, not network RTT.
local pixelArena = require("src.pixel_arena")
local stats = {blits=0, pixels=0}
local oldWindow = window

window = {
    create = function(_, _, _, w, h)
        local obj = {
            getSize = function() return w, h end,
            getBackgroundColor = function() return colors.black end,
            setBackgroundColor = function() end,
            clear = function() end,
            setCursorPos = function() end,
            blit = function(chars)
                stats.blits = stats.blits + 1
                stats.pixels = stats.pixels + #chars
            end,
        }
        return obj
    end,
}

local rect = {x1=1, y1=3, x2=55, y2=42}
local monitorA, monitorB = {}, {}

local function renderStress(units)
    local state = Game.new(nil, {headlessSimulation=true})
    Game.debugLoadScenario(state, "full")
    for i = 1, units do
        local owner = (i % 2) + 1
        local x = 12 + (i % 6) * 14
        local y = 24 + math.floor((i - 1) / 6) * 14
        assert(Game.debugSpawnCard(state, owner, "zombie", x, y))
    end
    local first = os.clock()
    pixelArena.draw(monitorA, state, 1, rect)
    pixelArena.draw(monitorB, state, 2, rect)
    local firstSeconds = os.clock() - first
    local firstBlits = stats.blits

    stats.blits, stats.pixels = 0, 0
    local frames = 12
    local t = os.clock()
    for _ = 1, frames do
        pixelArena.draw(monitorA, state, 1, rect)
        pixelArena.draw(monitorB, state, 2, rect)
    end
    local elapsed = os.clock() - t
    local repeatedBlits = stats.blits
    printMetric("static_arena_" .. units .. "_units_2_monitors",
        frames, elapsed,
        "first_ms=" .. string.format("%.4f", firstSeconds * 1000)
            .. "|initial_blits=" .. firstBlits
            .. "|unchanged_blits=" .. repeatedBlits)
    assert(repeatedBlits == 0,
        "Unchanged arena frames should not issue physical monitor blits")
end

renderStress(0)
renderStress(30)

-- Same-process A/B against the original exhaustive PixelBox encoder. The
-- optional forceFullEncode flag bypasses ONLY the frame identity cache, not
-- draw logic, animation, texel conversion or terminal row deduplication.
local function pairedFrameProfile(unitCount, moving)
    local state = Game.new(nil, {headlessSimulation=true})
    Game.debugLoadScenario(state, "full")
    local movingUnit = nil
    for i=1,unitCount do
        local owner = (i%2)+1
        local x=12+(i%6)*14
        local y=24+math.floor((i-1)/6)*14
        assert(Game.debugSpawnCard(state,owner,"zombie",x,y))
    end
    for _,entity in ipairs(state.entities) do
        if entity.sourceCardId=="zombie" then
            movingUnit=entity
            break
        end
    end

    local fastMonitor, oracleMonitor = {}, {}
    pixelArena.draw(fastMonitor,state,1,rect)
    pixelArena.draw(oracleMonitor,state,1,rect,true)
    local iterations=36
    local fastCpu, oracleCpu = 0, 0
    for i=1,iterations do
        if moving and movingUnit then
            movingUnit.x=30 + math.sin(i * 0.55) * 9
        end
        local t=os.clock()
        pixelArena.draw(fastMonitor,state,1,rect)
        fastCpu=fastCpu+(os.clock()-t)
        t=os.clock()
        pixelArena.draw(oracleMonitor,state,1,rect,true)
        oracleCpu=oracleCpu+(os.clock()-t)
    end
    local scenario=(moving and "moving_" or "static_")..unitCount
    printMetric("pixelbox_cached_"..scenario,iterations,fastCpu)
    printMetric("pixelbox_exhaustive_"..scenario,iterations,oracleCpu)
    print(("PROFILE|pixelbox_ratio_%s|cached_over_exhaustive=%.3f"):format(
        scenario, fastCpu/math.max(oracleCpu,0.000001)))
end
pairedFrameProfile(0,false)
pairedFrameProfile(30,false)
pairedFrameProfile(30,true)
window = oldWindow

print("Performance profile complete (no gameplay files modified).")

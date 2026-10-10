-- Exhaustive vs grid-optimized Falling Anvil scoring on crowded boards.
-- Identical target, score and first-best tie decisions are mandatory.
colors = {
    white=1,orange=2,magenta=4,lightBlue=8,yellow=16,lime=32,
    pink=64,gray=128,lightGray=256,cyan=512,purple=1024,
    blue=2048,brown=4096,green=8192,red=16384,black=32768,
}
package.path = "./?.lua;./?/init.lua;" .. package.path
local Game = require("src.game")
local Bot = require("src.bot")
local checked = 0

local function same(a,b,label)
    assert(a == b, label .. ": grid=" .. tostring(a) .. " oracle=" .. tostring(b))
    checked = checked + 1
end

-- Deterministic stress with concentrations, two banks, near cell edges,
-- overlapping towers and changing target-id/slow predictions.
for owner = 1, 2 do
    for scenario = 1, 10 do
        local state = Game.new(nil,{headlessSimulation=true})
        Game.debugLoadScenario(state,"full")

        for i = 1, 46 do
            local enemy = 3 - owner
            local x,y
            if scenario % 3 == 0 then
                x = 30 + (i % 8) * 0.45
                y = 110 + math.floor((i - 1) / 8) * 0.65
            elseif scenario % 3 == 1 then
                x = 4 + ((i * 37 + scenario * 11) % 90)
                y = 10 + ((i * 53 + scenario * 13) % 140)
            else
                x = 12 + ((i * 17 + scenario) % 75)
                y = 70 + ((i * 19 + scenario) % 25)
            end
            local kind = (i % 8 == 0) and "cannon"
                or ((i % 7 == 0) and "blaze" or "zombie")
            assert(Game.debugSpawnCard(state, enemy, kind, x, y))
        end

        -- Probe both modes on identical mutable state with pending warnings.
        for pass = 1, 3 do
            if pass == 2 then
                state.pendingSpells = {
                    {kind="falling_anvil", owner=owner, x=32, y=110},
                }
            elseif pass == 3 then
                state.pendingSpells = {
                    {kind="falling_anvil", owner=owner, x=58, y=82},
                }
            end
            local gx,gy,gs = Bot.debugAnvilTarget(state, owner, false)
            local ox,oy,os = Bot.debugAnvilTarget(state, owner, true)
            same(gx,ox,"X owner "..owner.." scenario "..scenario)
            same(gy,oy,"Y owner "..owner.." scenario "..scenario)
            same(gs,os,"Score owner "..owner.." scenario "..scenario)
        end
    end
end

-- Under the threshold the same oracle path should remain selected.
do
    local state = Game.new(nil,{headlessSimulation=true})
    Game.debugLoadScenario(state,"full")
    for i=1,12 do
        assert(Game.debugSpawnCard(state,2,"zombie",10+i*5,100))
    end
    local a,b,c=Bot.debugAnvilTarget(state,1,false)
    local x,y,z=Bot.debugAnvilTarget(state,1,true)
    same(a,x,"small X")
    same(b,y,"small Y")
    same(c,z,"small score")
end
print("Anvil exhaustive/grid parity passed (" .. checked .. " comparisons)")

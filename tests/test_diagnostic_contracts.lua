colors={white=1,orange=2,magenta=4,lightBlue=8,yellow=16,lime=32,pink=64,
    gray=128,lightGray=256,cyan=512,purple=1024,blue=2048,brown=4096,
    green=8192,red=16384,black=32768}
local Game=require('src.game')
local Bot=require('src.bot')
local Runner=require('src.headless_match')
local cards=require('src.cards')
local diagnostics=require('src.diagnostics')
local config=require('config')
local a=Bot.defaultDeck()
local b={'evoker','nether_portal','magma_cube','iron_golem','arrows','blaze','snow_golem','endermite'}
local s=Runner.run(a,b,{gameplaySeed=1437})
local probes=0
local checked=Runner.run(a,b,{gameplaySeed=1437,onTick=function(state)
    diagnostics.assertState(state,'read-only observer');probes=probes+1
end})
assert(diagnostics.combatSnapshot(s)==diagnostics.combatSnapshot(checked),
    'Read-only diagnostics changed actual combat output')
assert(probes>100,'Too few states inspected')
local state=Game.new(nil,{headlessSimulation=true});Game.startHeadlessBattle(state,0.1)
for _,fault in ipairs({'hp','emeralds','terrain','id','spatial'}) do
    local restore=diagnostics.restorePoint(state)
    if fault=='hp' then state.entities[1].hp=-1
    elseif fault=='emeralds' then state.players[1].emeralds=-0.00001
    elseif fault=='terrain' then state.entities[1].x=50;state.entities[1].y=80
    elseif fault=='id' then state.entities[2].id=state.entities[1].id
    else state.spatialIndex.buckets[1][state.entities[1]._spatialKey][state.entities[1].id]=nil end
    local ok=pcall(diagnostics.assertState,state,'fault '..fault)
    restore();assert(not ok,'Diagnostic missed injected '..fault)
    diagnostics.assertState(state,'recovered fault')
end
-- Compare headless countdown optimization to a genuinely independent live
-- countdown driver, including zero and fractional countdown configurations.
for _,countdown in ipairs({0,0.23,3}) do
    local original=config.MATCH.countdown;config.MATCH.countdown=countdown
    local live=Game.new();local headless=Game.new(nil,{headlessSimulation=true})
    live.players[1].deck=a;live.players[2].deck=b
    headless.players[1].deck=a;headless.players[2].deck=b
    Game.startCountdown(live);local ticks=0
    repeat Game.update(live,0.1);ticks=ticks+1 until live.phase=='battle'
    local ok,skipped=Game.startHeadlessBattle(headless,0.1)
    config.MATCH.countdown=original
    assert(ok and skipped==ticks,'Actual live countdown parity drift')
    assert(diagnostics.combatSnapshot(live)==diagnostics.combatSnapshot(headless))
    for _=1,240 do
        Game.update(live,0.1);Game.update(headless,0.1)
        assert(diagnostics.combatSnapshot(live)==diagnostics.combatSnapshot(headless),
            'Live/headless state drift after battle transition')
    end
end
print(('Diagnostic contracts passed: %d real match snapshots, 5 detected faults, 3 live countdown comparisons'):format(probes))

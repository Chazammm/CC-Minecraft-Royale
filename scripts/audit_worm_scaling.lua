-- Synthetic host microprofile of the new ambush search, not a CC benchmark.
colors={white=1,orange=2,magenta=4,lightBlue=8,yellow=16,lime=32,pink=64,
    gray=128,lightGray=256,cyan=512,purple=1024,blue=2048,brown=4096,
    green=8192,red=16384,black=32768}
local Game=require('src.game')
local Bot=require('src.bot')
local arena=require('src.arena')
for _,count in ipairs({20,60,120,240}) do
    local state=Game.new(nil,{headlessSimulation=true})
    Game.debugLoadScenario(state,'empty')
    for i=1,count do
        assert(Game.debugSpawnCard(state,2,'zombie',8+(i%12)*7,10+math.floor(i/12)*2))
        state.entities[#state.entities].passive=true
    end
    -- Count real calls without changing the validator, target samples or view.
    local original=arena.placementAllowed
    local calls=0
    arena.placementAllowed=function(...)
        calls=calls+1
        return original(...)
    end
    local started=os.clock()
    for _=1,10 do Bot.debugWormTarget(state,1) end
    local seconds=os.clock()-started
    arena.placementAllowed=original
    print(('WORM_SEARCH|enemies=%d|decisions=10|placement_calls=%d|cpu_s=%.6f|mean_ms=%.4f'):format(
        count,calls,seconds,seconds*100))
end

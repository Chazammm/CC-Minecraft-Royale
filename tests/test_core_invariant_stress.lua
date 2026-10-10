-- Deep audit: deterministically stress live combat indexing and economy under
-- many bot actions. This is not a mock of combat: Runner invokes actual
-- Game.update/Bot.update at the production 0.10s cadence.
-- A deterministic replay seed is printed on failure for reproduction.
colors = {
    white=1,orange=2,magenta=4,lightBlue=8,yellow=16,lime=32,pink=64,
    gray=128,lightGray=256,cyan=512,purple=1024,blue=2048,brown=4096,
    green=8192,red=16384,black=32768,
}
package.path="./?.lua;./?/init.lua;"..package.path
local config=require("config")
local Game=require("src.game")
local Bot=require("src.bot")
local Runner=require("src.headless_match")
local checks,ticks,matches=0,0,0
local function ensure(ok,msg)
    assert(ok,msg)
    checks=checks+1
end
local function checkFinite(v,label)
    ensure(type(v)=="number" and v==v and v~=math.huge
        and v~=-math.huge,"nonfinite "..label..": "..tostring(v))
end
local function assertState(state,seed)
    local prefix="seed "..seed..", tick "..tostring(state.combatTick)..": "
    local seen={},{}
    local owners={[1]={},[2]={}}
    local byId={}
    for position,entity in ipairs(state.entities) do
        local id=entity.id
        ensure(id~=nil and not byId[id],prefix.."duplicate or missing entity ID "..tostring(id))
        byId[id]=entity
        ensure(entity.owner==1 or entity.owner==2,prefix.."invalid owner "..tostring(id))
        checkFinite(entity.x,"x id="..id)
        checkFinite(entity.y,"y id="..id)
        checkFinite(entity.hp,"hp id="..id)
        checkFinite(entity.maxHp,"maxHp id="..id)
        ensure(entity.maxHp>0,prefix.."nonpositive maxHP id="..id)
        if entity.alive then
            ensure(entity.hp>0,prefix.."alive entity with zero HP id="..id)
            ensure(entity.hp<=entity.maxHp+0.001,prefix.."overmax HP id="..id)
            ensure(state.entityById[id]==entity,prefix.."broken id lookup "..id)
            ensure(entity._spatialOrder==position,prefix.."stale spatial order "..id)
            owners[entity.owner][#owners[entity.owner]+1]=entity
            local spatial=state.spatialIndex
            ensure(spatial and entity._spatialKey,
                prefix.."live entity not spatially indexed "..id)
            ensure(entity._spatialOwner==entity.owner,prefix.."spatial owner mismatch "..id)
            local bucket=spatial.buckets[entity.owner][entity._spatialKey]
            ensure(bucket and bucket[id]==entity,prefix.."spatial bucket mismatch "..id)
        end
    end
    for id,e in pairs(state.entityById) do
        ensure(byId[id]==e and e.alive,prefix.."orphan/stale ID map "..id)
    end
    for owner=1,2 do
        local owned=state.entitiesByOwner[owner]
        ensure(#owned==#owners[owner],prefix.."owner roster count "..owner)
        for i,e in ipairs(owners[owner]) do
            ensure(owned[i]==e,prefix.."owner roster order "..owner..":"..i)
        end
        local p=state.players[owner]
        checkFinite(p.emeralds,"emeralds")
        ensure(p.emeralds>=-0.00001 and p.emeralds<=p.maxEmeralds+0.00001,
            prefix.."emerald bounds owner "..owner)
    end
    local seenBucket={}
    for owner=1,2 do
        for key,bucket in pairs(state.spatialIndex.buckets[owner]) do
            for id,e in pairs(bucket) do
                ensure(byId[id]==e and e.alive,prefix.."orphan spatial member "..id)
                ensure(e._spatialKey==key and e._spatialOwner==owner,
                    prefix.."spatial reverse pointer "..id)
                ensure(not seenBucket[id],prefix.."duplicate bucket membership "..id)
                seenBucket[id]=true
            end
        end
    end
    for id,e in pairs(byId) do
        if e.alive then
            ensure(seenBucket[id],prefix.."missing indexed entity "..id)
        end
    end
end

-- Use a few markedly different card mixes. Fixed seeds and side swapping
-- expose spawn/death/teleport/spell/summon and mirror-order interactions.
local decks={
    Bot.defaultDeck(),
    {"skeleton","iron_golem","bat_swarm","creeper","slime","witch","spider","wolf"},
    {"evoker","enderman","nether_portal","magma_cube",
        "pillager_outpost","falling_anvil","blaze","villager"},
    {"endermite","zombie","arrows","cannon",
        "snow_golem","wither_skeleton","wolf","spider"},
}
local originalUpdate=Game.update
local inspected=0
Game.update=function(state,dt)
    originalUpdate(state,dt)
    ticks=ticks+1
    if ticks%17==0 and state.phase=="battle" and not state.entitiesDirty then
        assertState(state,state.__auditSeed or 0)
        inspected=inspected+1
    end
end

for i=1,8 do
    local seed=97300+i
    local a=decks[(i%4)+1]
    local b=decks[((i+1)%4)+1]
    local s=Runner.run(a,b,{
        gameplaySeed=seed,
        botOrderOffset=i%2,
        configure=function(state,bot1,bot2)
            state.__auditSeed=seed
            if i%3==0 then
                Bot.setDifficulty(bot1,"hard")
                Bot.setDifficulty(bot2,"hard")
            end
        end,
    })
    ensure(s.phase=="result","seed "..seed.." did not terminate")
    matches=matches+1
end
Game.update=originalUpdate
ensure(inspected>100,"Not enough live battle states inspected")
print(("Core invariant stress passed: %d matches, %d ticks, %d snapshots, %d assertions")
    :format(matches,ticks,inspected,checks))

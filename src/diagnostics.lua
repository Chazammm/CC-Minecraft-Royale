-- Read-only audit helpers. No gameplay rules are implemented here.
local util=require('src.util')
local arena=require('src.arena')
local config=require('config')
local diagnostics={}

-- Capture the definition graph without replacing any original table. This
-- preserves references held by Game/Bot while restoring failed test fixtures.
function diagnostics.restorePoint(...)
    local seen,records={},{}
    local function visit(value)
        if type(value)~='table' or seen[value] then return end
        seen[value]=true
        local fields={};records[#records+1]={object=value,fields=fields}
        for key,child in pairs(value) do
            fields[key]=child;visit(key);visit(child)
        end
    end
    for i=1,select('#',...) do visit(select(i,...)) end
    return function()
        for _,record in ipairs(records) do
            for key in pairs(record.object) do record.object[key]=nil end
            for key,value in pairs(record.fields) do record.object[key]=value end
        end
    end
end

local visualFields={damageFlash=true,criticalPulseTimer=true,emeraldPulseTimer=true,
    lastBeamChargeBeforeHit=true,lastBeamChargeAfterHit=true}
local function serialize(value)
    local kind=type(value)
    if kind=='number' then return ('%.17g'):format(value) end
    if kind=='string' then return ('%q'):format(value) end
    if kind~='table' then return tostring(value) end
    local keys={}
    for key in pairs(value) do
        if not visualFields[key] then keys[#keys+1]=key end
    end
    table.sort(keys,function(a,b)
        if type(a)==type(b) then return a<b end
        return type(a)<type(b)
    end)
    local parts={'{'}
    for _,key in ipairs(keys) do
        parts[#parts+1]=serialize(key)..'='..serialize(value[key])..';'
    end
    parts[#parts+1]='}';return table.concat(parts)
end

-- Full deterministic combat snapshot, rather than a lossy winner-only oracle.
-- Cosmetic effects/timers and private rendering caches are deliberately absent.
function diagnostics.combatSnapshot(state)
    local snapshot={}
    for _,key in ipairs({'phase','countdown','timeLeft','overtime','tiebreaker',
        'winner','resultReason','nextEntityId','combatTick','entities','projectiles',
        'pendingSpells','stats','ruleset','destroyedSideTowers','emeraldBoost'}) do
        snapshot[key]=state[key]
    end
    snapshot.players={}
    for owner=1,2 do
        local player=state.players[owner];local copy={}
        for _,key in ipairs({'id','emeralds','maxEmeralds','deck','hand','queue',
            'evolutionCardId','evolutionProgress','towersDestroyed'}) do copy[key]=player[key] end
        snapshot.players[owner]=copy
    end
    return serialize(snapshot)
end

function diagnostics.assertState(state,context)
    local prefix=tostring(context or 'state audit')..': '
    local function check(ok,message) assert(ok,prefix..message) end
    local function finite(value,label) check(util.isFiniteNumber(value),'nonfinite '..label) end
    local seen,live,counts={},{},{0,0}
    for _,entity in ipairs(state.entities) do
        check(type(entity.id)=='number' and entity.id>0
            and entity.id==math.floor(entity.id) and not seen[entity.id],'invalid/duplicate entity ID')
        seen[entity.id]=entity
        check(entity.owner==1 or entity.owner==2,'invalid entity owner')
        for _,key in ipairs({'x','y','hp','maxHp'}) do finite(entity[key],key..' id='..entity.id) end
        check(entity.x>=0 and entity.x<=config.ARENA.width
            and entity.y>=0 and entity.y<=config.ARENA.height,'entity outside arena')
        check(entity.maxHp>0 and entity.hp>=0 and entity.hp<=entity.maxHp+1e-8,'HP bounds')
        if entity.alive then
            check(state.phase=='result' or entity.hp>0,'live combat entity has zero HP')
            if state.phase=='battle' then
                check(arena.isWalkable(entity,entity.x,entity.y),'live entity on illegal terrain')
            end
            live[entity.id]=entity;counts[entity.owner]=counts[entity.owner]+1
            check(state.entityById[entity.id]==entity,'broken ID index')
            local buckets=state.spatialIndex and state.spatialIndex.buckets[entity.owner]
            local bucket=buckets and buckets[entity._spatialKey]
            check(bucket and bucket[entity.id]==entity and entity._spatialOwner==entity.owner,
                'broken spatial index')
        end
        check(state.nextEntityId>entity.id,'nextEntityId reused')
    end
    for id,entity in pairs(state.entityById) do
        check(seen[id]==entity,'orphan ID lookup')
    end
    for owner=1,2 do
        local indexed={};local count=0
        for _,entity in ipairs(state.entitiesByOwner[owner]) do
            check(entity.owner==owner and seen[entity.id]==entity,'orphan owner index')
            if entity.alive then
                check(not indexed[entity.id],'duplicate owner index')
                indexed[entity.id]=true;count=count+1
            end
        end
        check(count==counts[owner],'missing owner index')
        local spatialSeen={}
        for key,bucket in pairs(state.spatialIndex.buckets[owner]) do
            for id,entity in pairs(bucket) do
                check(live[id]==entity and entity.owner==owner,'orphan spatial entry')
                check(not spatialSeen[id] and entity._spatialKey==key,'duplicate/stale spatial key')
                spatialSeen[id]=true
            end
        end
        local player=state.players[owner]
        finite(player.emeralds,'Emeralds');finite(player.maxEmeralds,'maximum Emeralds')
        check(player.emeralds>=0 and player.emeralds<=player.maxEmeralds+1e-8,'Emerald bounds')
        finite(player.evolutionProgress or 0,'Evolution progress')
        check((player.evolutionProgress or 0)>=0,'negative Evolution progress')
    end
    return true
end

return diagnostics

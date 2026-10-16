-- Host-only read-only observer around the actual production CLI adapter.
-- Usage: lua scripts/audit_observed_cli.lua simulate.lua report.txt REV 100 mixed SEED
-- Does not replace combat, bot, RNG, placement or report aggregation logic.
colors={white=1,orange=2,magenta=4,lightBlue=8,yellow=16,lime=32,pink=64,
    gray=128,lightGray=256,cyan=512,purple=1024,blue=2048,brown=4096,
    green=8192,red=16384,black=32768}
local Runner=require('src.headless_match')
local diagnostics=require('src.diagnostics')
local cards=require('src.cards')
local util=require('src.util')
local original=Runner.run
local matches,ticks,maxEntities,maxProjectiles=0,0,0,0
local age={}
local plays={}
local function near(a,b,label)
    assert(math.abs(a-b)<1e-6,label..' accounting mismatch')
end
Runner.run=function(a,b,options)
    options=options or {}
    local previous=options.onTick
    age={}
    options.onTick=function(state,...)
        diagnostics.assertState(state,'observed production CLI')
        ticks=ticks+1
        maxEntities=math.max(maxEntities,#state.entities)
        maxProjectiles=math.max(maxProjectiles,#state.projectiles)
        local current={}
        for _,projectile in ipairs(state.projectiles) do
            local lifetime=(age[projectile] or 0)+(options.dt or .1)
            assert(lifetime<30,'Projectile survived 30 simulation seconds')
            current[projectile]=lifetime
        end
        age=current
        for owner=1,2 do
            local p=state.players[owner]
            assert(cards.isValidDeck(p.deck),'Invalid live deck')
            local seen={};local count=0
            for _,part in ipairs({p.hand,p.queue}) do
                for _,id in ipairs(part) do
                    assert(cards.isSelectable(id) and not seen[id],'Invalid hand/queue card')
                    seen[id]=true;count=count+1
                end
            end
            assert(count==8 and #p.hand==4 and #p.queue==4,'Card cycle lost/duplicated a card')
            for _,id in ipairs(p.deck) do assert(seen[id],'Deck/cycle mismatch') end
            if state.stats then
                local stats=state.stats.players[owner]
                for _,field in ipairs({'cardsPlayed','emeraldSpent','unitDamage','towerDamage'}) do
                    assert(util.isFiniteNumber(stats[field]) and stats[field]>=0,'Invalid '..field)
                end
            end
        end
        if previous then previous(state,...) end
    end
    local state,first,second,total=original(a,b,options)
    matches=matches+1
    assert(state.phase=='result' and (state.winner==nil or state.winner==1 or state.winner==2),
        'Invalid terminal result')
    for owner=1,2 do
        local stats=state.stats.players[owner]
        local sums={plays=0,emeraldSpent=0,unitDamage=0,towerDamage=0}
        for id,record in pairs(stats.cards) do
            plays[id]=(plays[id] or 0)+(record.plays or 0)
            for field in pairs(sums) do sums[field]=sums[field]+(record[field] or 0) end
        end
        near(sums.plays,stats.cardsPlayed,'plays')
        near(sums.emeraldSpent,stats.emeraldSpent,'spending')
        -- Crown Tower damage is intentionally tracked under its own source
        -- IDs as well, so all source records participate in these sums.
        near(sums.unitDamage,stats.unitDamage,'unit damage')
        near(sums.towerDamage,stats.towerDamage,'tower damage')
    end
    age={}
    return state,first,second,total
end
local ok,err=pcall(dofile,'scripts/audit_cli_host.lua')
Runner.run=original
if not ok then error(err,0) end
print(('OBSERVED_CLI|matches=%d|ticks=%d|max_entities=%d|max_projectiles=%d'):format(
    matches,ticks,maxEntities,maxProjectiles))
local ids={};for id in pairs(plays) do ids[#ids+1]=id end;table.sort(ids)
for _,id in ipairs(ids) do print(('OBSERVED_PLAYS|%s|%d'):format(id,plays[id])) end

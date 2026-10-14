-- Independent regressions for the complete-system audit. Exercise the real
-- engine; terminal-state, owner mirroring and rejected-input contracts are
-- asserted independently of the implementation under review.
colors={white=1,orange=2,magenta=4,lightBlue=8,yellow=16,lime=32,pink=64,
    gray=128,lightGray=256,cyan=512,purple=1024,blue=2048,brown=4096,
    green=8192,red=16384,black=32768}
package.path='./?.lua;./?/init.lua;'..package.path
local Game=require('src.game')
local cards=require('src.cards')
local arena=require('src.arena')
local config=require('config')
local Runner=require('src.headless_match')
local cases,failures,checks=0,0,0
local function check(ok,message)
    checks=checks+1;assert(ok,message)
end
local function near(a,b,label)
    check(math.abs(a-b)<1e-8,label..': '..tostring(a)..' vs '..tostring(b))
end
local function case(label,fn)
    cases=cases+1;local ok,err=pcall(fn)
    if not ok then failures=failures+1;print('FAIL '..label..': '..tostring(err)) end
end
local function admin()
    local s=Game.new(nil,{headlessSimulation=true})
    Game.debugLoadScenario(s,'empty');Game.debugSetPaused(s,false)
    return s
end
local function cohort(s,source,kind)
    local out={}
    for _,e in ipairs(s.entities) do
        if e.alive and e.sourceCardId==source and (not kind or e.kind==kind) then
            out[#out+1]=e
        end
    end
    return out
end
local function mirror(a,b)
    check(#a==#b and #a>0,'Mirrored spawn counts differ')
    for i,e in ipairs(a) do
        local other=b[i]
        near(e.x+other.x,100,'Mirrored spawn X')
        near(e.y+other.y,160,'Mirrored spawn Y')
        near(e.hp,other.hp,'Mirrored spawn HP')
        check(arena.isWalkable(e,e.x,e.y),'P1 spawn not walkable')
        check(arena.isWalkable(other,other.x,other.y),'P2 spawn not walkable')
    end
end

case('pending winning spells stop later aura and combat stages',function()
    local s=Game.new(nil,{headlessSimulation=true});Game.startHeadlessBattle(s,0.1)
    local king
    for _,e in ipairs(s.entities) do if e.owner==2 and e.towerType=='king' then king=e end end
    king.hp=1;s.globalMovementAuraDirty=true
    local spell=cards.get('falling_anvil').spell
    s.pendingSpells={{kind='falling_anvil',owner=1,cardId='falling_anvil',
        x=king.x,y=king.y,remaining=0.1,spell=spell}}
    local before=s.combatTick
    Game.update(s,0.1)
    check(s.phase=='result' and s.winner==1,'Delayed Anvil did not finish match')
    check(s.globalMovementAuraDirty==true,'Finished spell batch reconciled subsequent auras')
    check(s.combatTick==before,'Finished spell batch advanced subsequent combat stage')
end)
case('terminal projectile state freezes after King destruction',function()
    local s=Game.new(nil,{headlessSimulation=true})
    Game.startHeadlessBattle(s,0.1)
    local king,princess
    for _,e in ipairs(s.entities) do
        e.passive=true
        if e.owner==2 and e.towerType=='king' then king=e end
        if e.owner==2 and e.towerType=='princess' then princess=e end
    end
    king.hp=1;local before=princess.hp
    s.projectiles={
        {x=king.x,y=king.y,targetId=king.id,owner=1,damage=2,speed=50,alive=true,sourceCardId='skeleton'},
        {x=princess.x,y=princess.y,targetId=princess.id,owner=1,damage=100,speed=50,alive=true,sourceCardId='skeleton'},
    }
    Game.update(s,0.1)
    check(s.phase=='result' and s.winner==1,'Winning projectile did not finish match')
    near(princess.hp,before,'Later projectile damaged a result-state tower')
    near(s.stats.players[1].towerDamage,1,'Post-win damage corrupted telemetry')
    local elapsed=s.stats.elapsed
    for _=1,10 do Game.update(s,0.1) end
    near(s.stats.elapsed,elapsed,'Result clock advanced')
    near(princess.hp,before,'Result update mutated tower')
end)

case('three-bat deployment mirrors corresponding bodies',function()
    local a,b=admin(),admin()
    check(Game.debugSpawnCard(a,1,'bat_swarm',25,110),'P1 bats')
    check(Game.debugSpawnCard(b,2,'bat_swarm',75,50),'P2 bats')
    mirror(cohort(a,'bat_swarm'),cohort(b,'bat_swarm'))
end)

for _,id in ipairs({'witch','evoker','nether_portal','evo:nether_portal'}) do
    case('mirrored periodic summons '..id,function()
        local a,b=admin(),admin()
        check(Game.debugSpawnCard(a,1,id,25,110),'P1 summoner')
        check(Game.debugSpawnCard(b,2,id,75,50),'P2 summoner')
        local source=id:gsub('^evo:','')
        for _,s in ipairs({a,b}) do
            local e=cohort(s,source)[1];e.passive=true;e.periodicSpawnTimer=0
            Game.update(s,0.1)
        end
        mirror(cohort(a,source,'unit'),cohort(b,source,'unit'))
    end)
end

for _,id in ipairs({'slime','magma_cube'}) do
    case('mirrored death splits '..id,function()
        local a,b=admin(),admin()
        check(Game.debugSpawnCard(a,1,id,25,110),'P1 split parent')
        check(Game.debugSpawnCard(b,2,id,75,50),'P2 split parent')
        check(Game.debugKillEntity(a,cohort(a,id)[1]),'P1 parent death')
        check(Game.debugKillEntity(b,cohort(b,id)[1]),'P2 parent death')
        mirror(cohort(a,id),cohort(b,id))
    end)
end

case('nonfinite delta is rejected without match state mutation',function()
    for _,dt in ipairs({0/0,math.huge,-math.huge,'invalid'}) do
        local s=admin();local previousTick=s.combatTick
        local ok=pcall(Game.update,s,dt)
        check(not ok,'Malformed dt must raise a diagnostic error')
        check(s.combatTick==previousTick,'Malformed dt changed combat tick')
    end
end)

case('malformed admin spawn is rejected before indexing',function()
    for _,v in ipairs({0/0,math.huge,-math.huge,'invalid',false}) do
        local s=admin();local nextId=s.nextEntityId
        local ok,result=pcall(Game.debugSpawnCard,s,1,'zombie',v,110)
        check(ok and result==false,'Malformed spawn must return false')
        check(#s.entities==0 and s.nextEntityId==nextId,'Rejected spawn mutated entity state')
    end
    local s=admin()
    local ok,result=pcall(Game.debugSpawnCard,s,1,'zombie',nil,110)
    check(ok and result==false,'Nil coordinate must return false')
end)

case('invalid headless dt preserves lobby',function()
    local s=Game.new(nil,{headlessSimulation=true})
    local oldStats=s.stats
    local ok=Game.startHeadlessBattle(s,0)
    check(ok==false,'Zero dt must be rejected')
    check(s.phase=='lobby' and s.stats==oldStats,'Rejected headless start reset the lobby')
end)

case('zero countdown preserves one live transition tick',function()
    local previous=config.MATCH.countdown;config.MATCH.countdown=0
    local s=Game.new(nil,{headlessSimulation=true})
    local ok,ticks=Game.startHeadlessBattle(s,0.1)
    config.MATCH.countdown=previous
    check(ok and ticks==1,'Headless skipped ticks differ from zero-countdown live transition')
end)

case('headless suppresses sound callbacks',function()
    local calls=0
    local s=Game.new(function() calls=calls+1 end,{headlessSimulation=true})
    Game.startHeadlessBattle(s,0.1)
    check(calls==0,'Headless start invoked a live sound callback')
end)

case('technical headless timeout is an error rather than a draw',function()
    local saved=Game.update
    Game.update=function() end -- fault injection: an engine loop stops progressing
    local ok,result=pcall(Runner.run,cards.defaultDeck(),cards.defaultDeck(),{})
    Game.update=saved
    check(not ok and tostring(result):find('TIMEOUT',1,true),
        'A frozen engine was returned as a statistically valid draw')
end)

case('fractional affordability tolerance never creates negative Emeralds',function()
    local s=Game.new(nil,{headlessSimulation=true})
    Game.startHeadlessBattle(s,0.1)
    local p=s.players[1];p.emeralds=cards.get(p.hand[1]).cost-0.00005
    local played=Game.playCardFromSlot(s,1,1,25,110)
    check(played and p.emeralds>=0,'Allowed rounded cost created negative Emeralds')
end)

case('admin instant spell reconciles edited entity position',function()
    local s=admin()
    Game.debugSpawnCard(s,2,'zombie',10,50)
    local target=cohort(s,'zombie')[1];target.x=90;target.y=50
    local before=target.hp
    check(Game.debugSpawnCard(s,1,'arrows',90,50),'Admin Arrow cast')
    near(before-target.hp,cards.get('arrows').spell.damage,'Admin spell read stale Spatial bucket')
end)

case('bot opening placement mirrors both axes',function()
    local Bot=require('src.bot')
    local positions={}
    for owner=1,2 do
        local s=Game.new(nil,{headlessSimulation=true})
        local bot=Bot.new(owner);Bot.prepare(bot,s);Game.startHeadlessBattle(s,0.1)
        bot.enabled=true;bot.thinkTimer=0;s.players[owner].emeralds=10
        Bot.update(bot,s,0.1)
        check(bot.actions==1,'Bot did not produce an opening play')
        positions[owner]={bot.lastX,bot.lastY,bot.lastAction}
    end
    check(positions[1][3]==positions[2][3],'Identical bot openings choose different cards')
    near(positions[1][1]+positions[2][1],100,'Bot opening X orientation')
    near(positions[1][2]+positions[2][2],160,'Bot opening Y orientation')
end)

case('exact bridge-distance tie mirrors owner-relative route',function()
    local x1,y1=arena.navigationPoint({owner=1,x=50,y=120},{x=50,y=40})
    local x2,y2=arena.navigationPoint({owner=2,x=50,y=40},{x=50,y=120})
    near(x1+x2,100,'Equal-cost bridge X')
    near(y1+y2,160,'Equal-cost bridge Y')
end)

case('centre-lane troop objective mirrors both players',function()
    local targets={}
    for owner=1,2 do
        local s=admin();Game.debugLoadScenario(s,'princess');Game.debugSetPaused(s,false)
        for _,e in ipairs(s.entities) do e.passive=true end
        Game.debugSpawnCard(s,owner,'iron_golem',50,owner==1 and 120 or 40)
        local unit=cohort(s,'iron_golem')[1];unit.moveSpeed=0
        Game.update(s,0.1)
        targets[owner]=s.entityById[unit.targetId]
    end
    check(targets[1] and targets[2],'No centre-lane objective')
    near(targets[1].x+targets[2].x,100,'Centre-lane tower X')
end)

case('centre-lane bot counterpush mirrors both players',function()
    local Bot=require('src.bot');local lanes={}
    for owner=1,2 do
        local s=admin();Game.debugSpawnCard(s,owner,'iron_golem',50,owner==1 and 100 or 60)
        lanes[owner]=Bot.debugCounterpushLane(s,owner)
    end
    check(lanes[1] and lanes[2],'No centre counterpush')
    near(lanes[1]+lanes[2],100,'Centre counterpush X')
end)

case('ground-water eligibility agrees with the actual legal bank point',function()
    for owner=1,2 do
        local s=admin()
        local ty=owner==1 and 76.5 or 83.5
        local ay=owner==1 and 70 or 90
        Game.debugSpawnCard(s,3-owner,'guardian',50,ty)
        local guardian=s.entities[1];guardian.passive=true
        Game.debugSpawnCard(s,owner,'zombie',50,ay)
        local zombie=s.entities[2]
        Game.update(s,0.1)
        check(zombie.targetId==nil,'Zombie locked a water target beyond actual walkable reach')
        local gx,gy=arena.groundReachPoint(zombie,guardian)
        near(arena.distanceToGroundReach(guardian.x,guardian.y),
            math.sqrt((gx-guardian.x)^2+(gy-guardian.y)^2),'Reach/navigation geometry disagreement')
    end
end)

case('malformed slow factor/duration is rejected without effect-table pollution',function()
    for _,value in ipairs({0/0,math.huge,-math.huge}) do
        local s=admin();Game.debugSpawnCard(s,1,'zombie',50,110)
        local e=s.entities[1]
        check(Game.debugApplySlow(s,e,value,2)==false,'Nonfinite slow factor accepted')
        check(Game.debugApplySlow(s,e,0.5,value)==false,'Nonfinite slow duration accepted')
        check(#e.slowEffects==0,'Rejected slow changed paired-effect state')
    end
end)

check(failures==0,('%d/%d full-system regressions failed'):format(failures,cases))
print(('System audit regressions passed: %d cases, %d checks'):format(cases,checks))

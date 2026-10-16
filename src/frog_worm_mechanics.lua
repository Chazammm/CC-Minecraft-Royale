-- Actual-engine regressions shared by mechanics_test and host CI.
local Game=require('src.game')
local cards=require('src.cards')
local arena=require('src.arena')
local util=require('src.util')
local Bot=require('src.bot')
local spatial=require('src.spatial')
local diagnostics=require('src.diagnostics')
local suite={cases={}}
local function add(id,title,run) suite.cases[#suite.cases+1]={id='frog_worm_'..id,title=title,run=run} end
local function near(a,b,label) assert(math.abs(a-b)<1e-7,(label or 'value')..': '..tostring(a)..' vs '..tostring(b)) end
local function sandbox(live)
    local s=Game.new(nil,{headlessSimulation=not live});Game.debugLoadScenario(s,'empty')
    Game.debugSetPaused(s,false);return s
end
local function step(s,seconds,dt)
    dt=dt or .1;local time=0
    while time<seconds-1e-9 do local d=math.min(dt,seconds-time);Game.update(s,d);time=time+d end
end
local function spawn(s,owner,id,x,y,frozen)
    assert(Game.debugSpawnCard(s,owner,id,x,y));local e=s.entities[#s.entities]
    if frozen then e.passive=true;e.periodicSpawn=nil;e.remainingLifetime=nil end
    return e
end
local function activeWorm(s,owner,x,y)
    local e=spawn(s,owner,'nether_worm',x,y)
    e.emergenceRemaining=nil;e.burrowState='ACTIVE';e.wormOpenerRemaining=2
    return e
end
local function playWorm(s,owner,x,y)
    local p=s.players[owner];p.hand[1]='nether_worm';p.queue={'zombie','skeleton','wolf','arrows'}
    return Game.playCardFromSlot(s,owner,1,x,y)
end
local function awaitHook(s,frog,dt)
    Game.update(s,dt);assert(frog.tongueWindup,'Hook did not start')
    for _=1,20 do if not frog.tongueWindup then return end;Game.update(s,dt) end
    error('Hook did not finish')
end
add('definitions','Only two new selectable cards with owner-approved stats',function()
    local f,w=cards.get('king_frog'),cards.get('nether_worm')
    assert(#cards.list==27 and f.cost==3 and w.cost==3)
    near(f.unit.maxHp,550);near(w.unit.maxHp,350)
    near(f.unit.damage,40);near(f.unit.attackCooldown,1.4);near(f.unit.moveSpeed,5)
    near(w.unit.damage,95);near(w.unit.attackCooldown,1.2);near(w.unit.moveSpeed,9)
    assert(w.placement=='burrow' and not cards.get('netherite_crab') and not cards.get('ore_centipede'))
    assert(not cards.hasEvolution('king_frog') and not cards.hasEvolution('nether_worm') and cards.validate())
end)
for _,ownerValue in ipairs({1,2}) do
 local owner=ownerValue;local enemy=3-owner
 local function xy(x,y) if owner==2 then return 100-x,160-y end return x,y end
 local function own(s,id,x,y,frozen)local a,b=xy(x,y);return spawn(s,owner,id,a,b,frozen)end
 local function foe(s,id,x,y,frozen)local a,b=xy(x,y);return spawn(s,enemy,id,a,b,frozen)end
 local suffix='_p'..owner
 add('hook_melee'..suffix,'Hook deals zero, reaches melee, then ordinary 40-damage attacks',function()
    for _,dt in ipairs({.05,.1,.25}) do
        local s=sandbox();local f=own(s,'king_frog',25,110)
        local target=foe(s,'zombie',35,110,true);local hp=target.hp
        awaitHook(s,f,dt)
        near(target.hp,hp,'Hook damage');near(util.distance(f.x,f.y,target.x,target.y),2.5,'Hook reach')
        assert(f.lockedTargetId==target.id and f.tongueCooldownLeft>0)
        Game.update(s,dt);near(target.hp,hp-40,'Follow-up melee')
        Game.update(s,dt);near(target.hp,hp-40,'Extra free attack')
        assert(arena.isWalkable(target,target.x,target.y))
        local ids={}
        spatial.forEachInBounds(s,enemy,target.x-.01,target.y-.01,target.x+.01,target.y+.01,
            function(candidate) if candidate.id==target.id then ids[#ids+1]=candidate.id end end)
        assert(#ids==1 and ids[1]==target.id,'Stale displacement bucket')
    end
 end)
 add('hook_heavy_bank'..suffix,'Heavy ground troops and stationary economic units can be pulled',function()
    for _,id in ipairs({'iron_golem','minoshroom','villager','evo:villager'}) do
        local s=sandbox();local f=own(s,'king_frog',25,110)
        local t=foe(s,id,35,110,id~='villager' and id~='evo:villager')
        local hp,boost,lifetime=t.hp,s.emeraldBoost[enemy],t.remainingLifetime
        awaitHook(s,f,.1);near(t.hp,hp)
        near(util.distance(f.x,f.y,t.x,t.y),2.5)
        near(s.emeraldBoost[enemy],boost,'Hook changed income')
        if lifetime then assert(t.remainingLifetime<lifetime and t.remainingLifetime>lifetime-1,'Hook renewed lifetime') end
    end
 end)
 add('hook_filters'..suffix,'Tongue excludes buildings, air, water and allies',function()
    for _,id in ipairs({'cannon','blaze','zombie'}) do
        local s=sandbox();local f=own(s,'king_frog',25,110);f.moveSpeed=0
        local t=foe(s,id,35,110,true);local x,y=t.x,t.y
        if id=='zombie' then t.waterOnly=true end
        step(s,.7);assert(not f.tongueWindup);near(t.x,x);near(t.y,y)
    end
    local s=sandbox();local f=own(s,'king_frog',25,110);own(s,'zombie',35,110,true)
    step(s,.5);assert(not f.tongueWindup)
 end)
 add('hook_terrain'..suffix,'Pull sweeps cannot cross open water or bypass melee range',function()
    local s=sandbox();local f=own(s,'king_frog',21,80);f.moveSpeed=0
    local t=foe(s,'zombie',15,73,true);local hp=t.hp
    awaitHook(s,f,.1);assert(arena.isWalkable(t,t.x,t.y),'Pulled into river')
    assert(util.distance(f.x,f.y,t.x,t.y)>f.attackRange,'Teleported across terrain')
    step(s,.6);near(t.hp,hp,'Ranged damage after blocked pull')
 end)
 add('hook_cancel_clock'..suffix,'Dead targets cancel hooks; pulling never resets melee cooldown',function()
    local s=sandbox();local f=own(s,'king_frog',25,110)
    local t=foe(s,'zombie',35,110,true);Game.update(s,.1)
    assert(f.tongueWindup);Game.debugKillEntity(s,t);Game.update(s,.1)
    assert(not f.tongueWindup and f.tongueCooldownLeft>0)
    local next=foe(s,'zombie',35,110,true);f.tongueCooldownLeft=0;f.attackCooldownLeft=2
    awaitHook(s,f,.1);local hp=next.hp;assert(f.attackCooldownLeft>1)
    Game.update(s,.1);near(next.hp,hp,'Hook reset attack clock')
 end)
 add('multi_hook'..suffix,'Two frogs cannot drag one victim twice in the same tick',function()
    local s=sandbox();local a=own(s,'king_frog',25,110);local b=own(s,'king_frog',45,110)
    local t=foe(s,'zombie',35,110,true);local x,y=t.x,t.y
    Game.update(s,.1);assert(a.tongueWindup and b.tongueWindup)
    while a.tongueWindup or b.tongueWindup do Game.update(s,.1) end
    assert(util.distance(x,y,t.x,t.y)<=7.5+1e-8,'Same-tick pull chain')
 end)
 add('placement'..suffix,'Worm alone deploys behind either enemy tower and on bridges',function()
    local s=sandbox();local x,y=xy(42,4)
    assert(arena.placementAllowed(owner,x,y,'burrow',s))
    assert(not arena.placementAllowed(owner,x,y,nil,s),'Ordinary placement changed')
    local bx,by=xy(27,80);assert(arena.placementAllowed(owner,bx,by,'burrow',s))
    local wx,wy=xy(50,80);assert(not arena.placementAllowed(owner,wx,wy,'burrow',s))
    for _,pair in ipairs({{0,4},{42,0},{0/0,10},{math.huge,10}}) do
        assert(not arena.placementAllowed(owner,pair[1],pair[2],'burrow',s))
    end
    s.players[owner].emeralds=3;assert(playWorm(s,owner,x,y));near(s.players[owner].emeralds,0)
    assert(#s.entities==0 and #s.pendingDeployments==1,'Warning created a hidden unit')
    local before=s.players[owner].emeralds
    assert(not playWorm(s,owner,wx,wy));near(s.players[owner].emeralds,before)
 end)
 add('deploy_timing'..suffix,'Full warning then exposed emergence; no early bite at any supported dt',function()
    for _,dt in ipairs({.05,.1,.25}) do
        local s=sandbox();local t=foe(s,'zombie',26,110,true)
        local x,y=xy(25,110);assert(playWorm(s,owner,x,y))
        local time=0;local firstBite=nil
        while time<2.8 do
            Game.update(s,dt);time=time+dt
            if time<1.4-1e-8 then assert(#s.entities==1,'Early spawn') end
            if t.hp<t.maxHp then firstBite=time;break end
        end
        assert(firstBite and firstBite>=2-1e-8 and firstBite<=2+2*dt+1e-8,'Bad deployment clock '..tostring(firstBite))
        assert(#s.pendingDeployments==0 and #s.entities==2)
        near(t.hp,t.maxHp-180,'Ambush first hit')
    end
 end)
 add('exposed'..suffix,'Emerging Worm can be hit by troops and spells before it attacks',function()
    local s=sandbox();local x,y=xy(25,110);assert(playWorm(s,owner,x,y));step(s,1.4)
    local w=s.entities[1];assert(w and w.emergenceRemaining and w.alive)
    local t=foe(s,'zombie',26,110);local hp=t.hp
    Game.update(s,.1);assert(w.hp<350,'Emergence immune to troop')
    near(t.hp,hp,'Emerging worm attacked')
    local ax,ay=xy(25,110);Game.debugSpawnCard(s,enemy,'arrows',ax,ay)
    assert(w.hp<350-185,'Emergence immune to spell')
    Game.debugSpawnCard(s,enemy,'arrows',ax,ay);assert(not w.alive,'Lethal spell did not kill emerging worm')
 end)
 add('damage_matrix'..suffix,'Full unit/building damage, half damage to both tower types',function()
    for _,id in ipairs({'zombie','villager','evo:villager','cannon','pillager_outpost','nether_portal'}) do
        local s=sandbox();local x,y=xy(25,110);local w=activeWorm(s,owner,x,y);w.wormOpenerUsed=true
        local t=foe(s,id,26,110,true);t.periodicSpawn=nil;local hp=t.hp
        Game.update(s,.1);near(t.hp,hp-95,'Normal damage '..id)
    end
    for _,towerType in ipairs({'princess','king'}) do
        local s=sandbox();Game.debugLoadScenario(s,'full');Game.debugSetPaused(s,false);s.phase='battle'
        local t
        for _,e in ipairs(s.entities) do e.passive=true;if e.owner==enemy and e.towerType==towerType then t=e end end
        local w=activeWorm(s,owner,t.x+1,t.y);local hp=t.hp
        Game.update(s,.1);near(t.hp,hp-47.5,'Tower-only damage '..towerType)
        assert(not w.wormOpenerUsed,'Tower consumed troop opener')
        near(s.stats.players[owner].cards.nether_worm.towerDamage,47.5,'Actual tower damage telemetry')
    end
 end)
 add('opener'..suffix,'Ambush bonus is once-only, unit-only and expires',function()
    local s=sandbox();local x,y=xy(25,110);local w=activeWorm(s,owner,x,y)
    local t=foe(s,'zombie',26,110,true);Game.update(s,.1);near(t.hp,343)
    step(s,1.2);near(t.hp,248,'Repeated bonus')
    local exp=sandbox();local ex,ey=xy(25,110);local old=activeWorm(exp,owner,ex,ey);old.moveSpeed=0
    step(exp,2.1);local z=foe(exp,'zombie',26,110,true);Game.update(exp,.1);near(z.hp,428,'Expired bonus')
    local structures=sandbox();local sx,sy=xy(25,110);local a=activeWorm(structures,owner,sx,sy)
    local b=foe(structures,'cannon',26,110,true);Game.update(structures,.1);near(b.hp,b.maxHp-95)
    assert(not a.wormOpenerUsed,'Building consumed troop opener')
 end)
 add('bank_assassination'..suffix,'Real delayed deployment kills Bank in two hits and stops its income',function()
    local s=sandbox();s.phase='battle';s.players[enemy].emeralds=0
    local bank=foe(s,'evo:villager',26,20);local x,y=xy(25,20)
    assert(playWorm(s,owner,x,y));step(s,3.5)
    assert(not bank.alive and #s.pendingDeployments==0,'Bank survived expected two hits')
    near(s.emeraldBoost[enemy],0,'Dead Bank income remained registered')
    local bonus=s.stats.players[enemy].villagerBonus;assert(bonus>0,'Bank never generated income')
    step(s,.5);near(s.stats.players[enemy].villagerBonus,bonus,'Dead Bank kept generating bonus')
    near(s.stats.players[owner].cards.nether_worm.unitDamage,194.25,'Actual Bank damage accounting')
 end)
 add('economy_lock'..suffix,'Worm acquires bank over closer troops without stealing valid locks',function()
    local s=sandbox();local x,y=xy(25,110);local w=activeWorm(s,owner,x,y)
    foe(s,'zombie',26,110,true);local bank=foe(s,'evo:villager',35,110)
    Game.update(s,.1);assert(w.targetId==bank.id,'Did not acquire economic target')
    local other=foe(s,'villager',27,110);Game.update(s,.1)
    assert(w.targetId==bank.id and w.targetId~=other.id,'New unit stole ambush lock')
 end)
 add('refund'..suffix,'Blocked warning refunds once, preserves cycle and records cancellation',function()
    local s=sandbox();s.phase='battle';s.players[owner].emeralds=3
    local x,y=xy(25,110);assert(playWorm(s,owner,x,y));local next=s.players[owner].hand[1]
    own(s,'cannon',25,110,true);step(s,1.5)
    assert(#s.pendingDeployments==0 and s.players[owner].hand[1]==next)
    local record=s.stats.players[owner].cards.nether_worm
    near(record.plays,1);near(record.emeraldSpent,3);near(record.deploymentRefunds,3)
    near(record.cancelledDeployments,1);assert(#s.entities==1,'Blocked worm spawned')
    local refund=record.deploymentRefunds;step(s,.3);near(record.deploymentRefunds,refund,'Duplicate refund')
 end)
 add('correction'..suffix,'Local correction is visible before spawn and never relocates at the last instant',function()
    local s=sandbox();local x,y=xy(25,110);assert(playWorm(s,owner,x,y))
    own(s,'cannon',31,110,true);step(s,1.1)
    local p=s.pendingDeployments[1];assert(p and p.finalized and not p.blocked)
    assert(util.distance(x,y,p.x,p.y)>0 and util.distance(x,y,p.x,p.y)<=4+1e-8)
    local nx,ny=p.x,p.y;step(s,.3);local w=s.entities[#s.entities]
    near(w.x,nx);near(w.y,ny)
    local late=sandbox();assert(playWorm(late,owner,x,y));step(late,1.1)
    own(late,'cannon',25,110,true);step(late,.3);assert(#late.pendingDeployments==0 and #late.entities==1,'Late silent relocation')
 end)
 add('bot_air_defense'..suffix,'Bot does not answer an urgent flying threat with a ground-only ambush',function()
    local s=sandbox();Game.debugLoadScenario(s,'full');Game.debugSetPaused(s,false);s.phase='battle'
    foe(s,'villager',42,20);foe(s,'blaze',25,130)
    local deck={'nether_worm','king_frog','cannon','arrows','zombie','skeleton','wolf','blaze'}
    local bot=Bot.new(owner,deck);Bot.prepare(bot,s);Bot.beginMatch(bot);bot.enabled=true
    s.players[owner].hand={'nether_worm','cannon','arrows','minoshroom'};s.players[owner].emeralds=3
    for _=1,30 do Bot.update(bot,s,.1) end
    assert(#s.pendingDeployments==0 and bot.actions==0,'Bot used ground assassin as air defense')
 end)
 add('bot'..suffix,'Bot chooses legal enemy-half economic ambush positions and really plays the card',function()
    local s=sandbox();s.phase='battle';local bank=foe(s,'evo:villager',42,20)
    local x,y,score=Bot.debugWormTarget(s,owner)
    assert(x and score>0 and arena.placementAllowed(owner,x,y,'burrow',s))
    assert(owner==1 and y<74 or owner==2 and y>86,'Worm candidate clamped to own half')
    assert(util.distance(x,y,bank.x,bank.y)<=7.001)
    local deck={'nether_worm','king_frog','cannon','arrows','zombie','skeleton','wolf','blaze'}
    local bot=Bot.new(owner,deck);Bot.prepare(bot,s);Bot.beginMatch(bot);bot.enabled=true
    s.players[owner].hand={'nether_worm','cannon','arrows','blaze'};s.players[owner].emeralds=3
    for _=1,30 do Bot.update(bot,s,.1);if #s.pendingDeployments>0 then break end end
    assert(#s.pendingDeployments==1 and bot.actions>0,'Bot did not play legal ambush')
 end)
end
add('attack_cadence','New melee cadences preserve fractional progress at all supported dt',function()
 for _,id in ipairs({'king_frog','nether_worm'}) do for _,dt in ipairs({.05,.1,.25}) do
    local s=sandbox();local e=spawn(s,1,id,25,110);e.emergenceRemaining=nil
    e.wormOpenerUsed=true;e.moveSpeed=0
    local t=spawn(s,2,'zombie',26,110,true);t.hp=1000000;t.maxHp=t.hp
    step(s,30,dt)
    local hits=(1000000-t.hp)/e.damage
    local expected=1+(30-dt)/e.attackCooldown
    assert(math.abs(hits-expected)<=1,'Attack cadence drift '..id..' dt='..dt)
 end end
end)
add('cleanup','Finish, rematch, clear and lobby cancel every delayed deployment and hook',function()
 for _,mode in ipairs({'finish','lobby','clear','battle'}) do
    local s=sandbox();assert(playWorm(s,1,25,110))
    local f=spawn(s,1,'king_frog',50,110);spawn(s,2,'zombie',60,110,true)
    Game.update(s,.1);assert(f.tongueWindup)
    if mode=='finish' then Game.finish(s,1,'test')
    elseif mode=='lobby' then Game.resetLobby(s)
    elseif mode=='clear' then Game.debugClearUnits(s)
    else Game.startHeadlessBattle(s,.1) end
    assert(#s.pendingDeployments==0 and not f.tongueWindup,'Uncancelled '..mode)
 end
end)
add('staggered_deployments','Compaction retains a later warning when an earlier one is cancelled',function()
 local s=sandbox();assert(playWorm(s,1,25,110));step(s,.2)
 assert(playWorm(s,1,75,110));spawn(s,1,'cannon',25,110,true)
 step(s,1.2);assert(#s.pendingDeployments==1 and s.pendingDeployments[1].id==2)
 step(s,.2);assert(#s.pendingDeployments==0 and #s.entities==2)
 local worm=s.entities[2];assert(worm.sourceCardId=='nether_worm')
 step(s,2);assert(#s.entities==2,'Duplicate delayed spawn')
end)
add('refund_cap','Refunds credit only actual room in the Emerald cap',function()
 local s=sandbox();s.phase='battle';assert(playWorm(s,1,25,110))
 spawn(s,1,'cannon',25,110,true);s.players[1].emeralds=s.players[1].maxEmeralds
 step(s,1.4);near(s.players[1].emeralds,s.players[1].maxEmeralds)
 near(s.stats.players[1].cards.nether_worm.deploymentRefunds,0)
 near(s.stats.players[1].cards.nether_worm.cancelledDeployments,1)
end)
add('mirrored_ambush','Bot backfield choices mirror exactly with full tower coverage',function()
 local a,b=sandbox(),sandbox()
 for _,s in ipairs({a,b}) do Game.debugLoadScenario(s,'full');Game.debugSetPaused(s,false) end
 spawn(a,2,'evo:villager',42,20);spawn(b,1,'evo:villager',58,140)
 local ax,ay,ascore=Bot.debugWormTarget(a,1);local bx,by,bscore=Bot.debugWormTarget(b,2)
 assert(ax and bx);near(ax+bx,100);near(ay+by,160);near(ascore,bscore)
end)
add('schemas','New mechanic validation rejects malformed data and injected transients',function()
 for _,fault in ipairs({'hook_range','hook_windup','hook_stop','towerMultiplier','burrow_flying','tongueWindup','birthRemainder'}) do
    local restore=diagnostics.restorePoint(cards)
    local f,w=cards.get('king_frog').unit,cards.get('nether_worm').unit
    if fault=='hook_range' then f.tongueHook.range=0/0
    elseif fault=='hook_windup' then f.tongueHook.windup=0
    elseif fault=='hook_stop' then f.tongueHook.stopRange=20
    elseif fault=='towerMultiplier' then w.burrow.towerMultiplier=2
    elseif fault=='burrow_flying' then w.flying=true
    else f[fault]={} end
    local ok=pcall(cards.validate);restore();assert(not ok,'Schema missed '..fault);assert(cards.validate())
 end
end)
function suite.register(runTest)
 for _,entry in ipairs(suite.cases) do local case=entry
    runTest(case.id,case.title,function()case.run();return true,case.title,{}end)
 end
end
return suite

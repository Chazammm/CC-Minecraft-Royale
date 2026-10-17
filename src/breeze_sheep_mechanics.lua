-- Real-engine regressions, also exposed through the installed mechanics CLI.
local Game=require('src.game')
local cards=require('src.cards')
local arena=require('src.arena')
local spatial=require('src.spatial')
local diagnostics=require('src.diagnostics')
local suite={cases={}}
local function add(id,title,run) suite.cases[#suite.cases+1]={id='breeze_sheep_'..id,title=title,run=run} end
local function near(a,b,label) assert(math.abs(a-b)<1e-7,(label or 'value')..': '..tostring(a)..' vs '..tostring(b)) end
local function sandbox()
    local s=Game.new(nil,{headlessSimulation=true});Game.debugLoadScenario(s,'empty')
    Game.debugSetPaused(s,false);return s
end
local function spawn(s,owner,id,x,y,frozen)
    assert(Game.debugSpawnCard(s,owner,id,x,y),'Missing '..id)
    local e=s.entities[#s.entities]
    if frozen then e.passive=true;e.periodicSpawn=nil;e.remainingLifetime=nil end
    return e
end
local function step(s,time,dt)
    dt=dt or .1;local elapsed=0
    while elapsed<time-1e-9 do local d=math.min(dt,time-elapsed);Game.update(s,d);elapsed=elapsed+d end
end
local function shot(s,b,empowered)
    b.passive=false;b.windShotsFired=empowered and 2 or 0;b.attackCooldownLeft=0
    Game.update(s,.01);b.passive=true
    assert(#s.projectiles>0,'No wind projectile')
    return s.projectiles[#s.projectiles]
end
local function land(s)
    for _=1,50 do if #s.projectiles==0 then return end;Game.update(s,.05) end
    error('Wind projectile failed to finish')
end
add('registry','Exactly the two approved new cards; Phantom stays unavailable',function()
    local b,f=cards.get('breeze'),cards.get('adventure_sheep')
    assert(b and f and #cards.list==29 and not cards.get('phantom'))
    assert(cards.isSelectable(b) and cards.isSelectable(f))
    assert(b.cost==3 and f.cost==4 and b.unit.maxHp==320 and f.unit.maxHp==620)
    assert(b.unit.damage==32 and f.unit.damage==82 and f.unit.attackCooldown==1.1)
    assert(not b.unit.flying and not b.unit.canAttackAir and not f.unit.canAttackAir)
    assert(not cards.hasEvolution('breeze') and not cards.hasEvolution('adventure_sheep'))
    assert(cards.validate())
end)
for _,ownerValue in ipairs({1,2}) do
 local owner=ownerValue;local enemy=3-owner;local suffix='_p'..owner
 local function xy(x,y)if owner==2 then return 100-x,160-y end return x,y end
 local function own(s,id,x,y,frozen)local a,b=xy(x,y);return spawn(s,owner,id,a,b,frozen)end
 local function foe(s,id,x,y,frozen)local a,b=xy(x,y);return spawn(s,enemy,id,a,b,frozen)end
 add('third_shot'..suffix,'Only each third released projectile displaces, without bonus damage',function()
    local s=sandbox();local b=own(s,'breeze',25,110);b.moveSpeed=0
    local t=foe(s,'zombie',35,110,true);local hp=t.hp;local x=t.x;local elapsed=0
    while t.hp>hp-96+1e-8 and elapsed<5 do
        Game.update(s,.05);elapsed=elapsed+.05
        if t.hp>hp-96+1e-8 then near(t.x,x,'Early push') end
    end
    near(t.hp,hp-96,'Three hits');near(math.abs(t.x-x),4,'Third push')
    assert(b.windShotsFired==3 and (t.windImmunityRemaining or 0)>0)
    assert(elapsed>=2.8 and elapsed<3.5,'Shot cadence changed')
 end)
 add('shared_immunity'..suffix,'Two Breezes share victim immunity; locks and attack progress survive',function()
    local s=sandbox();local b=own(s,'breeze',25,110);b.moveSpeed=0
    local t=foe(s,'zombie',35,110,true);local target=own(s,'zombie',65,110,true)
    t.lockedTargetId=target.id;t.targetId=target.id;t.attackCooldownLeft=1.6
    shot(s,b,true);local second=own(s,'breeze',25,110);second.moveSpeed=0
    shot(s,second,true);local hp=t.hp;local x=t.x;land(s)
    near(t.hp,hp-64);near(math.abs(t.x-x),4,'Double knockback')
    assert(t.lockedTargetId==nil and t.targetId==nil,'Passive target did not clear ordinary lock')
    -- Repeat with a live, immobile victim: preserve actual committed lock.
    t.passive=false;t.moveSpeed=0;t.lockedTargetId=target.id;t.targetId=target.id;t.attackCooldownLeft=1.6
    local cooldown=t.attackCooldownLeft;shot(s,b,true);land(s)
    assert(t.lockedTargetId==target.id and t.attackCooldownLeft<cooldown,'Wind reset a lock/clock')
    near(math.abs(t.x-x),4,'Immunity failed')
    t.passive=true;t.moveSpeed=7.4;step(s,3.1);shot(s,b,true);land(s)
    near(math.abs(t.x-x),8,'Immunity never expired')
 end)
 add('slow_budget'..suffix,'Impact-time modifiers cap travel to one second; immobile targets stay put',function()
    for _,mode in ipairs({'web','slow','aura','zero'}) do
        local s=sandbox();local b=own(s,'breeze',25,110);b.moveSpeed=0
        local t=foe(s,'iron_golem',35,110,true);local x=t.x
        shot(s,b,true)
        local expected
        if mode=='web' then t.heroWeb={moveFactor=.25,attackFactor=.5};expected=1.05
        elseif mode=='slow' then t.slowEffects={{factor=.2,remaining=3}};t.slowRemaining=3;t.slowFactor=.2;expected=.84
        elseif mode=='aura' then t.globalMoveSpeedFactor=.5;expected=2.1
        else t.moveSpeed=0;expected=0 end
        land(s);near(math.abs(t.x-x),expected,'Move budget '..mode)
        if expected==0 then assert(not t.windImmunityRemaining,'No movement consumed immunity') end
    end
 end)
 add('terrain'..suffix,'River banks and bounds stop a swept push; bridges remain walkable',function()
    for _,case in ipairs({{50,70,50,73},{27,70,27,73},{90,110,98,110}}) do
        local s=sandbox();local b=own(s,'breeze',case[1],case[2]);b.moveSpeed=0
        local t=foe(s,'zombie',case[3],case[4],true)
        local x,y=t.x,t.y;shot(s,b,true);land(s)
        assert(arena.isWalkable(t,t.x,t.y),'Pushed into water or outside arena')
        assert((t.x-x)^2+(t.y-y)^2<=16+1e-8,'Exceeded distance cap')
        if case[1]==50 then assert(math.abs(t.y-y)<2,'Crossed open river') end
        local found=false
        spatial.forEachInBounds(s,enemy,t.x-.01,t.y-.01,t.x+.01,t.y+.01,function(e)if e==t then found=true end end)
        assert(found,'Stale spatial position')
    end
 end)
 add('excluded_targets'..suffix,'Air and water excluded; buildings take normal damage without movement',function()
    for _,id in ipairs({'cannon','villager','blaze','guardian'}) do
        local s=sandbox();local b=own(s,'breeze',25,110);b.moveSpeed=0
        local t
        if id=='guardian' then b.x,b.y=xy(40,72);t=foe(s,id,50,80,true)
        else t=foe(s,id,35,110,true) end
        local x,y,hp=t.x,t.y,t.hp
        if id=='blaze' or id=='guardian' then
            step(s,1);near(t.hp,hp);assert(b.windShotsFired==0)
        else
            shot(s,b,true);land(s);near(t.hp,hp-32);near(t.x,x);near(t.y,y)
        end
    end
 end)
 add('dead_source'..suffix,'Released wind survives source death; dead targets receive no displacement',function()
    local s=sandbox();local b=own(s,'breeze',25,110);b.moveSpeed=0
    local t=foe(s,'zombie',35,110,true);local x=t.x
    shot(s,b,true);Game.debugKillEntity(s,b);land(s);near(math.abs(t.x-x),4)
    local s2=sandbox();local b2=own(s2,'breeze',25,110);b2.moveSpeed=0
    local t2=foe(s2,'zombie',35,110,true);local tx=t2.x
    shot(s2,b2,true);Game.debugKillEntity(s2,t2);land(s2);near(t2.x,tx)
 end)
 add('bridge_choice'..suffix,'Displacement cannot force a committed attacker to switch bridges',function()
    local s=sandbox();local b=own(s,'breeze',45,73);b.moveSpeed=0
    local victim=foe(s,'zombie',49.9,73)
    local objective=own(s,'zombie',50,110,true)
    victim.targetId=objective.id;victim.lockedTargetId=objective.id
    victim.attackRange=100;victim.attackCooldownLeft=100
    local bx=arena.navigationPoint(victim,objective);local x,y=victim.x,victim.y
    shot(s,b,true);land(s)
    near(victim.x,x);near(victim.y,y);near(arena.navigationPoint(victim,objective),bx)
    assert(not victim.windImmunityRemaining,'Blocked push consumed immunity')
    assert(victim.lockedTargetId==objective.id,'Push changed target')
 end)
 add('tower_damage'..suffix,'Wind deals ordinary 32 damage to both crown tower types without displacement',function()
    for _,kind in ipairs({'princess','king'}) do
        local s=sandbox();Game.debugLoadScenario(s,'full');Game.debugSetPaused(s,false)
        local tower
        for _,e in ipairs(s.entities)do e.passive=true
            if e.owner==enemy and e.towerType==kind then tower=e end
        end
        assert(tower);local x,y,hp=tower.x,tower.y,tower.hp
        local b=spawn(s,owner,'breeze',x+10,y);b.moveSpeed=0
        b.targetId=tower.id;b.lockedTargetId=tower.id
        shot(s,b,true);land(s);near(tower.hp,hp-32);near(tower.x,x);near(tower.y,y)
    end
 end)
 add('placement_costs'..suffix,'Both ordinary cards honor own-half placement and emerald costs',function()
    for _,id in ipairs({'breeze','adventure_sheep'}) do
        local s=sandbox();local p=s.players[owner];local card=cards.get(id)
        p.hand[1]=id;p.queue={'zombie','skeleton','wolf','arrows'};p.emeralds=card.cost
        local x,y=xy(25,40)
        assert(not Game.playCardFromSlot(s,owner,1,x,y),'Anywhere placement leaked')
        near(p.emeralds,card.cost);x,y=xy(25,110)
        assert(Game.playCardFromSlot(s,owner,1,x,y));near(p.emeralds,0)
        assert(s.entities[1].sourceCardId==id and s.entities[1].owner==owner)
    end
 end)
 add('sheep_duels'..suffix,'Ordinary melee sheep competes with Zombie and Wither Skeleton in the real engine',function()
    for _,id in ipairs({'zombie','wither_skeleton'}) do for _,dt in ipairs({.05,.1,.25}) do
        local s=sandbox();local f=own(s,'adventure_sheep',25,110)
        local t=foe(s,id,27,110);local time=0
        while f.alive and t.alive and time<20 do Game.update(s,dt);time=time+dt end
        assert(f.alive and not t.alive,'Sheep lost '..id..' at dt='..dt)
        assert(f.hp>0 and f.hp<f.maxHp,'Duel did not exercise incoming damage')
    end end
 end)
 add('sheep_single_target'..suffix,'Sword animation gives exactly one melee hit and cannot hit air or at range',function()
    local s=sandbox();local f=own(s,'adventure_sheep',25,110);f.moveSpeed=0
    local a=foe(s,'zombie',27,110,true);local b=foe(s,'zombie',27,111,true)
    Game.update(s,.1);near((a.maxHp-a.hp)+(b.maxHp-b.hp),82)
    step(s,.8);near((a.maxHp-a.hp)+(b.maxHp-b.hp),82)
    local ranged=sandbox();local sheep=own(ranged,'adventure_sheep',25,110);sheep.moveSpeed=0
    local target=foe(ranged,'zombie',29,110,true);step(ranged,2);near(target.hp,target.maxHp)
    Game.debugKillEntity(ranged,target);local air=foe(ranged,'blaze',26,110,true)
    step(ranged,1);near(air.hp,air.maxHp);assert(#ranged.projectiles==0)
 end)
end
add('schema','Wind validation rejects invalid budgets, cadence and injected runtime counters',function()
    for _,fault in ipairs({'nan','zero','fractional','flying','transient','step'}) do
        local restore=diagnostics.restorePoint(cards);local unit=cards.get('breeze').unit
        if fault=='nan' then unit.windBurst.maxDistance=0/0
        elseif fault=='zero' then unit.windBurst.immunity=0
        elseif fault=='fractional' then unit.windBurst.every=2.5
        elseif fault=='flying' then unit.flying=true
        elseif fault=='step' then unit.windBurst.step=1
        else unit.windShotsFired=2 end
        local ok=pcall(cards.validate);restore();assert(not ok,'Schema missed '..fault)
        assert(cards.validate())
    end
end)
add('negative_control','A broken push implementation is detected by the real third-shot regression',function()
    local rules=require('src.wind_rules');local original=rules.apply
    rules.apply=function()return 0 end
    local control
    for _,case in ipairs(suite.cases)do if case.id=='breeze_sheep_third_shot_p1' then control=case end end
    local ok=pcall(control.run);rules.apply=original
    assert(not ok,'Disabled displacement was not detected')
    control.run()
end)
function suite.register(runTest)
    for _,entry in ipairs(suite.cases)do local case=entry
        runTest(case.id,case.title,function()case.run();return true,case.title,{}end)
    end
end
return suite

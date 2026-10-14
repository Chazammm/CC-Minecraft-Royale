-- Shared real-engine regressions: run in mechanics_test and host CI.
local Game = require('src.game')
local cards = require('src.cards')
local arena = require('src.arena')
local modifiers = require('src.combat_modifiers')
local suite = { cases = {} }
local function add(id, title, run)
    suite.cases[#suite.cases+1] = { id='mob_'..id, title=title, run=run }
end
local function near(a,b,what) assert(math.abs(a-b)<1e-7,(what or 'value')..': '..tostring(a)..' != '..tostring(b)) end
local function sandbox(headless)
    local s=Game.new(nil,{headlessSimulation=headless~=false})
    Game.debugLoadScenario(s,'empty');Game.debugSetPaused(s,false)
    return s
end
local function spawn(s,owner,id,x,y,frozen)
    assert(Game.debugSpawnCard(s,owner,id,x,y),'Spawn '..id)
    local e=s.entities[#s.entities]
    if frozen then e.passive=true;e.periodicSpawn=nil;e.remainingLifetime=nil end
    return e
end
local function dummy(s,owner,x,y,hp)
    local e=spawn(s,owner,'zombie',x,y,true)
    e.hp=hp or 100000;e.maxHp=e.hp
    return e
end
local function step(s,seconds,dt)
    dt=dt or .1;local elapsed=0
    while elapsed<seconds-1e-9 do
        local d=math.min(dt,seconds-elapsed);Game.update(s,d);elapsed=elapsed+d
    end
end
local function primeWeb(s,owner,x,y)
    local spider=spawn(s,owner,'evo:spider',x,y)
    spider.webCooldownLeft=0
    return spider
end

add('stats','Definitions, two-cycle Evo and exact Spider bonuses',function()
    local iron=cards.get('iron_golem').unit
    local rider=cards.get('ravager_rider');assert(rider.cost==5)
    near(rider.unit.damage,iron.damage*2);near(rider.unit.attackCooldown,iron.attackCooldown*2)
    near(rider.unit.secondaryAttack.damage,20);near(rider.unit.secondaryAttack.interval,2)
    assert(cards.get('baby_ender_dragon').cost==5 and cards.get('baby_ender_dragon').unit.flying)
    assert(cards.get('minoshroom').cost==8)
    local base=cards.get('spider');local hero=cards.evolvedCopy('spider')
    near(hero.unit.maxHp,base.unit.maxHp*1.1);near(hero.unit.damage,base.unit.damage*1.02)
    near(hero.unit.attackCooldown,base.unit.attackCooldown/1.02)
    near(hero.unit.moveSpeed,base.unit.moveSpeed);near(hero.cost,base.cost)
    assert(cards.evolutionCycles('spider')==2 and cards.validate())
end)

for _,side in ipairs({1,2}) do
    local owner=side;local enemy=3-owner
    local function xy(x,y) if owner==2 then return 100-x,160-y end return x,y end
    local function at(s,id,x,y,frozen) local a,b=xy(x,y);return spawn(s,owner,id,a,b,frozen) end
    local function foe(s,id,x,y,frozen) local a,b=xy(x,y);return spawn(s,enemy,id,a,b,frozen) end
    local function target(s,x,y,hp) local a,b=xy(x,y);return dummy(s,enemy,a,b,hp) end
    local suffix='_p'..owner
    add('rider_dual'..suffix,'Rider locks, ground/air attacks and independent building hits',function()
        local s=sandbox();local r=at(s,'ravager_rider',25,110)
        local c=foe(s,'cannon',27,110,true);local z=target(s,35,110)
        local hp=c.hp;Game.update(s,.1)
        near(c.hp,hp-220,'Immediate building hit')
        assert(r.targetId==c.id and r.riderTargetId==z.id and r.initialBuildingImpactUsed)
        Game.update(s,.1);near(z.hp,100000-20,'Independent rider damage')
        local closer=target(s,26,111);Game.update(s,.1)
        assert(r.riderTargetId==z.id,'New enemy stole rider lock')
        Game.debugKillEntity(s,z);Game.update(s,.1)
        assert(r.riderTargetId==closer.id,'Rider failed to retarget dead troop')
        local noBuildings=sandbox();local moving=at(noBuildings,'ravager_rider',25,110)
        local air=foe(noBuildings,'blaze',30,110,true)
        step(noBuildings,.3);near(air.hp,air.maxHp-20,'Air shot')
        assert(moving.targetId==nil,'Ravager attacked air troop')
        near(moving.damage,220,'Shared primary stats')
    end)
    add('rider_arrival'..suffix,'Initial Impact on arrival once per lifetime, not per building',function()
        for _,dt in ipairs({.05,.1,.25}) do
            local s=sandbox();local r=at(s,'ravager_rider',25,110)
            local c=foe(s,'cannon',28+4.4*dt*.5,110,true);local hp=c.hp
            r.attackCooldownLeft=99
            Game.update(s,dt);near(c.hp,hp-220,'Same-tick arrival')
            Game.update(s,dt);near(c.hp,hp-220,'Duplicate initial hit')
            Game.debugKillEntity(s,c)
            local next=foe(s,'cannon',r.owner==1 and r.x+1 or 100-r.x+1,110,true)
            local before=next.hp;Game.update(s,dt)
            near(next.hp,before,'Retarget repeated initial hit')
        end
    end)
    add('rider_moving'..suffix,'Reiter fires while Ravager marches toward a building',function()
        local s=sandbox();local r=at(s,'ravager_rider',25,110)
        local b=foe(s,'cannon',25,55,true);local z=target(s,30,110)
        local y=r.y;step(s,.3)
        assert(r.y~=y and r.targetId==b.id,'Building movement blocked')
        near(z.hp,100000-20,'Moving shot')
    end)
    add('mino_two_hits'..suffix,'Normal Zombie dies on exactly two successful Minoshroom hits',function()
        for _,dt in ipairs({.05,.1,.25}) do
            local s=sandbox();local m=at(s,'minoshroom',25,110)
            local z=foe(s,'zombie',27,110,true)
            Game.update(s,dt);near(z.hp,223,'First hit');assert(z.alive)
            step(s,2.4-dt,dt);near(z.hp,223,'Premature second hit')
            step(s,.3,dt);assert(not z.alive and z.hp==0,'Two-hit kill')
            local air=foe(s,'blaze',26,110,true);step(s,3,dt)
            near(air.hp,air.maxHp,'Minoshroom illegally attacked flying')
            near(m.maxHp,2100)
        end
    end)
    add('mino_single'..suffix,'Heavy melee does not splash adjacent units',function()
        local s=sandbox();local m=at(s,'minoshroom',25,110)
        local a=target(s,26,110);local b=target(s,27,110)
        Game.update(s,.1);near(a.hp,99700);near(b.hp,100000)
        assert(m.lockedTargetId==a.id)
    end)
    add('dragon_splash'..suffix,'Dragon splash hits ground and air once at the exact radius',function()
        local s=sandbox();local d=at(s,'baby_ender_dragon',25,110)
        local primary=target(s,30,110)
        local edge=target(s,34,110);local outside=target(s,34.001,110)
        local air=foe(s,'blaze',32,111,true)
        step(s,.3);near(primary.hp,99930);near(edge.hp,99930);near(outside.hp,100000)
        near(air.hp,air.maxHp-70);assert(d.targetId==primary.id)
    end)
    add('dragon_dead_primary'..suffix,'Fireball splashes surviving enemies after its primary target dies',function()
        local s=sandbox();at(s,'baby_ender_dragon',25,110)
        local a=target(s,38,110);local b=target(s,40,110)
        Game.update(s,.1);assert(#s.projectiles==1)
        Game.debugKillEntity(s,a);step(s,.5);near(b.hp,99930)
    end)
    for _,id in ipairs({'ravager_rider','minoshroom','evo:spider','baby_ender_dragon'}) do
        local cardId=id
        add('river_'..id:gsub(':','_')..suffix,'Real bridge / flying navigation for '..id,function()
            local s=sandbox();local e=at(s,cardId,50,105)
            local t=foe(s,cardId=='ravager_rider' and 'cannon' or 'zombie',50,55,true)
            t.hp=100000;t.maxHp=t.hp
            local entered=false;local openWater=false
            for _=1,700 do
                Game.update(s,.1)
                assert(arena.isWalkable(e,e.x,e.y),'Illegal water position')
                if arena.isRiver(e.y) then
                    entered=true
                    if not arena.isBridge(e.x,e.y) then openWater=true end
                end
                if owner==1 and e.y<74 or owner==2 and e.y>86 then break end
            end
            assert(entered,'Never crossed river')
            assert(openWater==(cardId=='baby_ender_dragon'),'Wrong bridge/flight path')
        end)
    end
    add('web_lifetime'..suffix,'Permanent web survives source death, composes slows, clears on target death',function()
        local s=sandbox();local a,b=xy(25,110);local spider=primeWeb(s,owner,a,b)
        local z=target(s,30,110)
        step(s,.2);assert(z.heroWeb and not z.heroWebReservation and not spider.pendingWebShotId)
        near(z.heroWeb.moveFactor,.25);near(z.heroWeb.attackFactor,.25)
        near(z.moveSpeed,7.4);near(z.attackCooldown,1,'Base stats mutated')
        near(modifiers.moveSpeed(z),7.4*.25)
        Game.debugKillEntity(s,spider);step(s,12)
        assert(z.heroWeb,'Source death removed status')
        assert(not Game.debugApplySlow(s,z,.65,1),'Weaker slow stacked with web')
        assert(Game.debugApplySlow(s,z,.1,.3));near(modifiers.moveSpeed(z),7.4*.1)
        step(s,.4);near(modifiers.moveSpeed(z),7.4*.25)
        z.globalMoveSpeedFactor=.95;near(modifiers.moveSpeed(z),7.4*.25*.95)
        Game.debugKillEntity(s,z);assert(z.heroWeb==nil and z.heroWebReservation==nil)
    end)
    add('web_filters'..suffix,'Web excludes allies, air, water, buildings, affected and reserved units',function()
        local s=sandbox();local a,b=xy(25,110);local h=primeWeb(s,owner,a,b)
        local air=foe(s,'blaze',29,110,true);local building=foe(s,'cannon',30,110,true)
        local ally=at(s,'zombie',28,110,true)
        step(s,.2);assert(not h.pendingWebShotId and h.webCooldownLeft==0)
        assert(not air.heroWeb and not building.heroWeb and not ally.heroWeb)
        local good=target(s,36,110);Game.update(s,.1)
        assert(good.heroWebReservation or good.heroWeb,'Ready net wasted without a target')
        step(s,.3);assert(good.heroWeb)
        h.webCooldownLeft=0;step(s,.2)
        assert(h.webCooldownLeft==0 and not h.pendingWebShotId,'Already-webbed target consumed cooldown')
        -- Dev water target is close to a Hero on the same bridge, but is invalid.
        local water=sandbox();local x,y=xy(50,90);local hero=primeWeb(water,owner,x,y)
        local gx,gy=xy(50,80);local guardian=spawn(water,enemy,'guardian',gx,gy,true)
        step(water,.3);assert(not guardian.heroWeb and hero.webCooldownLeft==0)
    end)
    add('web_reservation'..suffix,'Two Hero Spiders reserve one target exactly once; failure refunds only its source',function()
        local s=sandbox();local x,y=xy(25,110);local h=primeWeb(s,owner,x,y)
        local x2,y2=xy(25,111);local other=primeWeb(s,owner,x2,y2)
        local z=target(s,36,110);Game.update(s,.1)
        local pending=(h.pendingWebShotId and 1 or 0)+(other.pendingWebShotId and 1 or 0)
        assert(pending==1 and z.heroWebReservation,'Duplicate launch')
        local firing=h.pendingWebShotId and h or other
        local waiting=firing==h and other or h
        z.flying=true;Game.update(s,.1)
        assert(not z.heroWeb and not z.heroWebReservation and not firing.pendingWebShotId)
        near(firing.webCooldownLeft,0,'Invalid impact not refunded');near(waiting.webCooldownLeft,0)
        z.flying=false;step(s,.5);assert(z.heroWeb)
        assert(not h.pendingWebShotId and not other.pendingWebShotId)
    end)
    add('web_source_inflight'..suffix,'Valid in-flight web survives its source death',function()
        local s=sandbox();local x,y=xy(25,110);local h=primeWeb(s,owner,x,y)
        local z=target(s,36,110);Game.update(s,.1)
        assert(h.pendingWebShotId);Game.debugKillEntity(s,h);step(s,.4)
        assert(z.heroWeb and not z.heroWebReservation)
    end)
    add('web_clock'..suffix,'Ten-second web clock preserves configured delay and exact subsequent spacing',function()
        for _,dt in ipairs({.05,.1,.25}) do
            local s=sandbox();local h=at(s,'evo:spider',25,110)
            h.webCooldownLeft=10 -- verify an explicit delayed charge as well as the ready-on-spawn default
            -- Prevent melee movement into the target; this does not alter web targeting.
            h.moveSpeed=0;local first=target(s,35,110)
            step(s,10-dt,dt);assert(not first.heroWeb and not h.pendingWebShotId)
            Game.update(s,dt);assert(h.pendingWebShotId or first.heroWeb,'Initial ten-second launch missing')
            local launch=s.combatTick;step(s,.5,dt);assert(first.heroWeb)
            local second=target(s,35,111)
            while s.combatTick<launch+math.ceil(10/dt)-1 do Game.update(s,dt) end
            assert(not h.pendingWebShotId and not second.heroWeb,'Early second web')
            Game.update(s,dt);assert(h.pendingWebShotId or second.heroWeb,'Second launch missing')
        end
    end)
end

add('hero_frequency','Actual long-run attacks preserve the +2% frequency despite tick quantization',function()
    for _,dt in ipairs({.05,.1,.25}) do
        local function count(id)
            local s=sandbox();local e=spawn(s,1,id,25,110)
            e.heroWebAbility=nil;local z=dummy(s,2,26,110,1000000)
            step(s,80,dt);return (1000000-z.hp)/e.damage
        end
        local base,hero=count('spider'),count('evo:spider')
        local expected=1+(80-dt)/cards.evolvedCopy('spider').unit.attackCooldown
        assert(math.abs(hero-expected)<=1,'Fractional attack progress lost dt='..dt)
        if dt<=.1 then assert(hero>base and math.abs(hero/base-1.02)<.012,'+2% not realized dt='..dt) end
    end
end)
add('web_attack_clock','Web quarters attack frequency without rewriting interval or losing partial progress',function()
    local s=sandbox();local z=spawn(s,1,'zombie',25,110)
    local t=dummy(s,2,26,110,100000)
    Game.update(s,.1);near(t.hp,99920)
    z.heroWeb={moveFactor=.25,attackFactor=.25,sourceOwner=2,sourceCardId='spider'}
    step(s,3.9);near(t.hp,99920,'Web attack too early')
    Game.update(s,.1);near(t.hp,99840,'Quarter-frequency hit missing')
    near(z.attackCooldown,1);near(z.moveSpeed,7.4)
end)
add('evo_api','Two successful normal plays then Hero, rejected plays and rematch reset',function()
    for _,owner in ipairs({1,2}) do
        local s=Game.new(nil,{headlessSimulation=true})
        s.players[owner].deck={'spider','zombie','skeleton','iron_golem','blaze','witch','wolf','arrows'}
        assert(Game.setEvolutionCard(s,owner,'spider'))
        Game.startHeadlessBattle(s,.1)
        local p=s.players[owner];p.emeralds=10
        local x,y=owner==1 and 25 or 75,owner==1 and 110 or 50
        for play=1,3 do
            p.hand[1]='spider';assert(Game.playCardFromSlot(s,owner,1,x,y))
            local e=s.entities[#s.entities]
            assert((e.visualVariant=='hero_spider')==(play==3),'Wrong Evo cycle')
        end
        near(p.evolutionProgress,0)
        p.hand[1]='spider';p.emeralds=0
        assert(not Game.playCardFromSlot(s,owner,1,x,y));near(p.evolutionProgress,0)
        Game.resetLobby(s);Game.startHeadlessBattle(s,.1)
        near(p.evolutionProgress,0);assert(#s.projectiles==0 and s.nextWebShotId==1)
        for _,e in ipairs(s.entities) do assert(not e.heroWeb and not e.heroWebReservation) end
    end
end)
add('evo_disabled','Ruleset-disabled Evo remains normal and Dev spawn remains available',function()
    local s=Game.new(nil,{headlessSimulation=true})
    s.players[1].deck={'spider','zombie','skeleton','iron_golem','blaze','witch','wolf','arrows'}
    assert(Game.setEvolutionCard(s,1,'spider'));s.ruleset.evolutions=false
    Game.startHeadlessBattle(s,.1)
    for i=1,4 do
        s.players[1].hand[1]='spider';s.players[1].emeralds=10
        assert(Game.playCardFromSlot(s,1,1,25,110))
        assert(s.entities[#s.entities].visualVariant~='hero_spider')
    end
    local dev=sandbox();assert(spawn(dev,1,'evo:spider',25,110).heroWebAbility)
end)

add('initial_web_ready','Hero Web starts ready without consuming a shot in an empty arena',function()
    local s=sandbox();local h=spawn(s,1,'evo:spider',25,110)
    near(h.webCooldownLeft,0);step(s,2);near(h.webCooldownLeft,0)
    local z=dummy(s,2,30,110);Game.update(s,.1)
    assert(z.heroWebReservation or z.heroWeb,'No initial shot');step(s,.2);assert(z.heroWeb)
end)
add('web_purged_entity','Final removal clears permanent status even on an externally retained entity reference',function()
    local s=sandbox();primeWeb(s,1,25,110);local z=dummy(s,2,30,110)
    step(s,.2);assert(z.heroWeb);Game.debugClearUnits(s)
    assert(z.heroWeb==nil and z.heroWebReservation==nil,'Removed entity retained status')
    local fresh=spawn(s,2,'zombie',30,110);assert(not fresh.heroWeb and not fresh.heroWebReservation)
end)
add('result_web_cancel','Match end cancels pending nets and releases both reservation endpoints',function()
    local s=sandbox();local h=primeWeb(s,1,25,110);local z=dummy(s,2,36,110)
    Game.update(s,.1);assert(h.pendingWebShotId and z.heroWebReservation)
    Game.finish(s,1,'fixture result')
    assert(not h.pendingWebShotId and not z.heroWebReservation,'Result left a pending web transaction')
    assert(not z.heroWeb,'Unlanded net applied on match end')
end)
add('rider_web_rates','Permanent web quarters both Ravager weapon frequencies independently',function()
    local s=sandbox();local r=spawn(s,1,'ravager_rider',25,110)
    local b=spawn(s,2,'cannon',27,110,true);b.hp=100000;b.maxHp=b.hp
    local z=dummy(s,2,35,110)
    r.heroWeb={moveFactor=.25,attackFactor=.25,sourceOwner=2,sourceCardId='spider'}
    Game.update(s,.1);near(b.hp,99780)
    step(s,8.2);near(b.hp,99780);near(z.hp,99960,'Rider did not quarter its shot rate')
    step(s,3.8);near(b.hp,99560,'Ravager did not quarter its building hit rate')
    near(r.attackCooldown,3);near(r.secondaryAttack.interval,2)
end)
add('heavy_matchups','Minoshroom uses shared damage for real Iron/Diamond Golem and Wither HP',function()
    for _,row in ipairs({{'iron_golem',6},{'evo:iron_golem',6},{'wither_skeleton',2}}) do
        local s=sandbox();spawn(s,1,'minoshroom',25,110)
        local t=spawn(s,2,row[1],27,110,true)
        for hit=1,row[2] do
            if hit==1 then Game.update(s,.1) else step(s,2.4) end
            assert(t.alive==(hit<row[2]),'Wrong real heavy matchup hit count '..row[1])
        end
    end
end)
add('winning_primary_freeze','Ravager winning King hit freezes the rider and all later combat',function()
    local s=Game.new(nil,{headlessSimulation=true});Game.debugLoadScenario(s,'king')
    Game.debugSetPaused(s,false)
    for _,tower in ipairs(s.entities) do tower.passive=true end
    local king=s.entities[2];king.hp=1
    local r=spawn(s,1,'ravager_rider',king.x,king.y+1)
    local z=dummy(s,2,king.x+4,king.y+1)
    r.targetId=king.id;r.lockedTargetId=king.id
    s.phase='battle';s.adminMode=false
    Game.update(s,.1);assert(s.phase=='result' and s.winner==1)
    near(z.hp,100000,'Rider attacked after victory')
    for _,p in ipairs(s.projectiles) do assert(p.sourceEntityId~=r.id,'Post-win rider projectile') end
end)

function suite.register(runTest)
    for _,entry in ipairs(suite.cases) do
        local case=entry
        runTest(case.id,case.title,function()
            case.run();return true,case.title,{}
        end)
    end
end
return suite

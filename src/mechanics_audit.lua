-- Additional actual-engine probes kept separate from the historical fixtures.
local Game=require('src.game')
local arena=require('src.arena')
local cards=require('src.cards')
local diagnostics=require('src.diagnostics')
local Bot=require('src.bot')
local audit={}
local function admin(scenario)
    local state=Game.new(nil,{headlessSimulation=true})
    Game.debugLoadScenario(state,scenario or 'empty')
    Game.debugSetPaused(state,false);return state
end
local function step(state,seconds)
    local ticks=math.ceil(seconds/0.05)
    for _=1,ticks do Game.update(state,0.05) end
end
function audit.register(runTest)
    runTest('terminal_delayed_spell','Winning delayed spells freeze later combat stages',function()
        local state=Game.new(nil,{headlessSimulation=true});Game.startHeadlessBattle(state,0.1)
        local king
        for _,e in ipairs(state.entities) do if e.owner==2 and e.towerType=='king' then king=e end end
        king.hp=1;state.globalMovementAuraDirty=true
        state.pendingSpells={{kind='falling_anvil',owner=1,cardId='falling_anvil',
            x=king.x,y=king.y,remaining=0.1,spell=cards.get('falling_anvil').spell}}
        local before=state.combatTick;Game.update(state,0.1)
        return state.phase=='result' and state.winner==1
            and state.globalMovementAuraDirty==true and state.combatTick==before,
            'No aura/combat stage after the winning spell.',{}
    end)
    runTest('exact_timer_cadence','Repeated attacks respect configured cooldown boundaries',function()
        local probes=0
        for _,id in ipairs({'zombie','skeleton','cannon','snow_golem','blaze'}) do
            local state=admin();Game.debugSpawnCard(state,1,id,50,110)
            local attacker=state.entities[1]
            Game.debugSpawnCard(state,2,'zombie',51,110)
            local target=state.entities[#state.entities]
            target.passive=true;target.hp=100000;target.maxHp=100000
            attacker.moveSpeed=0
            local lastHit,lastHp=nil,target.hp
            local interval=math.ceil(attacker.attackCooldown/0.1-1e-9)
            for tick=1,80 do
                Game.update(state,0.1)
                if target.hp<lastHp then
                    if lastHit then
                        if tick-lastHit~=interval then return false,'Extra timer tick '..id,{} end
                        probes=probes+1
                    end
                    lastHit,lastHp=tick,target.hp
                end
            end
        end
        for _,mode in ipairs({'easy','normal','hard'}) do
            local state=Game.new(nil,{headlessSimulation=true});Game.startHeadlessBattle(state,0.1)
            state.players[1].emeralds=0;state.players[1].hand={};state.timeLeft=45
            local bot=Bot.new(1);bot.enabled=true;Bot.setDifficulty(bot,mode);bot.thinkTimer=0.3
            for _=1,12 do
                local expected=math.ceil(bot.thinkTimer/0.1-1e-9)
                local before=bot.decisionCount;local observed=0
                repeat Bot.update(bot,state,0.1);observed=observed+1 until bot.decisionCount>before or observed>30
                if observed~=expected then return false,'Extra bot timer tick '..mode,{} end
                probes=probes+1
            end
        end
        return probes>=51,'Repeated engine attacks and bot intervals measured.',{'intervals='..probes}
    end)
    runTest('tower_lock_retarget','Both tower types retain targets and retarget legitimately',function()
        local probes=0
        for owner=1,2 do for _,kind in ipairs({'princess','king'}) do
            local state=admin('full');local tower
            for _,e in ipairs(state.entities) do
                e.passive=true
                if e.owner==owner and e.towerType==kind then tower=e end
            end
            tower.passive=false;tower.attackCooldownLeft=999
            local direction=owner==1 and -1 or 1
            Game.debugSpawnCard(state,3-owner,'zombie',tower.x,tower.y+direction*20)
            local first=state.entities[#state.entities];first.passive=true
            Game.update(state,0.1)
            if tower.targetId~=first.id then return false,'Tower did not acquire',{} end
            Game.debugSpawnCard(state,3-owner,'endermite',tower.x,tower.y+direction*2)
            local closer=state.entities[#state.entities];closer.passive=true
            Game.update(state,0.1)
            if tower.targetId~=first.id then return false,'Closer spawn stole tower lock',{} end
            first.x=first.x<50 and 98 or 2;first.y=80
            Game.update(state,0.1);Game.update(state,0.1)
            if tower.targetId~=closer.id then return false,'Range retarget failed',{} end
            Game.debugKillEntity(state,closer);Game.update(state,0.1)
            if tower.targetId~=nil then return false,'Tower retained dead target',{} end
            probes=probes+1
        end end
        return probes==4,'Princess/King locks validated on both owners.',{'probes='..probes}
    end)
    runTest('terminal_projectiles','Winning impact freezes the remaining projectile batch',function()
        local state=Game.new(nil,{headlessSimulation=true});Game.startHeadlessBattle(state,0.1)
        local king,princess
        for _,e in ipairs(state.entities) do
            e.passive=true
            if e.owner==2 and e.towerType=='king' then king=e end
            if e.owner==2 and e.towerType=='princess' then princess=e end
        end
        king.hp=1;local before=princess.hp
        state.projectiles={
            {x=king.x,y=king.y,targetId=king.id,owner=1,damage=2,speed=50,alive=true,sourceCardId='skeleton'},
            {x=princess.x,y=princess.y,targetId=princess.id,owner=1,damage=100,speed=50,alive=true,sourceCardId='skeleton'},
        }
        Game.update(state,0.1)
        return state.phase=='result' and state.winner==1 and princess.hp==before,
            'No post-win impact damage.',{'post_win_damage='..(before-princess.hp)}
    end)
    runTest('spawn_side_mirror','Deployment, summon and split bodies mirror player views',function()
        local probes=0
        for _,id in ipairs({'bat_swarm','witch','evoker','nether_portal','evo:nether_portal','slime','magma_cube'}) do
            local groups={}
            for owner=1,2 do
                local state=admin()
                Game.debugSpawnCard(state,owner,id,owner==1 and 25 or 75,owner==1 and 110 or 50)
                local parent=state.entities[1]
                if parent.periodicSpawn then
                    parent.passive=true;parent.moveSpeed=0
                    step(state,(parent.periodicSpawn.initialDelay or parent.periodicSpawn.interval)+0.15)
                elseif parent.splitOnDeath then Game.debugKillEntity(state,parent) end
                groups[owner]={}
                for _,e in ipairs(state.entities) do if e.alive then groups[owner][#groups[owner]+1]=e end end
            end
            if #groups[1]~=#groups[2] then return false,'Count mismatch '..id,{} end
            for i,e in ipairs(groups[1]) do
                local other=groups[2][i]
                if math.abs(e.x+other.x-100)>1e-6 or math.abs(e.y+other.y-160)>1e-6 then
                    return false,'Spawn mirror mismatch '..id,{}
                end
                probes=probes+1
            end
        end
        return probes>10,'Both axes and counts preserved.',{'bodies='..probes}
    end)
    runTest('bridge_flying_paths','Ground uses bridges; flying crosses open water on both owners',function()
        local probes=0
        for owner=1,2 do for _,id in ipairs({'zombie','blaze'}) do
            local state=admin()
            Game.debugSpawnCard(state,owner,id,50,owner==1 and 100 or 60)
            Game.debugSpawnCard(state,3-owner,'zombie',50,owner==1 and 50 or 110)
            local moving,target=state.entities[1],state.entities[2]
            moving.damage=0;target.passive=true
            local water,bridge=false,false
            for _=1,240 do
                Game.update(state,0.1)
                if not arena.isWalkable(moving,moving.x,moving.y) then return false,'Illegal terrain',{} end
                if arena.isRiver(moving.y) then
                    bridge=bridge or arena.isBridge(moving.x,moving.y)
                    water=water or not arena.isBridge(moving.x,moving.y)
                end
            end
            local crossed=owner==1 and moving.y<74 or (owner==2 and moving.y>86)
            if not crossed or (id=='zombie' and (water or not bridge)) or (id=='blaze' and not water) then
                return false,'Wrong traversal '..id,{}
            end
            probes=probes+1
        end end
        return probes==4,'No ground shortcuts or stuck river crossings.',{'probes='..probes}
    end)
    runTest('consecutive_match_reset','Twenty matches clear match-local state and retain lobby choices',function()
        local state=Game.new(nil,{headlessSimulation=true})
        state.players[1].deck=cards.defaultDeck();state.players[2].deck=cards.defaultDeck()
        Game.setEvolutionCard(state,1,'creeper');local savedPresets=state.deckPresets
        for match=1,20 do
            local started=Game.startHeadlessBattle(state,0.1)
            if not started or #state.entities~=6 or state.combatTick~=0
                or state.players[1].evolutionProgress~=0 or state.stats.players[1].cardsPlayed~=0 then
                return false,'Stale match start '..match,{}
            end
            diagnostics.assertState(state,'match reset '..match)
            Game.playCardFromSlot(state,1,1,25,110);Game.update(state,0.1)
            state.players[1].evolutionProgress=2;Game.finish(state,match%2+1,'RESET PROBE')
            local snapshot=diagnostics.combatSnapshot(state);Game.update(state,0.1)
            if snapshot~=diagnostics.combatSnapshot(state) then return false,'Result changed',{} end
            Game.resetLobby(state)
            if #state.entities~=0 or #state.projectiles~=0 or #state.pendingSpells~=0
                or state.emeraldBoost[1]~=0 or state.players[1].evolutionProgress~=0
                or state.deckPresets~=savedPresets or state.players[1].evolutionCardId~='creeper' then
                return false,'Lobby reset leaked/overwrote state',{}
            end
        end
        return true,'Resets preserve intended deck/Evo choices and preset data.',{'matches=20'}
    end)
    runTest('ui_state_independence','UI visibility does not change combat',function()
        local states={admin(),admin()}
        for _,state in ipairs(states) do
            Game.debugSpawnCard(state,1,'skeleton',45,110);Game.debugSpawnCard(state,2,'zombie',45,103)
        end
        states[2].players[1].infoOpen=true;states[2].players[2].rulesetOpen=true
        for tick=1,120 do
            for _,state in ipairs(states) do Game.update(state,0.1) end
            if diagnostics.combatSnapshot(states[1])~=diagnostics.combatSnapshot(states[2]) then
                return false,'UI affected combat at tick '..tick,{}
            end
        end
        return true,'Identical combat with differing UI flags.',{'ticks=120'}
    end)
end
return audit

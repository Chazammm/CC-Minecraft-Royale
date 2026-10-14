colors={white=1,orange=2,magenta=4,lightBlue=8,yellow=16,lime=32,pink=64,
    gray=128,lightGray=256,cyan=512,purple=1024,blue=2048,brown=4096,
    green=8192,red=16384,black=32768}
local Game=require('src.game')
local cards=require('src.cards')
local diagnostics=require('src.diagnostics')
local config=require('config')
local Bot=require('src.bot')
local failures,checks=0,0
local function check(ok,msg)
    checks=checks+1;if not ok then failures=failures+1;print('FAIL '..msg) end
end
local function admin(kind)
    local s=Game.new(nil,{headlessSimulation=true})
    Game.debugLoadScenario(s,kind or 'empty');Game.debugSetPaused(s,false);return s
end
for _,id in ipairs({'zombie','skeleton','king','cannon','snow_golem','blaze'}) do
    local s=admin(id=='king' and 'king' or 'empty')
    local attacker
    if id=='king' then
        attacker=s.entities[1];s.entities[2].passive=true
    else
        Game.debugSpawnCard(s,1,id,50,110);attacker=s.entities[1]
    end
    Game.debugSpawnCard(s,2,'zombie',attacker.x+1,attacker.y)
    local target=s.entities[#s.entities];target.passive=true;target.hp=100000;target.maxHp=100000
    attacker.moveSpeed=0
    local hits,lastHp={},target.hp
    for tick=1,80 do
        Game.update(s,0.1)
        if target.hp<lastHp then hits[#hits+1]=tick;lastHp=target.hp end
    end
    local expected=math.ceil(attacker.attackCooldown/0.1-1e-9)
    check(#hits>=3,'Insufficient repeated attacks '..id)
    for i=2,#hits do
        check(hits[i]-hits[i-1]==expected,
            ('%s cooldown %.2fs: expected %d ticks, got %d'):format(id,attacker.attackCooldown,expected,hits[i]-hits[i-1]))
    end
end
for _,id in ipairs({'villager','evoker'}) do
    local s=admin();Game.debugSpawnCard(s,1,id,50,110)
    local e=s.entities[1];e.passive=true
    if id=='villager' then
        for _=1,500 do Game.update(s,0.1) end
        check(not e.alive,'50s Villager persisted into an extra 50.1s tick')
    else
        for _=1,180 do Game.update(s,0.1) end
        check(e.periodicSpawnTotal==6,'4s+14s Vex wave was delayed beyond tick180')
    end
end
local s=Game.new(nil,{headlessSimulation=true});Game.startHeadlessBattle(s,0.1)
for _=1,1500 do Game.update(s,0.1) end
check(s.overtime==true,'150s regulation boundary was delayed to 150.1s')
local previous=config.MATCH.countdown;config.MATCH.countdown=3
s=Game.new(nil,{headlessSimulation=true})
local started,ticks=Game.startHeadlessBattle(s,0.05)
config.MATCH.countdown=previous
check(started and ticks==60,'3s countdown at 0.05s gained a floating-point extra tick')
for _,dt in ipairs({0,-0.1}) do
    local a=admin();Game.debugSpawnCard(a,1,'zombie',50,110);Game.debugSpawnCard(a,2,'zombie',51,110)
    local before=diagnostics.combatSnapshot(a);Game.update(a,dt)
    check(before==diagnostics.combatSnapshot(a),'Nonpositive time delta advanced combat')
end
for _,mode in ipairs({'easy','normal','hard'}) do
    local state=Game.new(nil,{headlessSimulation=true});Game.startHeadlessBattle(state,0.1)
    state.players[1].emeralds=0;state.players[1].hand={};state.timeLeft=45
    local bot=Bot.new(1);bot.enabled=true;Bot.setDifficulty(bot,mode)
    bot.thinkTimer=0.3
    for decision=1,12 do
        local expected=math.ceil(bot.thinkTimer/0.1-1e-9)
        local before=bot.decisionCount;local observed=0
        repeat Bot.update(bot,state,0.1);observed=observed+1 until bot.decisionCount>before or observed>30
        check(observed==expected,mode..' bot timer expected '..expected..' ticks, got '..observed)
    end
end
assert(failures==0,('%d timer-precision regressions failed'):format(failures))
print(('Timer precision passed: %d checks, exact cooldowns/lifetimes/countdown/regulation'):format(checks))

colors={white=1,orange=2,magenta=4,lightBlue=8,yellow=16,lime=32,pink=64,
 gray=128,lightGray=256,cyan=512,purple=1024,blue=2048,brown=4096,green=8192,red=16384,black=32768}
local Game=require('src.game')
local Bot=require('src.bot')
local Runner=require('src.headless_match')
local diagnostics=require('src.diagnostics')
local chosen={'breeze','adventure_sheep','villager','minoshroom','pillager_outpost','arrows','falling_anvil','nether_portal'}
local opposing={'minoshroom','villager','iron_golem','blaze','spider','pillager_outpost','snow_golem','falling_anvil'}
local checks,matches=0,{}
local function check(ok,msg)checks=checks+1;assert(ok,msg)end
local function configure(_,a,b)Bot.setDifficulty(a,'hard');Bot.setDifficulty(b,'hard')end
local function bots(s,a,b,tick,offset)
 if (tick+offset)%2==0 then Bot.update(a,s,.1);Bot.update(b,s,.1)
 else Bot.update(b,s,.1);Bot.update(a,s,.1) end
end
for _,owner in ipairs({1,2}) do
 local left,right=chosen,opposing;if owner==2 then left,right=right,left end
 local seed=20261017+owner;local offset=owner%2
 math.randomseed(seed)
 local live=Game.new();local a,b=Bot.new(1,left),Bot.new(2,right)
 Bot.prepare(a,live);Bot.prepare(b,live);configure(live,a,b)
 live.players[1].ready=true;live.players[2].ready=true;Game.startCountdown(live)
 local tick=0;repeat Game.update(live,.1);tick=tick+1 until live.phase=='battle'
 Bot.beginMatch(a);Bot.beginMatch(b);a.enabled=true;b.enabled=true
 bots(live,a,b,tick-1,offset)
 local trace={[tick]=diagnostics.combatSnapshot(live)}
 while live.phase~='result' and tick<4000 do
  Game.update(live,.1);bots(live,a,b,tick,offset);tick=tick+1
  diagnostics.assertState(live,'Breeze/Sheep live')
  if tick%25==0 or live.phase=='result' then trace[tick]=diagnostics.combatSnapshot(live) end
 end
 check(live.phase=='result','Live match timeout')
 local state,first,second,total=Runner.run(left,right,{gameplaySeed=seed,botOrderOffset=offset,configure=configure,
  onTick=function(s,_,_,t)
   diagnostics.assertState(s,'Breeze/Sheep headless')
   if trace[t] then check(trace[t]==diagnostics.combatSnapshot(s),'Live/headless drift tick '..t) end
  end})
 check(total==tick and diagnostics.combatSnapshot(live)==diagnostics.combatSnapshot(state),'Final parity')
 check(first.actions==a.actions and second.actions==b.actions,'Bot action parity')
 for _,id in ipairs({'breeze','adventure_sheep'}) do
  local card=state.stats.players[owner].cards[id]
  check(card and card.plays>0 and card.unitDamage>0,'Did not exercise '..id..' P'..owner)
 end
 check((state.stats.players[owner].cards.breeze.windPushes or 0)>0,'Full match never exercised displacement')
 local replay=Runner.run(left,right,{gameplaySeed=seed,botOrderOffset=offset,configure=configure})
 check(diagnostics.combatSnapshot(replay)==diagnostics.combatSnapshot(state),'Seeded replay drift')
 local snapshot=diagnostics.combatSnapshot(state)
 Game.update(state,.25);check(snapshot==diagnostics.combatSnapshot(state),'Result mutated combat')
 check(#state.pendingDeployments==0,'Pending deployment after result')
 matches[#matches+1]={owner=owner,seed=seed,ticks=tick,winner=state.winner,
  breeze=state.stats.players[owner].cards.breeze.plays,sheep=state.stats.players[owner].cards.adventure_sheep.plays}
end
for _,m in ipairs(matches) do
 print(('P%d seed=%d ticks=%d winner=%s breeze_plays=%d sheep_plays=%d'):format(m.owner,m.seed,m.ticks,tostring(m.winner),m.breeze,m.sheep))
end
print(('Breeze/Sheep full-match parity: %d checks, both owners, live/headless + seeded replay'):format(checks))

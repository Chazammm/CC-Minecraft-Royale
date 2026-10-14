colors={white=1,orange=2,magenta=4,lightBlue=8,yellow=16,lime=32,pink=64,
 gray=128,lightGray=256,cyan=512,purple=1024,blue=2048,brown=4096,green=8192,red=16384,black=32768}
package.path='./?.lua;./?/init.lua;'..package.path
local Game=require('src.game')
local Bot=require('src.bot')
local Runner=require('src.headless_match')
local cards=require('src.cards')
local diagnostics=require('src.diagnostics')
local deck={'ravager_rider','baby_ender_dragon','minoshroom','spider','zombie','skeleton','cannon','arrows'}
local opponent={'iron_golem','blaze','spider','wolf','creeper','pillager_outpost','snow_golem','falling_anvil'}
local checks=0
local function check(ok,msg)checks=checks+1;assert(ok,msg)end
local function configure(s,b1,b2)
 check(Game.setEvolutionCard(s,1,'spider'),'Hero P1 selection')
 check(Game.setEvolutionCard(s,2,'spider'),'Hero P2 selection')
 Bot.setDifficulty(b1,'hard');Bot.setDifficulty(b2,'hard')
end
local function bots(s,a,b,tick,offset)
 if (tick+offset)%2==0 then Bot.update(a,s,.1);Bot.update(b,s,.1)
 else Bot.update(b,s,.1);Bot.update(a,s,.1) end
end
-- Independent live countdown/driver, with bounded exact snapshot checkpoints.
for _,seed in ipairs({714,715}) do
 local offset=seed%2
 math.randomseed(seed)
 local live=Game.new();local a=Bot.new(1,deck);local b=Bot.new(2,opponent)
 Bot.prepare(a,live);Bot.prepare(b,live);configure(live,a,b)
 live.players[1].ready=true;live.players[2].ready=true
 Game.startCountdown(live);local tick=0
 repeat Game.update(live,.1);tick=tick+1 until live.phase=='battle'
 Bot.beginMatch(a);Bot.beginMatch(b);a.enabled=true;b.enabled=true
 bots(live,a,b,tick-1,offset)
 local trace={};trace[tick]=diagnostics.combatSnapshot(live)
 while live.phase~='result' and tick<4000 do
  Game.update(live,.1);bots(live,a,b,tick,offset);tick=tick+1
  diagnostics.assertState(live,'new-unit live driver')
  if tick%25==0 or live.phase=='result' then trace[tick]=diagnostics.combatSnapshot(live) end
 end
 check(live.phase=='result','Live driver timeout')
 local shared,sa,sb,total=Runner.run(deck,opponent,{gameplaySeed=seed,botOrderOffset=offset,configure=configure,
  onTick=function(s,_,_,t)
   diagnostics.assertState(s,'new-unit headless driver')
   if trace[t] then check(trace[t]==diagnostics.combatSnapshot(s),'Live/headless combat drift tick '..t) end
  end})
 check(total==tick and diagnostics.combatSnapshot(shared)==diagnostics.combatSnapshot(live),'Final live/headless mismatch')
 check(sa.actions==a.actions and sb.actions==b.actions,'Bot action drift')
 local seen=shared.stats.players[1].cards
 for _,id in ipairs({'ravager_rider','baby_ender_dragon','minoshroom','spider'}) do check(seen[id] and seen[id].plays>0,'Bot never played '..id) end
 local spider=seen.spider
 check(spider.evolutionPlays>0 and (spider.websApplied or 0)>0,'Hero/web not exercised in full match')
 local replay=Runner.run(deck,opponent,{gameplaySeed=seed,botOrderOffset=offset,configure=configure})
 check(diagnostics.combatSnapshot(replay)==diagnostics.combatSnapshot(shared),'Seed replay changed result')
 check(shared.winner==nil or shared.winner==1 or shared.winner==2,'Invalid winner')
 local before=diagnostics.combatSnapshot(shared);for _=1,5 do Game.update(shared,.1) end
 check(before==diagnostics.combatSnapshot(shared),'Result state continued combat')
end
-- Data guards reject malformed new channels and injected entity-local state.
for _,fault in ipairs({'range','damage','interval','projectileSpeed','heroWeb','pendingWebShotId'}) do
 local restore=diagnostics.restorePoint(cards)
 local r=cards.get('ravager_rider').unit
 if fault=='heroWeb' then r.heroWeb={moveFactor=.25}
 elseif fault=='pendingWebShotId' then r.pendingWebShotId=1
 else r.secondaryAttack[fault]=fault=='range' and -1 or 0/0 end
 local ok=pcall(cards.validate);restore();check(not ok,'Schema missed '..fault)
 check(cards.validate(),'Schema not restored')
end
-- Public modifiers are shared with Bot Anvil forecasts and DPS estimates.
local modifiers=require('src.combat_modifiers')
local unit={moveSpeed=7.4,attackCooldown=1,heroWeb={moveFactor=.25,attackFactor=.25},globalMoveSpeedFactor=.95}
check(math.abs(modifiers.moveSpeed(unit)-1.7575)<1e-8,'Effective movement composition')
check(modifiers.attackFrequency(unit)==.25,'Effective attack frequency')
local s=Game.new(nil,{headlessSimulation=true});Game.debugLoadScenario(s,'empty');Game.debugSetPaused(s,false)
assert(Game.debugSpawnCard(s,1,'zombie',25,110))
assert(Game.debugSpawnCard(s,2,'zombie',25,50))
local z=s.entities[1];local target=s.entities[2];target.passive=true
z.targetId=target.id;z.lockedTargetId=target.id
z.heroWeb={moveFactor=.25,attackFactor=.25,sourceOwner=2,sourceCardId='spider'}
local px,py=Bot.debugPredictedAnvilPosition(s,z,1)
for i=1,10 do Game.update(s,.1) end
check(math.abs(px-z.x)<1e-7 and math.abs(py-z.y)<1e-7,'Bot forecast did not use permanent web movement')
print(('Four-mob simulation parity: %d checks, 2 full live/headless matches + deterministic replays'):format(checks))

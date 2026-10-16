-- A later ordinary projectile can kill a target after its earlier web shot
-- was processed. The stale flight is cancelled/refunded on the next update.
colors={white=1,orange=2,magenta=4,lightBlue=8,yellow=16,lime=32,pink=64,
    gray=128,lightGray=256,cyan=512,purple=1024,blue=2048,brown=4096,
    green=8192,red=16384,black=32768}
local Game=require('src.game')
local diagnostics=require('src.diagnostics')
for owner=1,2 do
    local state=Game.new(nil,{headlessSimulation=true})
    Game.debugLoadScenario(state,'empty');Game.debugSetPaused(state,false)
    assert(Game.debugSpawnCard(state,owner,'evo:spider',25,110))
    local source=state.entities[#state.entities]
    source.moveSpeed=0;source.attackRange=0;source.damage=0
    assert(Game.debugSpawnCard(state,3-owner,'zombie',36,110))
    local victim=state.entities[#state.entities]
    victim.passive=true;victim.hp=10
    Game.update(state,.1)
    local web=assert(state.projectiles[1])
    assert(web.heroWebSpec and web.alive and source.pendingWebShotId)
    state.projectiles[#state.projectiles+1]={alive=true,owner=owner,
        x=victim.x,y=victim.y,lastTargetX=victim.x,lastTargetY=victim.y,
        targetId=victim.id,sourceEntityId=source.id,sourceCardId='spider',damage=10,speed=60}
    Game.update(state,.1)
    assert(not victim.alive and not state.entityById[victim.id])
    assert(web.alive and source.pendingWebShotId==web.webShotId,
        'Fixture must retain the already-processed flight until the next update')
    assert(diagnostics.assertState(state,'valid deferred flight cancellation'))
    Game.update(state,.1)
    assert(not web.alive and not source.pendingWebShotId and source.webCooldownLeft==0,
        'The next update must cancel/refund the invalid web flight')
    assert(diagnostics.assertState(state,'cancelled flight'))
    -- A live target must still hold its reservation; the fix must not make
    -- genuinely broken transactions invisible to the observer.
    assert(Game.debugSpawnCard(state,3-owner,'zombie',36,110))
    local live=state.entities[#state.entities];live.passive=true
    Game.update(state,.1)
    assert(live.heroWebReservation)
    local reservation=live.heroWebReservation;live.heroWebReservation=nil
    assert(not pcall(diagnostics.assertState,state,'missing live reservation'))
    live.heroWebReservation=reservation
    assert(diagnostics.assertState(state,'restored live reservation'))
end
print('Web observer boundary passed: both owners, deferred cancellation, refund, live corruption rejection')

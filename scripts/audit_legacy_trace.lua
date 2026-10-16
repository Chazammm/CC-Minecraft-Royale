-- Host cross-revision oracle: explicit pre-Frog/Worm decks, full canonical
-- checkpoints every 25 ticks. Run this same script from either checkout.
colors={white=1,orange=2,magenta=4,lightBlue=8,yellow=16,lime=32,pink=64,
    gray=128,lightGray=256,cyan=512,purple=1024,blue=2048,brown=4096,
    green=8192,red=16384,black=32768}
local Runner=require('src.headless_match')
local Bot=require('src.bot')
local diagnostics=require('src.diagnostics')
local decks={
    {'zombie','skeleton','iron_golem','bat_swarm','cannon','arrows','creeper','slime'},
    {'evoker','enderman','nether_portal','magma_cube','pillager_outpost','falling_anvil','blaze','villager'},
    {'endermite','wolf','snow_golem','spider','wither_skeleton','ravager_rider','baby_ender_dragon','minoshroom'},
    {'spider','creeper','villager','iron_golem','endermite','nether_portal','arrows','wolf'},
}
for case=1,8 do
    local pair=math.floor((case-1)/2)+1
    local a,b=decks[pair],decks[pair%4+1]
    if case%2==0 then a,b=b,a end
    local function trace(state,_,_,tick)
        if tick%25==0 or state.phase=='result' then
            local snapshot=diagnostics.combatSnapshot(state)
            -- Only additive, UNUSED custom-deployment bookkeeping is omitted.
            -- Nonempty warnings and nonzero refund/cancellation values remain
            -- visible, so normalization cannot hide accidentally active skills.
            snapshot=snapshot:gsub('"pendingDeployments"={};','')
                :gsub('"nextDeploymentId"=1;','')
                :gsub('"deploymentRefunds"=0;','')
                :gsub('"cancelledDeployments"=0;','')
            print(case..'|'..tick..'|'..snapshot)
        end
    end
    local state,first,second,ticks=Runner.run(a,b,{
        gameplaySeed=20261016+pair,botOrderOffset=case%2,
        configure=function(_,x,y)Bot.setDifficulty(x,'hard');Bot.setDifficulty(y,'hard')end,
        onTick=trace,
    })
    print(('END|case=%d|ticks=%d|winner=%s|actions=%d'):format(
        case,ticks,tostring(state.winner),first.actions+second.actions))
end

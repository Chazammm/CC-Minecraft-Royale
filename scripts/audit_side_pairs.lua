-- Reproduce and locate outcome differences in the invariant audit's paired
-- deck schedule. Differences are diagnostic observations, not balance edits.
colors={white=1,orange=2,magenta=4,lightBlue=8,yellow=16,lime=32,pink=64,
    gray=128,lightGray=256,cyan=512,purple=1024,blue=2048,brown=4096,
    green=8192,red=16384,black=32768}
local cards=require('src.cards')
local bm=require('src.benchmark_utils')
local Runner=require('src.headless_match')
local Bot=require('src.bot')
local seed=assert(bm.parseSeed(arg[1],20261016))
local pairCount=tonumber(arg[2] or 500)
assert(pairCount and pairCount>0 and pairCount<=500 and pairCount%1==0)
local random=bm.newRandomInt(seed)
local pool={};for _,card in ipairs(cards.list) do pool[#pool+1]=card.id end
local mismatches=0
for pair=1,pairCount do
    local order=bm.shuffle(pool,random)
    local a,b={},{}
    for i=1,8 do a[i]=order[i];b[i]=order[i+8] end
    local mode=({'easy','normal','hard'})[(pair-1)%3+1]
    local function run(flipped)
        return Runner.run(flipped and b or a,flipped and a or b,{
            gameplaySeed=bm.pairedGameplaySeed(seed,pair),botOrderOffset=flipped and 1 or 0,
            configure=function(_,x,y)Bot.setDifficulty(x,mode);Bot.setDifficulty(y,mode)end,
        })
    end
    local left=run(false)
    local right=run(true)
    local opposite=left.winner and 3-left.winner or nil
    if opposite~=right.winner then
        mismatches=mismatches+1
        print(('SIDE_PAIR_DIFFERENCE|pair=%d|mode=%s|first_winner=%s|swapped_winner=%s|first_s=%.4f|swapped_s=%.4f'):format(
            pair,mode,tostring(left.winner),tostring(right.winner),left.stats.elapsed,right.stats.elapsed))
        print('SIDE_DECK_A|'..table.concat(a,','))
        print('SIDE_DECK_B|'..table.concat(b,','))
        for _,flipped in ipairs({false,true}) do
            local replay=run(flipped)
            local expected=flipped and right or left
            assert(replay.winner==expected.winner and replay.stats.elapsed==expected.stats.elapsed,
                'Pair difference was not reproducible')
        end
    end
end
print(('SIDE_PAIRS|seed=%d|pairs=%d|outcome_mismatches=%d'):format(seed,pairCount,mismatches))

-- Reusable full-engine diagnostic: invariants every tick, paired mixed decks,
-- stable result fingerprints and post-GC memory observations. No balance edits.
local cards=require('src.cards')
local benchmark=require('src.benchmark_utils')
local Runner=require('src.headless_match')
local Bot=require('src.bot')
local diagnostics=require('src.diagnostics')
local version=require('src.version')
local util=require('src.util')
local args={...}
if not args[1] or args[1]=='help' or args[1]=='--help' then
    print('Usage: audit_matches <1-1000> [seed]');return
end
local count=tonumber(args[1])
if not count or count~=math.floor(count) or count<1 or count>1000 then
    error('Audit match count must be an integer from 1 to 1000',0)
end
local seed,err=benchmark.parseSeed(args[2],20261014)
if not seed then error(err,0) end
local randomInt=benchmark.newRandomInt(seed)
local pool={};for _,card in ipairs(cards.list) do pool[#pool+1]=card.id end
local decks,outcomes,appearances={}, {0,0,0},{}
local fingerprint=17
local ticks=0
local started=os.clock()
local lastYield=started
local function yield()
    if os.clock()-lastYield<0.4 then return end
    if os.queueEvent and os.pullEvent then
        os.queueEvent('__cc_royale_audit_yield');os.pullEvent('__cc_royale_audit_yield')
    elseif sleep then sleep(0) end
    lastYield=os.clock()
end
local function hash(text)
    for i=1,#text do fingerprint=(fingerprint*131+text:byte(i))%2147483647 end
end
print('CC Royale deterministic invariant audit')
print('CODE_REVISION|'..version.read())
print('CLOCK_SOURCE|os.clock: native Lua CPU time; CraftOS computer uptime')
print(('AUDIT_INPUT|matches=%d|seed=%d|cards=%d'):format(count,seed,#pool))
local memorySamples={}
local function memorySample()
    -- Cobalt uses the JVM collector and may expose no collectgarbage API.
    if type(collectgarbage)~='function' then return nil end
    pcall(collectgarbage,'collect')
    local ok,kb=pcall(collectgarbage,'count')
    if ok and util.isFiniteNumber(kb) and kb>=0 then return kb end
end
for match=1,count do
    if match%2==1 then
        local order=benchmark.shuffle(pool,randomInt)
        decks={{},{}}
        for i=1,8 do decks[1][i]=order[i];decks[2][i]=order[i+8] end
    end
    local flipped=match%2==0
    local a,b=decks[flipped and 2 or 1],decks[flipped and 1 or 2]
    local pair=math.floor((match-1)/2)+1
    local state=Runner.run(a,b,{
        gameplaySeed=benchmark.pairedGameplaySeed(seed,pair),
        botOrderOffset=flipped and 1 or 0,
        configure=function(_,bot1,bot2)
            local modes={'easy','normal','hard'}
            local mode=modes[(pair-1)%3+1]
            Bot.setDifficulty(bot1,mode);Bot.setDifficulty(bot2,mode)
        end,
        onTick=function(s)
            diagnostics.assertState(s,('seed=%d match=%d tick=%d'):format(seed,match,s.combatTick))
            ticks=ticks+1
        end,
        yieldFn=yield,
    })
    assert(state.phase=='result' and not tostring(state.resultReason):find('TIMEOUT',1,true))
    outcomes[state.winner or 3]=outcomes[state.winner or 3]+1
    hash(diagnostics.combatSnapshot(state))
    for _,deck in ipairs({a,b}) do for _,id in ipairs(deck) do
        appearances[id]=(appearances[id] or 0)+1
    end end
    if match%50==0 or match==count then
        state=nil
        local kb=memorySample()
        if kb then memorySamples[#memorySamples+1]=kb end
        print(('AUDIT_PROGRESS|matches=%d|ticks=%d|gc_kib=%s'):format(
            match,ticks,kb and ('%.2f'):format(kb) or 'unavailable'))
    end
end
local minimum,maximum=math.huge,0
for _,kb in ipairs(memorySamples) do minimum=math.min(minimum,kb);maximum=math.max(maximum,kb) end
print(('AUDIT_RESULT|matches=%d|p1=%d|p2=%d|draws=%d|ticks=%d|fingerprint=%d|clock_s=%.4f|gc_min_kib=%s|gc_max_kib=%s')
    :format(count,outcomes[1],outcomes[2],outcomes[3],ticks,fingerprint,os.clock()-started,
        #memorySamples>0 and ('%.2f'):format(minimum) or 'unavailable',
        #memorySamples>0 and ('%.2f'):format(maximum) or 'unavailable'))
for _,card in ipairs(cards.list) do print(('AUDIT_CARD|%s|deck_appearances=%d'):format(card.id,appearances[card.id] or 0)) end

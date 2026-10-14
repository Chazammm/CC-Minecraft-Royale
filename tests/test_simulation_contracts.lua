colors={white=1,orange=2,magenta=4,lightBlue=8,yellow=16,lime=32,pink=64,
    gray=128,lightGray=256,cyan=512,purple=1024,blue=2048,brown=4096,
    green=8192,red=16384,black=32768}
local Runner=require('src.headless_match')
local Game=require('src.game')
local cards=require('src.cards')
local benchmark=require('src.benchmark_utils')
local checks,failures=0,0
local function check(ok,message)
    checks=checks+1
    if not ok then failures=failures+1;print('FAIL '..message) end
end
local savedNew=Game.new
local creations=0
check(benchmark.pairedGameplaySeed(9007199254740991,1,1,1)==9502516,
    'Largest exact seed lost a replay bit while adding pair offsets')
check(benchmark.pairedGameplaySeed(-9007199254740991,1,1,1)==2140208948,
    'Negative seed boundary lost a replay bit')
for _,seed in ipairs({1,20261014,-100}) do
    check(benchmark.pairedGameplaySeed(seed,5,3,2)==
        (seed+5*1000003+3*9176+2*104729)%2147483646+1,
        'Ordinary seeds changed during modular reduction')
end
Game.new=function(...) creations=creations+1;return savedNew(...) end
for _,key in ipairs({'dt','gameplaySeed','botOrderOffset','yieldCheckTicks'}) do
    for _,value in ipairs({0/0,math.huge,-math.huge,'invalid'}) do
        local before=creations
        math.randomseed(776);local expected=math.random();math.randomseed(776)
        local ok=pcall(Runner.run,cards.defaultDeck(),cards.defaultDeck(),{[key]=value})
        check(not ok,key..' must reject '..tostring(value))
        check(creations==before,key..' must validate before constructing match')
        check(math.random()==expected,key..' rejection must preserve gameplay RNG')
    end
end
for _,deck in ipairs({false,'invalid',{'zombie'}, {'guardian','skeleton','zombie','creeper',
    'witch','spider','wolf','slime'}, {'missing','skeleton','zombie','creeper',
    'witch','spider','wolf','slime'}, {'zombie','zombie','zombie','zombie',
    'zombie','zombie','zombie','zombie'}}) do
    for owner=1,2 do
        local before=creations
        math.randomseed(901);local expected=math.random();math.randomseed(901)
        local a,b=cards.defaultDeck(),cards.defaultDeck()
        if owner==1 then a=deck else b=deck end
        local ok=pcall(Runner.run,a,b,{gameplaySeed=13})
        check(not ok,'Invalid deck must fail for owner '..owner)
        check(creations==before,'Invalid deck created a match')
        check(math.random()==expected,'Invalid deck reseeded gameplay RNG')
    end
end
Game.new=savedNew
for _,value in ipairs({0/0,math.huge,-math.huge,1e20,'invalid'}) do
    local ok=pcall(benchmark.newRandomInt,value)
    check(not ok,'Deck sampler must reject invalid seed '..tostring(value))
end
for _,spec in ipairs({{'simulate.lua','100','mixed','1e309'},
    {'compare.lua','10','all','1e309'}, {'evo_compare.lua','10','all','1e309'}}) do
    local oldFs,oldPrint=fs,print
    local touched=0
    fs={exists=function()touched=touched+1;return false end,
        open=function()touched=touched+1;return nil end,
        move=function()touched=touched+1 end,delete=function()touched=touched+1 end}
    print=function()end
    local chunk=assert(loadfile(spec[1]));local ok=pcall(chunk,spec[2],spec[3],spec[4])
    fs,print=oldFs,oldPrint
    check(ok and touched==0,spec[1]..' must reject invalid seed before report IO')
end
assert(failures==0,('%d simulation-input checks failed'):format(failures))
print(('Simulation input contracts passed: %d checks'):format(checks))

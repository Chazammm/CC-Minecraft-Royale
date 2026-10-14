-- An ERROR in one mechanics fixture must not change later fixtures' rules.
colors={white=1,orange=2,magenta=4,lightBlue=8,yellow=16,lime=32,pink=64,
    gray=128,lightGray=256,cyan=512,purple=1024,blue=2048,brown=4096,
    green=8192,red=16384,black=32768}
local config=require('config')
local cards=require('src.cards')
local beforeDamage=cards.get('skeleton').unit.damage
local beforeRate=config.TICK_RATE
local cardReference=cards.get('skeleton')
local unitReference=cardReference.unit
local savedFs,savedWrite,savedPrint=fs,write,print
local report
fs={exists=function()return false end,isDir=function()return false end,
    open=function(path,mode)
        if path~='mechanics_report.txt' or mode~='w' then return nil end
        local body=''
        return {write=function(s)body=body..s end,close=function()report=body end}
    end}
write=function()end;print=function()end
local f=assert(io.open('mechanics_test.lua','r'));local source=f:read('*a');f:close()
local injected=[[
runTest('isolation_fault','intentional definition mutation then ERROR',function()
    cards.get('skeleton').unit.damage=999
    cards.get('skeleton').unit={maxHp=1,damage=999}
    config.TICK_RATE=99
    error('intentional mechanics isolation fault')
end)
runTest('isolation_oracle','next case must observe original definitions',function()
    return cards.get('skeleton').unit.damage==30 and config.TICK_RATE==0.10,
        'Original rules restored after failed fixture',{}
end)
]]
local modified,n=source:gsub('local passCount = 0',function()return injected..'\nlocal passCount = 0'end,1)
assert(n==1,'Cannot inject mechanics fault')
local ok,err=pcall(assert(load(modified,'isolation suite','t')))
fs,write,print=savedFs,savedWrite,savedPrint
assert(ok,tostring(err))
assert(report and report:find('RESULT|isolation_fault|ERROR|',1,true),'Fault did not reach exception handler')
assert(report:find('RESULT|isolation_oracle|PASS|',1,true),'One failed test contaminated the next mechanics case')
assert(cards.get('skeleton')==cardReference and cardReference.unit==unitReference,
    'Restoration must retain original card/payload references used by engine and bot')
assert(cardReference.unit.damage==beforeDamage and config.TICK_RATE==beforeRate)
print('Mechanics exception isolation passed (definition values and references restored)')

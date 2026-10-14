colors={white=1,orange=2,magenta=4,lightBlue=8,yellow=16,lime=32,pink=64,
    gray=128,lightGray=256,cyan=512,purple=1024,blue=2048,brown=4096,
    green=8192,red=16384,black=32768}
package.path='./?.lua;./?/init.lua;'..package.path
local cards=require('src.cards')
for _,id in ipairs({'ravager_rider','baby_ender_dragon','minoshroom'}) do
    assert(cards.isSelectable(id),'New playable card missing: '..id)
end
assert(cards.hasEvolution('spider'),'Hero Spider Evolution missing')
local suite=require('src.four_mob_mechanics')
local count=0
for _,case in ipairs(suite.cases) do
    local ok,err=pcall(case.run)
    assert(ok,case.id..': '..tostring(err))
    count=count+1
end
print('Four-mob mechanics passed: '..count..' cases')

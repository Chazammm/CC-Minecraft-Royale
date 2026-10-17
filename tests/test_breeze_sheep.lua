colors={white=1,orange=2,magenta=4,lightBlue=8,yellow=16,lime=32,pink=64,
 gray=128,lightGray=256,cyan=512,purple=1024,blue=2048,brown=4096,green=8192,red=16384,black=32768}
local suite=require('src.breeze_sheep_mechanics')
local failed=0
for _,case in ipairs(suite.cases)do
 local ok,err=pcall(case.run)
 if not ok then failed=failed+1;print('FAIL '..case.id..': '..tostring(err)) end
end
assert(failed==0,tostring(failed)..' Breeze/Sheep cases failed')
print('Breeze/Sheep real-engine mechanics: '..#suite.cases..' cases passed')

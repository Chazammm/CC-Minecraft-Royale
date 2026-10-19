-- Read-only balance reference. Run from repository root; never writes cards.
colors={white=1,orange=2,magenta=4,lightBlue=8,yellow=16,lime=32,pink=64,
 gray=128,lightGray=256,cyan=512,purple=1024,blue=2048,brown=4096,green=8192,red=16384,black=32768}
local function json(v)
 if type(v)=='string' then return '"'..v:gsub('[%z\1-\31\\"]',function(c)return ('\\u%04x'):format(c:byte()) end)..'"' end
 if type(v)=='number' or type(v)=='boolean' then return tostring(v) end
 if type(v)=='nil' then return 'null' end
 local keys={};for k in pairs(v) do keys[#keys+1]=k end;table.sort(keys)
 local array=#v>0;local parts={}
 for _,k in ipairs(keys) do parts[#parts+1]=(array and '' or json(k)..':')..json(v[k]) end
 return (array and '[' or '{')..table.concat(parts,',')..(array and ']' or '}')
end
local snapshot={baseRevision='6e85dc77553bd17422deeb9cb51258cefda06fe5',cards={}}
local cards=require('src.cards')
for _,card in ipairs(cards.list) do snapshot.cards[#snapshot.cards+1]={id=card.id,name=card.name,
 cost=card.cost,kind=card.kind,placement=card.placement,spawnCount=card.spawnCount or 1,
 unit=card.unit,building=card.building,spell=card.spell} end
local f=assert(io.open(assert(arg[1],'Output JSON path required'),'w'));f:write(json(snapshot),'\n');f:close()
print('Read-only reference: '..#snapshot.cards..' current card definitions')

-- Host-only QA: inject into a private sprite slot temporarily, never register a mob.
-- Run from repository root; output path is optional. Requires native debug upvalues.
local root='assets/proposed/custom_mobs/'
local function find(fn,wanted,seen)
    seen=seen or {};if seen[fn] then return end;seen[fn]=true
    for i=1,math.huge do
        local name,value=debug.getupvalue(fn,i);if not name then break end
        if name==wanted then return value end
        if type(value)=='function' then
            local result=find(value,wanted,seen);if result~=nil then return result end
        end
    end
end
local function json(v)
    if type(v)=='string' then return '"'..v:gsub('[%z\1-\31\\"]',function(c)
        return ('\\u%04x'):format(c:byte()) end)..'"' end
    if type(v)=='number' or type(v)=='boolean' then return tostring(v) end
    if v==nil then return 'null' end
    assert(type(v)=='table')
    local keys={};for k in pairs(v) do keys[#keys+1]=k end;table.sort(keys)
    local array=#v>0;local parts={}
    for _,k in ipairs(keys) do parts[#parts+1]=(array and '' or json(k)..':')..json(v[k]) end
    return (array and '[' or '{')..table.concat(parts,',')..(array and ']' or '}')
end
-- Loading art in an empty environment proves it has no startup dependency/effect.
local assets=assert(loadfile(root..'cc_tweaked/sprites.lua','t',{}))()
local keys={}
for key in pairs(assets) do keys[#keys+1]=key end
table.sort(keys)
colors={white=1,orange=2,magenta=4,lightBlue=8,yellow=16,lime=32,pink=64,
    gray=128,lightGray=256,cyan=512,purple=1024,blue=2048,brown=4096,green=8192,red=16384,black=32768}
local arena=require('src.pixel_arena')
local sprites=assert(find(arena.draw,'SPRITES'))
local palette=assert(find(arena.draw,'PALETTE'))
local selectSprite=assert(find(arena.draw,'spriteFor'))
local surface=assert(find(arena.draw,'getSurface'))
local project=assert(find(arena.draw,'worldToPixel'))
local alignX=assert(find(arena.draw,'alignTexelX'))
local alignY=assert(find(arena.draw,'alignTexelY'))
local liveAssets=require('src.mob_assets')
local cards=require('src.cards')
local oldSprites=json(sprites)
local checks=0
local function check(ok,message) checks=checks+1;assert(ok,message) end
local captures={};local count=0

for _ in pairs(assets) do count=count+1 end
check(count==13,'Unexpected asset count')
local loveIndex=assert(loadfile(root..'love2d/index.lua','t',{}))()
for _,key in ipairs({'netherite_crab','king_frog','nether_worm','ore_centipede'}) do
    local meta=assert(loveIndex[key]);local width=(key=='netherite_crab' or key=='ore_centipede') and 384 or 256
    check(meta.file==key..'.png' and meta.width==width and meta.height==256
        and meta.anchorX==width/2 and meta.anchorY==240 and meta.frame=='idle','Invalid LÖVE metadata '..key)
end

for _,key in ipairs(keys) do
    local f=assert(assets[key]);local visible=0
    check(f.width<=16 and f.height<=18 and f.height==#f.rows,'Invalid footprint '..key)
    for _,row in ipairs(f.rows) do
        check(#row==f.width,'Ragged rows '..key)
        for i=1,#row do local t=row:sub(i,i)
            check(t=='.' or palette[t]~=nil,'Invalid token '..t)
            if t~='.' then visible=visible+1 end
        end
    end
    check(visible>30,'Unusable/empty sprite '..key)
    check(not cards.get(key) and not liveAssets.sprites[key], 'Asset became gameplay data '..key)
    check(selectSprite({name=key,visualVariant=key})==sprites.zombie,'Asset registered in normal renderer')
end
local oldWindow,oldClock=window,os.clock
os.clock=function()return 0 end
local records={}
window={create=function(m,_,_,w,h)
    local record=records[m];local y=1
    return {getSize=function()return w,h end,getBackgroundColor=function()return colors.black end,
        setBackgroundColor=function()end,clear=function()end,setCursorPos=function(_,ny)y=ny end,
        blit=function(chars,fg,bg)
            check(#chars==w and #fg==w and #bg==w,'Bad blit dimensions')
            check(not (fg..bg):find('[^0-9a-f]'),'Bad encoded colour')
            record.calls=record.calls+1;record.rows[y]={chars=chars,fg=fg,bg=bg}
        end}
end}
local function signature(record) local a={}
    for i,r in ipairs(record.rows)do a[i]=r.chars..r.fg..r.bg end
    return table.concat(a,'\n')
end
local function copyCanvas(box)
    local a={};for y=1,box.height do a[y]={};for x=1,box.width do a[y][x]=box.canvas[y][x] end end
    return a
end
local function capture(key,viewer,w,h)
    local frame=assets[key];local saved=sprites.__new_mob_preview
    local m={};local record={calls=0,rows={}};records[m]=record
    local rect={x1=1,y1=1,x2=w,y2=h}
    local e={id=1,alive=true,owner=1,x=50,y=40,hp=100,maxHp=100,
        kind='unit',name='Unregistered art',visualVariant='__new_mob_preview'}
    local state={phase='battle',entities={},effects={},projectiles={},visualTime=0}
    local ok,result=pcall(function()
        arena.draw(m,state,viewer,rect)
        local empty=signature(record);local box=surface(m,rect);local terrain=copyCanvas(box)
        sprites.__new_mob_preview=frame;state.entities={e}
        local before=json(state)
        arena.draw(m,state,viewer,rect)
        check(json(state)==before,'Drawing mutated game state')
        local normal=signature(record);check(normal~=empty,'Invisible sprite '..key)
        local cx,cy=project(box,viewer,e.x,e.y)
        local x1,y1=alignX(cx-frame.width/2),alignY(cy-frame.height/2)
        for y,row in ipairs(frame.rows)do for x=1,#row do
            local token=row:sub(x,x);local expected=palette[token] or terrain[y1+y-1][x1+x-1]
            check(box.canvas[y1+y-1][x1+x-1]==expected,'Wrong raster/transparency '..key)
        end end
        local writes=record.calls;arena.draw(m,state,viewer,rect)
        check(record.calls==writes,'Stationary frame missed cache')
        arena.draw(m,state,viewer,rect,true)
        check(signature(record)==normal,'Forced encode differs')
        -- Capture actual emitted terminal sextant bytes, including real terrain/HP.
        local crop={}
        local col1,col2=math.floor((x1-1)/2)-1,math.ceil((x1-1+frame.width)/2)+2
        local row1,row2=math.floor((y1-1)/3)-1,math.ceil((y1-1+frame.height)/3)+1
        for y=row1,row2 do local r=record.rows[y];local bytes={}
            for x=col1,col2 do bytes[#bytes+1]=r.chars:byte(x) end
            crop[#crop+1]={bytes=bytes,fg=r.fg:sub(col1,col2),bg=r.bg:sub(col1,col2)}
        end
        local result={width=frame.width,height=frame.height,rows=frame.rows,terminalCrop=crop,
            origin={x=x1,y=y1},viewer=viewer,monitor={w=w,h=h}}
        local alternatives={netherite_crab='netherite_crab_guard',king_frog='king_frog_tongue',
            nether_worm='nether_worm_bite',ore_centipede='ore_centipede_reserve_0'}
        local alternative=alternatives[key]
        if alternative then
            sprites.__new_mob_preview=assets[alternative];arena.draw(m,state,viewer,rect)
            check(signature(record)~=normal,'Pose change stayed cached '..key)
            sprites.__new_mob_preview=frame;arena.draw(m,state,viewer,rect)
            check(signature(record)==normal,'Pose change left ghosts '..key)
        end
        e.damageFlash=1;arena.draw(m,state,viewer,rect)
        check(signature(record)~=normal,'Missing damage flash')
        for y,row in ipairs(frame.rows)do for x=1,#row do if row:sub(x,x)~='.' then
            check(box.canvas[y1+y-1][x1+x-1]==colors.white,'Flash did not cover opaque pixel')
        end end end
        e.damageFlash=nil;arena.draw(m,state,viewer,rect)
        check(signature(record)==normal,'Flash left ghost pixels')
        e.hp=20;arena.draw(m,state,viewer,rect);check(signature(record)~=normal,'Missing health overlay')
        e.hp=100;e.owner=2;arena.draw(m,state,viewer,rect);check(signature(record)~=normal,'Missing team overlay')
        e.owner=1;e.heroWeb={};arena.draw(m,state,viewer,rect);check(signature(record)~=normal,'Missing web overlay')
        e.heroWeb=nil;arena.draw(m,state,viewer,rect);check(signature(record)==normal,'Overlay not restored')
        e.x=e.x+20;arena.draw(m,state,viewer,rect);check(signature(record)~=normal,'Movement stayed cached')
        e.x=e.x-20;arena.draw(m,state,viewer,rect);check(signature(record)==normal,'Movement round trip left ghosts')
        state.entities={};arena.draw(m,state,viewer,rect);check(signature(record)==empty,'Removal left ghosts')
        return result
    end)
    sprites.__new_mob_preview=saved;arena.invalidate(m);records[m]=nil
    if not ok then error(result,0) end
    return result
end
local monitorCapture
local function captureMonitor()
    local m={};local record={calls=0,rows={}};records[m]=record
    local rect={x1=1,y1=1,x2=51,y2=40}
    local names={'netherite_crab','king_frog','nether_worm','ore_centipede'}
    local positions={{25,40},{75,40},{25,120},{75,120}}
    local state={phase='battle',entities={},effects={},projectiles={},visualTime=0}
    local saved={}
    for i,key in ipairs(names) do
        local slot='__custom_preview_'..key;saved[slot]=sprites[slot];sprites[slot]=assets[key]
        state.entities[i]={id=i,alive=true,owner=i<3 and 1 or 2,x=positions[i][1],y=positions[i][2],
            hp=100,maxHp=100,kind='unit',name='Unregistered art',visualVariant=slot}
    end
    local ok,result=pcall(function()
        local before=json(state);arena.draw(m,state,1,rect)
        check(json(state)==before,'Full monitor mutated state')
        local all={}
        for y=1,40 do
            local line=assert(record.rows[y]);local bytes={}
            for x=1,51 do bytes[x]=line.chars:byte(x) end
            all[y]={bytes=bytes,fg=line.fg,bg=line.bg}
        end
        return {terminalCrop=all,monitor={w=51,h=40},viewer=1,
            pipeline='ACTUAL_ARENA_SPRITE_AND_PIXELBOX',positions=positions,names=names}
    end)
    for _,key in ipairs(names) do local slot='__custom_preview_'..key;sprites[slot]=saved[slot] end
    arena.invalidate(m);records[m]=nil
    if not ok then error(result,0) end
    return result
end
local ok,err=pcall(function()
    monitorCapture=captureMonitor()
    for _,size in ipairs({{45,42},{51,40},{57,62}}) do
        for viewer=1,2 do for _,key in ipairs(keys) do
            local c=capture(key,viewer,size[1],size[2])
            if size[1]==51 and viewer==1 then captures[key]=c end
        end end
    end
end)
window,os.clock=oldWindow,oldClock
if not ok then error(err,0) end
check(json(sprites)==oldSprites,'Existing sprite registry modified')
for _,key in ipairs(keys)do
    check(selectSprite({name=key,visualVariant=key})==sprites.zombie,'Preview leaked into production')
end
local path=arg and arg[1]
if path then local f=assert(io.open(path,'w'));f:write(json(captures),'\n');f:close() end
if arg and arg[2] then local f=assert(io.open(arg[2],'w'));f:write(json(monitorCapture),'\n');f:close() end
print(('13 isolated poses: 78 real-renderer cases, %d checks; palette, transparency, cache, flash, overlays, state and registry intact'):format(checks))
return captures

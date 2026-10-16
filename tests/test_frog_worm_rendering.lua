colors={white=1,orange=2,magenta=4,lightBlue=8,yellow=16,lime=32,pink=64,
 gray=128,lightGray=256,cyan=512,purple=1024,blue=2048,brown=4096,green=8192,red=16384,black=32768}
local Game=require('src.game')
local arena=require('src.pixel_arena')
local art=require('src.assets.custom_mobs.dispatch')
local frames=require('src.assets.custom_mobs.frames')
local diagnostics=require('src.diagnostics')
local function find(fn,wanted,seen)
 seen=seen or {};if seen[fn] then return end;seen[fn]=true
 for i=1,math.huge do local name,value=debug.getupvalue(fn,i);if not name then break end
  if name==wanted then return value end
  if type(value)=='function' then local v=find(value,wanted,seen);if v then return v end end
 end
end
local surface=assert(find(arena.draw,'getSurface'))
local project=assert(find(arena.draw,'worldToPixel'))
local alignX=assert(find(arena.draw,'alignTexelX'))
local alignY=assert(find(arena.draw,'alignTexelY'))
local palette=assert(find(arena.draw,'PALETTE'))
local checks=0
local function check(ok,msg)checks=checks+1;assert(ok,msg)end
for key,frame in pairs(frames) do
 check(frame.width<=16 and frame.height<=18 and frame.height==#frame.rows,'Bad footprint '..key)
 for _,row in ipairs(frame.rows) do
  check(#row==frame.width,'Ragged frame '..key)
  for i=1,#row do local t=row:sub(i,i);check(t=='.' or palette[t]~=nil,'Bad palette token') end
 end
end
local poses={
 {id='king_frog',frame='king_frog'},
 {id='king_frog',frame='king_frog_tongue',windup=true},
 {id='king_frog',frame='king_frog_melee',a={primaryLeft=.3}},
 {id='king_frog',frame='king_frog_walk',a={moving=true,walkTime=.2}},
 {id='nether_worm',frame='nether_worm'},
 {id='nether_worm',frame='nether_worm_bite',a={primaryLeft=.3}},
 {id='nether_worm',frame='nether_worm_move',a={moving=true,walkTime=.2}},
 {id='nether_worm',frame='nether_worm_emerging',emerging=.5},
 {id='nether_worm',frame='nether_worm_warning',warning=true},
}
local oldWindow=window;local records={}
window={create=function(m,_,_,w,h)
 local record=records[m];local y=1
 return {getSize=function()return w,h end,getBackgroundColor=function()return colors.black end,
  setBackgroundColor=function()end,clear=function()end,setCursorPos=function(_,ny)y=ny end,
  blit=function(chars,fg,bg)
   check(#chars==w and #fg==w and #bg==w,'Broken blit row')
   check(not (fg..bg):find('[^0-9a-f]'),'Invalid blit palette')
   record.calls=record.calls+1;record.rows[y]={chars=chars,fg=fg,bg=bg}
  end}
end}
local function signature(record)
 local parts={};for _,r in ipairs(record.rows)do parts[#parts+1]=r.chars..r.fg..r.bg end;return table.concat(parts,'\n')
end
local function terminal(record,col1,col2,row1,row2)
 local result={}
 for y=row1,row2 do local r=record.rows[y];local bytes={}
  for x=col1,col2 do bytes[#bytes+1]=r.chars:byte(x) end
  result[#result+1]={bytes=bytes,fg=r.fg:sub(col1,col2),bg=r.bg:sub(col1,col2)}
 end
 return result
end
local output={captures={}}
local ok,err=pcall(function()
 for _,size in ipairs({{45,42},{51,40},{57,62}}) do for viewer=1,2 do for _,pose in ipairs(poses) do
  local s=Game.new();Game.debugLoadScenario(s,'empty');Game.debugSetPaused(s,false)
  local m={};local record={calls=0,rows={}};records[m]=record
  local rect={x1=1,y1=1,x2=size[1],y2=size[2]}
  arena.draw(m,s,viewer,rect);local empty=signature(record)
  local box=surface(m,rect);local terrain={}
  for y=1,box.height do terrain[y]={};for x=1,box.width do terrain[y][x]=box.canvas[y][x] end end
  local frame=frames[pose.frame];local e
  if pose.warning then
   local p=s.players[1];p.hand[1]='nether_worm';p.queue={'zombie','wolf','skeleton','arrows'}
   assert(Game.playCardFromSlot(s,1,1,50,40));check(#s.entities==0,'Warning became a unit')
  else
   assert(Game.debugSpawnCard(s,1,pose.id,50,40));e=s.entities[1]
   e.emergenceRemaining=pose.emerging;e.visualAnimation=pose.a or {}
   if pose.windup then e.tongueWindup={targetId=999,remaining=.1} end
   s.effects={} -- isolate sprite pixels from the ordinary spawn puff
   local selected,name=art.sprite(e,0);check(name==pose.frame and selected==frame,'Wrong live pose '..pose.frame)
  end
  local before=diagnostics.combatSnapshot(s);arena.draw(m,s,viewer,rect)
  check(before==diagnostics.combatSnapshot(s),'Renderer changed combat')
  local normal=signature(record);check(normal~=empty,'Invisible '..pose.frame)
  local cx,cy=project(box,viewer,50,40);local x1,y1=alignX(cx-frame.width/2),alignY(cy-frame.height/2)
  for y,row in ipairs(frame.rows) do for x=1,#row do
   local token=row:sub(x,x);local expected=palette[token] or terrain[y1+y-1][x1+x-1]
   check(box.canvas[y1+y-1][x1+x-1]==expected,'Actual dispatch/raster/transparency mismatch '..pose.frame)
  end end
  if pose.warning then
   for y=y1-6,y1-1 do for x=x1,x1+frame.width-1 do
    check(box.canvas[y][x]==terrain[y][x],'Warning has an HP bar')
   end end
  end
  local writes=record.calls;arena.draw(m,s,viewer,rect);check(record.calls==writes,'Stationary frame cache')
  arena.draw(m,s,viewer,rect,true);check(signature(record)==normal,'Forced encode parity')
  local col1,col2=math.floor((x1-1)/2)-1,math.ceil((x1-1+frame.width)/2)+2
  local row1,row2=math.floor((y1-1)/3)-1,math.ceil((y1-1+frame.height)/3)+1
  if size[1]==51 and viewer==1 then
   output.captures[pose.frame]={width=frame.width,height=frame.height,rows=frame.rows,
    terminalCrop=terminal(record,col1,col2,row1,row2),pipeline='LIVE_ARENA_AND_PIXELBOX'}
  end
  if e then
   local original=e.visualAnimation;e.visualAnimation={};e.tongueWindup=nil;e.emergenceRemaining=nil
   arena.draw(m,s,viewer,rect);local idle=signature(record)
   e.visualAnimation={primaryLeft=.3};arena.draw(m,s,viewer,rect);check(signature(record)~=idle,'Same-entity pose stayed cached')
   e.visualAnimation={};arena.draw(m,s,viewer,rect);check(signature(record)==idle,'Pose ghost pixels')
   e.damageFlash=1;arena.draw(m,s,viewer,rect);check(signature(record)~=idle,'No hurt flash')
   e.damageFlash=nil;e.hp=20;arena.draw(m,s,viewer,rect);check(signature(record)~=idle,'Missing HP change')
   e.hp=e.maxHp;e.owner=2;arena.draw(m,s,viewer,rect);check(signature(record)~=idle,'Missing team overlay')
   e.owner=1;e.heroWeb={};arena.draw(m,s,viewer,rect);check(signature(record)~=idle,'Missing web overlay')
   e.heroWeb=nil;arena.draw(m,s,viewer,rect);check(signature(record)==idle,'Overlay ghosts')
  end
  Game.debugClearUnits(s);arena.draw(m,s,viewer,rect);check(signature(record)==empty,'Removal ghosts')
  arena.invalidate(m);records[m]=nil
 end end end
 -- Actual gameplay windup plus pending warning on a full virtual arena.
 local s=Game.new();Game.debugLoadScenario(s,'empty');Game.debugSetPaused(s,false)
 assert(Game.debugSpawnCard(s,1,'king_frog',25,110))
 assert(Game.debugSpawnCard(s,2,'zombie',35,110));s.entities[2].passive=true
 assert(Game.debugSpawnCard(s,2,'nether_worm',75,45))
 local p=s.players[2];p.hand[1]='nether_worm';p.queue={'zombie','skeleton','wolf','arrows'}
 assert(Game.playCardFromSlot(s,2,1,25,45));Game.update(s,.1);Game.update(s,.1)
 check(s.entities[1].tongueWindup~=nil and #s.pendingDeployments==1,'Missing live scene states')
 local m={};local record={calls=0,rows={}};records[m]=record
 local before=diagnostics.combatSnapshot(s);arena.draw(m,s,1,{x1=1,y1=1,x2=51,y2=40})
 check(diagnostics.combatSnapshot(s)==before,'Live scene draw changed state')
 output.liveScene={terminalCrop=terminal(record,1,51,1,40),pipeline='LIVE_GAMEPLAY_ARENA_AND_PIXELBOX'}
 arena.invalidate(m);records[m]=nil
end)
window=oldWindow;if not ok then error(err,0) end
local function json(v)
 if type(v)=='string' then return '"'..v:gsub('[%z\1-\31\\"]',function(c)return ('\\u%04x'):format(c:byte())end)..'"' end
 if type(v)=='number' or type(v)=='boolean' then return tostring(v) end
 local keys={};for k in pairs(v)do keys[#keys+1]=k end;table.sort(keys)
 local parts={};for _,k in ipairs(keys)do parts[#parts+1]=(#v>0 and '' or json(k)..':')..json(v[k])end
 return (#v>0 and '[' or '{')..table.concat(parts,',')..(#v>0 and ']' or '}')
end
if arg[1] then local f=assert(io.open(arg[1],'w'));f:write(json(output),'\n');f:close() end
print(('Frog/Worm live renderer: 54 pose/view/size cases + gameplay scene, %d checks'):format(checks))

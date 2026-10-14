colors={white=1,orange=2,magenta=4,lightBlue=8,yellow=16,lime=32,pink=64,
 gray=128,lightGray=256,cyan=512,purple=1024,blue=2048,brown=4096,green=8192,red=16384,black=32768}
package.path='./?.lua;./?/init.lua;'..package.path
local renderer=require('src.pixel_arena')
local assets=require('src.mob_assets')
local approved=require('tests.fixtures.four_mob_approved_pixels')
local Game=require('src.game')
local Render=require('src.render')
local function upvalue(fn,target,seen)
 seen=seen or {};if seen[fn] then return end;seen[fn]=true
 for i=1,math.huge do
  local name,value=debug.getupvalue(fn,i);if not name then break end
  if name==target then return value end
  if type(value)=='function' then local found=upvalue(value,target,seen);if found then return found end end
 end
end
local surface=assert(upvalue(renderer.draw,'getSurface'))
local project=assert(upvalue(renderer.draw,'worldToPixel'))
local alignX=assert(upvalue(renderer.draw,'alignTexelX'))
local alignY=assert(upvalue(renderer.draw,'alignTexelY'))
local palette=assert(upvalue(renderer.draw,'PALETTE'))
local checks=0
local function check(ok,msg) checks=checks+1;assert(ok,msg) end
local oldWindow=window
local records={}
window={create=function(m,_,_,w,h)
 local record=records[m];local y=1
 return {getSize=function()return w,h end,getBackgroundColor=function()return colors.black end,
  setBackgroundColor=function()end,clear=function()end,setCursorPos=function(_,vy)y=vy end,
  blit=function(chars,fg,bg)
   check(#chars==w and #fg==w and #bg==w,'Invalid monitor row length')
   check(not (fg..bg):find('[^0-9a-f]'),'Invalid terminal palette')
   record.calls=record.calls+1;record.rows[y]=chars..'|'..fg..'|'..bg
  end}
end}
local function signature(record)return table.concat(record.rows,'\n')end
local nativeFrames=0
for id,set in pairs(assets.sprites) do
 local original={frames=approved.sprites[id]}
 for name,frame in pairs(set.frames) do
  nativeFrames=nativeFrames+1
  check(table.concat(frame.rows)==table.concat(original.frames[name].rows),'Approved art changed: '..id..'/'..name)
  check(frame.width<=16 and frame.height<=18,'Oversized frame')
  for _,row in ipairs(frame.rows) do check(#row==frame.width,'Ragged frame');check(not row:find('[^KWSDGLBACRYNPMOI%.]'),'Bad source token') end
 end
end
check(nativeFrames==25,'Lost unit frames')
local effectFrames=0
for id,set in pairs(assets.effects) do
 for name,frame in pairs(set.frames) do
  effectFrames=effectFrames+1
  local original=assert(approved.effects[id][name])
  check(frame.width==original.width and frame.height==original.height
   and table.concat(frame.rows)==table.concat(original.rows),'Approved effect pixels changed')
 end
end
check(effectFrames==15,'Lost effect frames')
local poses={
 ravager_rider={
  {name='idle',a={}}, {name='walk_a',a={moving=true,walkTime=0}},
  {name='walk_b',a={moving=true,walkTime=.2}}, {name='building_hit',a={primaryLeft=.3}},
  {name='rider_shot',a={riderLeft=.2}}, {name='combined_hit_shot',a={primaryLeft=.3,riderLeft=.2}},
  {name='rider_reload',a={},riderTargetId=2,riderCooldownLeft=.1},
  {name='building_windup',a={},targetId=2,attackCooldownLeft=.2,initialBuildingImpactUsed=true},
 },
 baby_ender_dragon={
  {name='flight_up',a={},time=0},{name='idle',a={},time=.2},{name='flight_down',a={},time=.4},
  {name='attack_charge',a={},targetId=2,attackCooldownLeft=.1},{name='attack_release',a={primaryLeft=.3}},
 },
 minoshroom={
  {name='idle',a={}},{name='walk_a',a={moving=true,walkTime=0}},
  {name='walk_b',a={moving=true,walkTime=.2}},{name='windup',a={},targetId=2,attackCooldownLeft=.2},
  {name='swing',a={primaryLeft=.3}},{name='recovery',a={primaryLeft=.1}},
 },
 hero_spider={
  {name='idle',a={}},{name='walk_a',a={moving=true,walkTime=0}},
  {name='walk_b',a={moving=true,walkTime=.15}},{name='web_charge',a={webCharging=true},targetId=2,webCooldownLeft=.1},
  {name='web_release',a={webLeft=.2}},{name='melee_bite',a={primaryLeft=.2}},
 },
}
local captures=0
for _,size in ipairs({{45,42},{51,52},{57,62}}) do
 local rect=Render.layoutFor({getSize=function()return size[1],size[2] end}).arena
 for viewer=1,2 do for id,states in pairs(poses) do for _,pose in ipairs(states) do
  local state=Game.new();Game.debugLoadScenario(state,'empty')
  local cardId=id=='hero_spider' and 'evo:spider' or id
  assert(Game.debugSpawnCard(state,1,cardId,50,110))
  state.effects={};local e=state.entities[1];e.visualAnimation=pose.a
  for _,field in ipairs({'targetId','attackCooldownLeft','riderTargetId','riderCooldownLeft','initialBuildingImpactUsed','webCooldownLeft'}) do e[field]=pose[field] end
  state.visualTime=pose.time or 0
  local frame,name=assets.sprite(e,state.visualTime);check(name==pose.name,'Wrong pose '..id..'/'..pose.name)
  local monitor={};local record={calls=0,rows={}};records[monitor]=record
  local roster=state.entities;state.entities={};renderer.draw(monitor,state,viewer,rect)
  local empty=signature(record);state.entities=roster;renderer.draw(monitor,state,viewer,rect)
  check(signature(record)~=empty,'Invisible live model')
  local box=surface(monitor,rect);local cx,cy=project(box,viewer,e.x,e.y)
  local x1,y1=alignX(cx-frame.width/2),alignY(cy-frame.height/2)
  for y,row in ipairs(frame.rows) do for x=1,#row do
   local token=row:sub(x,x)
   if token~='.' then check(box.canvas[y1+y-1][x1+x-1]==palette[token],'Live dispatcher pixel mismatch '..id..'/'..name) end
  end end
  local still=signature(record);local writes=record.calls
  renderer.draw(monitor,state,viewer,rect);check(record.calls==writes,'Static frame missed cache')
  renderer.draw(monitor,state,viewer,rect,true);check(signature(record)==still,'Cached versus forced encode mismatch')
  e.heroWeb={moveFactor=.25,attackFactor=.25};renderer.draw(monitor,state,viewer,rect)
  check(signature(record)~=still,'Permanent web marker invisible')
  e.heroWeb=nil;renderer.draw(monitor,state,viewer,rect);check(signature(record)==still,'Marker left ghost pixels')
  state.entities={};renderer.draw(monitor,state,viewer,rect);check(signature(record)==empty,'Removed unit left ghost pixels')
  captures=captures+1;renderer.invalidate(monitor);records[monitor]=nil
 end end end
end
-- Every new projectile and effect must take the registered raster branch.
for viewer=1,2 do
 for _,kind in ipairs({'rider_bolt','rider_muzzle','ravager_impact','ender_fireball','ender_splash','minoshroom_impact','hero_web','hero_web_hit'}) do
  local m={};local record={calls=0,rows={}};records[m]=record
  local rect={x1=1,y1=1,x2=51,y2=40}
  local s={phase='battle',entities={},effects={},projectiles={},visualTime=0}
  renderer.draw(m,s,viewer,rect);local empty=signature(record)
  local frame=assert(assets.effect(kind,0,0))
  local projectile=kind=='rider_bolt' or kind=='ender_fireball' or kind=='hero_web'
  if projectile then s.projectiles={{alive=true,x=50,y=40,visual=kind}} else s.effects={{kind=kind,x=50,y=40,ttl=.3,duration=.3}} end
  renderer.draw(m,s,viewer,rect);check(signature(record)~=empty,'Invisible FX '..kind)
  local box=surface(m,rect);local cx,cy=project(box,viewer,50,40)
  local x1,y1=alignX(cx-frame.width/2),alignY(cy-frame.height/2)
  for y,row in ipairs(frame.rows) do for x=1,#row do local token=row:sub(x,x)
   if token~='.' then check(box.canvas[y1+y-1][x1+x-1]==palette[token],'Effect fell back to old generic visual') end
  end end
  s.effects={};s.projectiles={};renderer.draw(m,s,viewer,rect);check(signature(record)==empty,'FX ghost pixels')
  renderer.invalidate(m);records[m]=nil
 end
end
window=oldWindow
print(('Four-mob live renderer: %d poses captured, %d checks, 25 approved frames preserved'):format(captures,checks))

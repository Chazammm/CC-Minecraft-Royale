-- Host-only concept probe. Reads unchanged arena internals; never registers a
-- card, replaces a live sprite, or alters the production dispatcher.
local root='assets/proposed/wind_sheep_phantom/'
colors={white=1,orange=2,magenta=4,lightBlue=8,yellow=16,lime=32,pink=64,
 gray=128,lightGray=256,cyan=512,purple=1024,blue=2048,brown=4096,green=8192,red=16384,black=32768}
local arena=require('src.pixel_arena')
local render=require('src.render')
local pixelbox=require('lib.pixelbox_lite')
local cards=require('src.cards')
local config=require('config')
local util=require('src.util')
local function find(fn,wanted,seen)
 seen=seen or {};if seen[fn] then return end;seen[fn]=true
 for i=1,math.huge do
  local name,value=debug.getupvalue(fn,i);if not name then break end
  if name==wanted then return value end
  if type(value)=='function' then local v=find(value,wanted,seen);if v then return v end end
 end
end
local surface=assert(find(arena.draw,'getSurface'))
local project=assert(find(arena.draw,'worldToPixel'))
local alignX=assert(find(arena.draw,'alignTexelX'))
local alignY=assert(find(arena.draw,'alignTexelY'))
local hpBar=assert(find(arena.draw,'drawHp'))
local palette=assert(find(arena.draw,'PALETTE'))
local liveSprites=assert(find(arena.draw,'SPRITES'))
local checks=0
local function check(ok,msg) checks=checks+1;assert(ok,msg) end
local function json(v)
 local t=type(v)
 if t=='string' then return '"'..v:gsub('[%z\1-\31\\"]',function(c)return ('\\u%04x'):format(c:byte())end)..'"' end
 if t=='boolean' then return v and 'true' or 'false' end
 if t=='number' then return ('%.17g'):format(v) end
 if t=='nil' then return 'null' end
 assert(t=='table')
 local keys={};for k in pairs(v) do keys[#keys+1]=k end;table.sort(keys)
 local out={};for _,k in ipairs(keys) do out[#out+1]=(#v>0 and '' or json(k)..':')..json(v[k]) end
 return (#v>0 and '[' or '{')..table.concat(out,',')..(#v>0 and ']' or '}')
end
local initialSprites,initialCards=json(liveSprites),json(cards.list)
local names={'breeze','adventure_sheep','phantom'}
local assets,effects={},{}
for _,key in ipairs(names) do
 assets[key]=assert(loadfile(root..'sprites/'..key..'.lua','t',{}))()
 effects[key]=assert(loadfile(root..'effects/'..key..'.lua','t',{}))()
 check(cards.get(key)==nil,'Concept accidentally registered')
 check(assets[key].runtimeRegistered==false,'Wrong asset phase')
 for _,entry in pairs(assets[key].previewSequences) do for _,step in ipairs(entry) do
  check(assets[key].frames[step.frame]~=nil,'Missing animation frame')
  check(step.durationMs>=100 and step.durationMs%100==0,'Invalid GIF/CC timing')
 end end
end
local variants=assert(loadfile(root..'sprites/sheep_variants.lua','t',{}))()
local records={};local oldWindow=window
window={create=function(m,_,_,w,h)
 local line=1;local rec=records[m]
 return {getSize=function()return w,h end,getBackgroundColor=function()return colors.black end,
  setBackgroundColor=function()end,clear=function()end,setCursorPos=function(_,y)line=y end,
  blit=function(chars,fg,bg)
   check(#chars==w and #fg==w and #bg==w,'Bad terminal row length')
   check(not (fg..bg):find('[^0-9a-f]'),'Bad terminal colors')
   rec.calls=rec.calls+1;rec.rows[line]={chars=chars,fg=fg,bg=bg}
  end}
end}
local function pixels(frame,box,x1,y1,flip)
 for y,row in ipairs(frame.rows) do for x=1,#row do
  local token=row:sub(x,x)
  if token~='.' then
   local px=x1+(flip and frame.width-x or x-1);local py=y1+y-1
   if px>=1 and px<=box.width and py>=1 and py<=box.height then box.canvas[py][px]=assert(palette[token]) end
  end
 end end
end
local function rows(rec,x1,x2,y1,y2)
 local out={}
 for y=y1,y2 do local row=assert(rec.rows[y]);local bytes={}
  for x=x1,x2 do bytes[#bytes+1]=row.chars:byte(x) end
  out[#out+1]={bytes=bytes,fg=row.fg:sub(x1,x2),bg=row.bg:sub(x1,x2)}
 end
 return out
end
local function signature(rec)
 local out={};for _,r in ipairs(rec.rows) do out[#out+1]=r.chars..r.fg..r.bg end;return table.concat(out,'\n')
end
local function validate(frame,icon)
 check(frame.width<=16 and frame.height<=18,'Prototype exceeds established footprint')
 check(#frame.rows==frame.height,'Wrong frame height')
 local painted,transparent=0,0
 for _,row in ipairs(frame.rows) do
  check(#row==frame.width,'Ragged native row')
  for i=1,#row do local token=row:sub(i,i)
   check(token=='.' or palette[token]~=nil,'Invalid native token')
   if token=='.' then transparent=transparent+1 else painted=painted+1 end
  end
 end
 check(painted>0 and transparent>0,'Empty/opaque prototype')
 if icon then check(frame.width==12 and frame.height==12,'Wrong icon footprint') end
end
local function capture(frame,options)
 options=options or {};validate(frame,options.icon)
 local w,h=options.w or 51,options.h or 42
 local viewer,owner=options.viewer or 1,options.owner or 1
 local m={getSize=function()return w,h end};local rec={calls=0,rows={}};records[m]=rec
 local layout=render.layoutFor(m);local rect=layout.arena
 local state={phase='battle',entities={},effects={},projectiles={},visualTime=0}
 local before=json(state)
 arena.draw(m,state,viewer,rect)
 local box=surface(m,rect)
 if options.icon then box:clear(colors.gray);box:render() end
 local blank=signature(rec)
 local cx,cy=project(box,viewer,50,40)
 local x1,y1=alignX(cx-frame.width/2),alignY(cy-frame.height/2)
 local function paint()
  pixels(frame,box,x1,y1,options.flip)
  if options.fx then pixels(options.fx,box,x1+(options.fxX or 16),y1+(options.fxY or 6),false) end
  if options.bar then hpBar(box,{kind='unit',hp=options.hp or 100,maxHp=100,owner=owner},viewer,x1+frame.width/2,y1,frame.width) end
  box:render()
 end
 paint()
 local shown=signature(rec)
 check(shown~=blank,'Invisible concept pose')
 check(before==json(state),'Preview changed live state')
 if not options.flip then for y,row in ipairs(frame.rows) do for x=1,#row do
  local token=row:sub(x,x)
  if token~='.' then check(box.canvas[y1+y-1][x1+x-1]==palette[token],'Bad native overlay pixel at '..x..','..y..' token '..token..' got '..tostring(box.canvas[y1+y-1][x1+x-1])..' expected '..tostring(palette[token])) end
 end end end
 local col1=math.max(1,math.floor((x1-1)/2)-1)
 local col2=math.min(box.width/2,math.ceil((x1-1+frame.width+(options.fxRoom or 0))/2)+2)
 local row1=math.max(1,math.floor((y1-1)/3)-1)
 local row2=math.min(box.height/3,math.ceil((y1-1+frame.height)/3)+2)
 local result={rows=frame.rows,width=frame.width,height=frame.height,
  terminalCrop=rows(rec,col1,col2,row1,row2),viewer=viewer,owner=owner,
  pipeline=options.icon and 'ISOLATED_ICON_ON_CC_GRAY_AND_ACTUAL_PIXELBOX' or 'ISOLATED_NATIVE_OVERLAY_AND_ACTUAL_PIXELBOX',
  monitor={w,h},arenaLogical={box.width,box.height}}
 local calls=rec.calls;paint();check(rec.calls==calls,'Identical overlay retransmitted dirty rows')
 arena.draw(m,state,viewer,rect)
 if options.icon then box:clear(colors.gray) end
 box:render();check(signature(rec)==blank,'Overlay removal left ghost pixels')
 result.clearedCrop=rows(rec,col1,col2,row1,row2)
 arena.invalidate(m);records[m]=nil
 return result
end
local function scene(t,viewer)
 local w,h=51,42
 local m={getSize=function()return w,h end};local rec={calls=0,rows={}};records[m]=rec
 local layout=render.layoutFor(m);local state={phase='battle',entities={},effects={},projectiles={},visualTime=0}
 for i,entry in ipairs({{'Zombie',1,20,104,523},{'Wither Skeleton',2,42,91,470},
   {'Skeleton',2,76,48,168},{'Iron Golem',2,73,20,1514.7},
   {'Blaze',1,79,135,257},{'Wolf',2,9,62,330}}) do
  state.entities[i]={id=i,name=entry[1],owner=entry[2],x=entry[3],y=entry[4],hp=entry[5],maxHp=entry[5],kind='unit',alive=true}
 end
 local before=json(state)
 arena.draw(m,state,viewer,layout.arena)
 local box=surface(m,layout.arena)
 local pose={
  {key='breeze',owner=1,x=22,y=128,frames={'idle','windup','attack','move_a'}},
  {key='adventure_sheep',owner=1,x=47,y=128,frames={'move_a','windup','attack','recovery'}},
  {key='phantom',owner=1,x=73,y=107,frames={'move_a','windup','dive','attack'}},
  {key='breeze',owner=2,x=73,y=67,frames={'move_b','windup','attack','recovery'}},
  {key='adventure_sheep',owner=2,x=47,y=47,frames={'move_b','idle','windup','attack'}},
  {key='phantom',owner=2,x=23,y=42,frames={'move_b','idle','windup','dive'}},
 }
 table.sort(pose,function(a,b)return viewer==1 and a.y<b.y or viewer==2 and a.y>b.y end)
 for _,p in ipairs(pose) do
  local frame=assets[p.key].frames[p.frames[t]];local cx,cy=project(box,viewer,p.x,p.y)
  local x1,y1=alignX(cx-frame.width/2),alignY(cy-frame.height/2)
  local flip=p.key=='adventure_sheep' and p.owner~=viewer
  pixels(frame,box,x1,y1,flip)
  hpBar(box,{kind='unit',hp=100,maxHp=100,owner=p.owner},viewer,x1+frame.width/2,y1,frame.width)
 end
 if t==3 then
  local cx,cy=project(box,viewer,37,125)
  pixels(effects.breeze.frames.wind_gust_a,box,alignX(cx-8),alignY(cy-6),viewer==2)
  cx,cy=project(box,viewer,58,128)
  pixels(effects.adventure_sheep.frames.sword_arc_b,box,alignX(cx-8),alignY(cy-6),viewer==2)
 end
 box:render();check(before==json(state),'Staged scene changed state')
 local out={terminalCrop=rows(rec,1,w,1,layout.arena.y2-layout.arena.y1+1),
   pipeline='STAGED_CONCEPT_OVERLAYS_ON_UNCHANGED_PRODUCTION_ARENA',monitor={w,h},viewer=viewer,
   arenaLogical={box.width,box.height},prototypeCount=#pose,existingUnitCount=#state.entities}
 arena.invalidate(m);records[m]=nil
 return out
end
local output={units={},effects={},variants={},scenes={},showcases={},checks=0,
 baseRevision='e80ad6919b7eb21a1d3464290d177ee3ab210eee',
 classification='ISOLATED_PROTOTYPES_NOT_REGISTERED_NOT_A_COMBAT_SIMULATION',
 reference={cards={},evolutions={},match=config.MATCH,arena=config.ARENA},
 captureCases=0}
local ok,err=pcall(function()
 for _,key in ipairs(names) do
  local asset=assets[key];output.units[key]={frames={},sequences=asset.previewSequences,icon=capture(asset.deckIcon,{icon=true})}
  for pose,frame in pairs(asset.frames) do
   output.units[key].frames[pose]=capture(frame,{bar=not pose:match('^death_')});output.captureCases=output.captureCases+1
   for _,sz in ipairs({{45,42},{57,62}}) do for viewer=1,2 do
    capture(frame,{bar=not pose:match('^death_'),w=sz[1],h=sz[2],viewer=viewer,owner=1});output.captureCases=output.captureCases+1
   end end
  end
  output.units[key].enemy=capture(asset.frames.idle,{bar=true,viewer=1,owner=2})
  output.units[key].mirrored=capture(asset.frames.idle,{bar=true,flip=true})
  output.effects[key]={frames={}}
  for name,frame in pairs(effects[key].frames) do output.effects[key].frames[name]=capture(frame);output.captureCases=output.captureCases+1 end
 end
 local stories={
  breeze={{'idle',350},{'windup',300},{'attack',120,'wind_gust_a'},{'recovery',180,'wind_gust_b'},{'idle',400}},
  adventure_sheep={{'idle',350},{'windup',220},{'attack',100,'sword_arc_a'},{'recovery',180,'sword_arc_b'},{'idle',350}},
  phantom={{'idle_b',350},{'windup',250},{'dive',120},{'attack',100},{'recovery',200},{'move_a',170},{'idle',250}},
 }
 for key,story in pairs(stories) do
  output.showcases[key]={frames={},sequence={}}
  for i,step in ipairs(story) do
   local options={bar=true,fxRoom=key=='phantom' and 0 or 16}
   if step[3] then options.fx=effects[key].frames[step[3]] end
   local id='show_'..i
   output.showcases[key].frames[id]=capture(assets[key].frames[step[1]],options)
   output.showcases[key].sequence[i]={frame=id,durationMs=math.ceil(step[2]/100)*100,pose=step[1]}
   output.captureCases=output.captureCases+1
  end
 end
 for key,frame in pairs(variants.frames) do output.variants[key]=capture(frame,{bar=true}) end
 for viewer=1,2 do output.scenes[tostring(viewer)]={};for t=1,4 do output.scenes[tostring(viewer)][t]=scene(t,viewer) end end
 for _,card in ipairs(cards.list) do output.reference.cards[card.id]={id=card.id,name=card.name,cost=card.cost,kind=card.kind,unit=card.unit,building=card.building,spell=card.spell}
  if card.evolution then local e=cards.evolvedCopy(card.id);output.reference.evolutions[card.id]={name=e.name,cost=e.cost,unit=e.unit,abilities=card.evolution.abilities} end
 end
 check(json(cards.list)==initialCards,'Preview altered card registry')
 check(json(liveSprites)==initialSprites,'Preview altered live sprites')
 output.checks=checks;output.auxiliaryCaptures=11;output.stagedSceneCaptures=8;output.totalProbeCases=output.captureCases+19
end)
window=oldWindow
if not ok then error(err,0) end
local path=assert(arg[1],'Pass output JSON file')
local f=assert(io.open(path,'w'));f:write(json(output),'\n');f:close()
print(('PASS: %d primary/size/view native cases, %d assertions, 37 poses + icons/effects/variants + staged scenes; live registry/sprites unchanged'):format(output.captureCases,checks))

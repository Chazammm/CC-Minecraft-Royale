-- Cosmetic arena paint must preserve logical AND encoded terrain geometry.
colors={white=1,orange=2,magenta=4,lightBlue=8,yellow=16,lime=32,
    pink=64,gray=128,lightGray=256,cyan=512,purple=1024,blue=2048,
    brown=4096,green=8192,red=16384,black=32768}
package.path='./?.lua;./?/init.lua;'..package.path
local config=require('config')
local geometry=require('src.arena')
local Renderer=require('src.render')
local Game=require('src.game')
local skin=require('src.pixel_arena')
local function find(fn,target,seen)
    seen=seen or {}; if seen[fn] then return nil end;seen[fn]=true
    for i=1,255 do
        local name,value=debug.getupvalue(fn,i)
        if not name then break end
        if name==target then return value end
        if type(value)=='function' then
            local result=find(value,target,seen);if result then return result end
        end
    end
end

-- Frozen pre-skin terrain routine, from main before the requested redesign.
-- Remaining renderer code is shared so the oracle exercises real PixelBox.
local legacyTerrain=[[
local function drawTerrain(box)
    box:clear(colors.green)
    local riverY1=1+(A.riverTop/A.height)*(box.height-1)
    local riverY2=1+(A.riverBottom/A.height)*(box.height-1)
    fillRect(box,1,riverY1,box.width,riverY2,colors.blue)
    for _,bx in ipairs(A.bridgeCenters) do
        local x1=1+((bx-A.bridgeHalfWidth)/A.width)*(box.width-1)
        local x2=1+((bx+A.bridgeHalfWidth)/A.width)*(box.width-1)
        fillRect(box,x1,riverY1,x2,riverY2,colors.brown)
        drawLine(box,x1,riverY1,x1,riverY2,colors.gray)
        drawLine(box,x2,riverY1,x2,riverY2,colors.gray)
    end
end
]]
local file=assert(io.open('src/pixel_arena.lua','r'))
local source=file:read('*a');file:close()
local oldSource,replaced=source:gsub(
    'local function drawTerrain%(box%).-\nend\n\nlocal function restoreTerrain',
    legacyTerrain..'\nlocal function restoreTerrain',1)
assert(replaced==1,'Cannot construct the pre-skin terrain oracle')
local legacy=assert(load(oldSource,'legacy arena','t'))()
local paint=find(skin.draw,'drawTerrain')
local oldPaint=find(legacy.draw,'drawTerrain')
local project=find(skin.draw,'worldToPixel')

local A=config.ARENA
assert(A.width==100 and A.height==160 and A.riverTop==74 and A.riverBottom==86)
assert(A.bridgeHalfWidth==7 and #A.bridgeCenters==2)
assert(A.bridgeCenters[1]==27 and A.bridgeCenters[2]==73)
local expectedTowers={{1,'princess',25,132},{1,'princess',75,132},
    {1,'king',50,151},{2,'princess',25,28},{2,'princess',75,28},{2,'king',50,9}}
for i,tower in ipairs(geometry.towerBlueprints()) do
    local e=expectedTowers[i]
    assert(tower.owner==e[1] and tower.towerType==e[2]
        and tower.x==e[3] and tower.y==e[4],'Tower coordinate changed')
end

local role={[colors.green]='land',[colors.lime]='land',[colors.lightGray]='land',
    [colors.blue]='water',[colors.lightBlue]='water',[colors.cyan]='water',
    [colors.brown]='bridge',[colors.gray]='bridge',[colors.orange]='bridge'}
local function canvas(w,h,fn)
    local box={width=w,height=h,canvas={}}
    function box:clear(color)
        for y=1,h do self.canvas[y]={};for x=1,w do self.canvas[y][x]=color end end
    end
    fn(box);return box.canvas
end
local function sameRoles(a,b,w,h)
    for y=1,h do for x=1,w do
        if not role[b[y][x]] or role[a[y][x]]~=role[b[y][x]] then return false,x,y end
    end end
    return true
end
local records=setmetatable({},{__mode='k'})
local oldWindow=window
window={create=function(monitor,_,_,w,h)
    local row=1;local record=records[monitor]
    return {getSize=function()return w,h end,getBackgroundColor=function()return colors.black end,
        setBackgroundColor=function()end,clear=function()end,
        setCursorPos=function(_,y)row=y end,
        blit=function(chars,fg,bg)
            record[row]={chars=chars,fg=fg,bg=bg}
        end}
end}
local function decoded(renderer,rect,player,state,monitor)
    monitor=monitor or {}
    if not records[monitor] then records[monitor]={} end
    renderer.draw(monitor,state or {phase='battle',entities={},projectiles={},effects={}},
        player,rect,true)
    local pixels={}
    for y,line in ipairs(records[monitor]) do
        pixels[y*3-2]={};pixels[y*3-1]={};pixels[y*3]={}
        for x=1,#line.chars do
            local byte=line.chars:byte(x)
            local fg=2^tonumber(line.fg:sub(x,x),16)
            local bg=2^tonumber(line.bg:sub(x,x),16)
            for j=0,5 do
                local foreground=j<5 and byte>=128
                    and math.floor((byte-128)/2^j)%2==1
                pixels[(y-1)*3+math.floor(j/2)+1][(x-1)*2+j%2+1]=foreground and fg or bg
            end
        end
    end
    return pixels
end

local pixelChecks,coordinateChecks,changes=0,0,0
for _,size in ipairs({{45,42},{51,48},{85,60},{143,78}}) do
    local monitor={getSize=function()return size[1],size[2] end}
    local layout=Renderer.layoutFor(monitor)
    local hand=math.min(8,math.max(6,math.floor(size[2]*0.16)))
    local rect=layout.arena
    assert(rect.x1==1 and rect.y1==3 and rect.x2==size[1] and rect.y2==size[2]-hand,
        'Arena/touch rectangle changed')
    assert(layout.hand.y1==rect.y2+1 and layout.hand.y2==size[2], 'Card touch region changed')
    local w,h=size[1]*2,(rect.y2-rect.y1+1)*3
    local original=canvas(w,h,oldPaint)
    local updated=canvas(w,h,paint)
    assert(sameRoles(original,updated,w,h),'Native terrain footprint moved')
    for y=1,h do for x=1,w do
        if original[y][x]~=updated[y][x] then changes=changes+1 end
    end end
    pixelChecks=pixelChecks+w*h
    for player=1,2 do
        local a=decoded(legacy,rect,player)
        local b=decoded(skin,rect,player)
        assert(sameRoles(a,b,w,h),'PixelBox terrain footprint moved')
        pixelChecks=pixelChecks+w*h
        for sx=rect.x1,rect.x2 do for sy=rect.y1,rect.y2 do
            local wx,wy=geometry.screenToWorld(player,sx,sy,rect)
            local ex=(sx-rect.x1)/(rect.x2-rect.x1)*100
            local ey=(sy-rect.y1)/(rect.y2-rect.y1)*160
            if player==2 then ex,ey=100-ex,160-ey end
            assert(math.abs(wx-ex)<1e-10 and math.abs(wy-ey)<1e-10,'Touch coordinate drift')
            coordinateChecks=coordinateChecks+1
        end end
        for wx=0,100,2 do for wy=0,160,2 do
            local px,py=project({width=w,height=h},player,wx,wy)
            local vx,vy=wx,wy;if player==2 then vx,vy=100-wx,160-wy end
            assert(math.abs(px-(1+vx/100*(w-1)))<1e-10
                and math.abs(py-(1+vy/160*(h-1)))<1e-10,'Entity projection drift')
            coordinateChecks=coordinateChecks+1
        end end
    end
    -- Fault injection proves the oracle detects a resized bridge.
    A.bridgeHalfWidth=8
    local invalid=canvas(w,h,paint)
    A.bridgeHalfWidth=7
    assert(not sameRoles(original,invalid,w,h),'Oracle missed a widened bridge')
    -- No paint result may depend on the shared combat RNG.
    math.randomseed(24680);local expected=math.random()
    math.randomseed(24680);canvas(w,h,paint)
    assert(math.random()==expected,'Terrain paint consumed gameplay RNG')
    collectgarbage('collect')
end
assert(changes>0,'Requested appearance did not change')

local function scalars(object)
    local keys={};for key,value in pairs(object) do
        if type(value)=='number' or type(value)=='string' or type(value)=='boolean' then
            keys[#keys+1]=key
        end
    end
    table.sort(keys);local parts={}
    for _,key in ipairs(keys) do
        local value=object[key]
        parts[#parts+1]=key..'='..(type(value)=='number' and ('%.17g'):format(value) or tostring(value))
    end
    return table.concat(parts,';')
end
local function snapshot(state)
    local parts={state.phase,tostring(state.timeLeft),tostring(state.combatTick),tostring(state.nextEntityId)}
    for _,collection in ipairs({state.entities,state.projectiles,state.pendingSpells,state.effects}) do
        for _,object in ipairs(collection) do parts[#parts+1]=scalars(object) end
        parts[#parts+1]='|'
    end
    for _,player in ipairs(state.players) do parts[#parts+1]=scalars(player) end
    return table.concat(parts,'\n')
end
local function simulate(renderer)
    math.randomseed(13579)
    local state=Game.new(nil,{headlessSimulation=true})
    Game.debugLoadScenario(state,'full')
    for owner=1,2 do
        local y=owner==1 and 110 or 50
        for i,id in ipairs({'zombie','skeleton','creeper','iron_golem','blaze','witch'}) do
            assert(Game.debugSpawnCard(state,owner,id,15+i*10,y))
        end
    end
    assert(Game.debugSpawnCard(state,1,'guardian',50,80))
    state.phase='battle';state.adminMode=false;state.adminPaused=false
    local monitor1,monitor2={},{}
    local rect={x1=1,y1=3,x2=51,y2=42}
    local history={}
    for tick=1,240 do
        if tick==40 or tick==70 then
            state.adminMode=true
            local owner,id,y=1,'falling_anvil',50
            if tick==70 then owner,id,y=2,'arrows',110 end
            assert(Game.debugSpawnCard(state,owner,id,50,y))
            state.adminMode=false
        end
        Game.update(state,0.1)
        if renderer and tick%20==0 then
            decoded(renderer,rect,1,state,monitor1)
            decoded(renderer,rect,2,state,monitor2)
        end
        history[tick]=snapshot(state)
    end
    return table.concat(history,'\nTICK\n'),math.random()
end
local without,randomWithout=simulate(nil)
local before,randomBefore=simulate(legacy)
local after,randomAfter=simulate(skin)
assert(before==without and after==without,'Appearance changed simulation state/movement/combat')
assert(randomBefore==randomWithout and randomAfter==randomWithout,'Renderer altered combat RNG stream')
window=oldWindow
print(('Arena skin parity passed (%d terrain pixels, %d coordinate checks, 240 identical combat ticks)')
    :format(pixelChecks,coordinateChecks))

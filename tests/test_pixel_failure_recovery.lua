colors={white=1,orange=2,magenta=4,lightBlue=8,yellow=16,lime=32,pink=64,
    gray=128,lightGray=256,cyan=512,purple=1024,blue=2048,brown=4096,
    green=8192,red=16384,black=32768}
colors.toBlit=function(c)for i=0,15 do if c==2^i then return ('%x'):format(i) end end end
local Game=require('src.game')
local Pixel=require('src.pixel_arena')
local Render=require('src.render')
local savedWindow,savedClock=window,os.clock
os.clock=function()return 0 end
local rows,blits,failNext={},0,false
local width,height,cursor=51,48,1
local monitor={getSize=function()return width,height end,
    setCursorPos=function(_,y)cursor=y end,
    blit=function(chars,fg,bg)
        if failNext then failNext=false;error('injected monitor timeout') end
        blits=blits+1;rows[cursor]=chars..'|'..fg..'|'..bg
    end,
    setBackgroundColor=function()end,setTextColor=function()end,write=function()end}
window={create=function(parent,x1,y1,w,h)
    local x,y=1,1
    return {getSize=function()return w,h end,getBackgroundColor=function()return colors.black end,
        setBackgroundColor=function()end,clear=function()end,
        setCursorPos=function(px,py)x,y=px,py end,
        blit=function(...)parent.setCursorPos(x1+x-1,y1+y-1);parent.blit(...)end}
end}
local state=Game.new(nil,{headlessSimulation=true});Game.startHeadlessBattle(state,0.1)
local rect={x1=1,y1=1,x2=51,y2=40}
for _=1,3 do Pixel.draw(monitor,state,1,rect) end
state.entities[1].hp=100
failNext=true
local failed=not pcall(Pixel.draw,monitor,state,1,rect)
assert(failed,'Fault did not interrupt the changed stationary frame')
local previousBlits=blits
Pixel.draw(monitor,state,1,rect)
assert(blits>previousBlits,'An unacknowledged failed frame was skipped instead of retried')

-- Clear the physical display during resize, then restore the SAME original
-- dimensions. The gameplay scene has not changed and must still be repainted.
state=Game.new(nil,{headlessSimulation=true});Game.startHeadlessBattle(state,0.1)
monitor={getSize=monitor.getSize,setCursorPos=monitor.setCursorPos,blit=monitor.blit,
    setBackgroundColor=monitor.setBackgroundColor,setTextColor=monitor.setTextColor,write=monitor.write}
rows={}
for _=1,3 do Render.draw(monitor,state,1,'test_monitor') end
local expected={};for y,row in pairs(rows) do expected[y]=row end
width,height=20,10;rows={};Render.draw(monitor,state,1,'test_monitor')
width,height=51,48;rows={};Render.draw(monitor,state,1,'test_monitor')
for y=1,48 do assert(rows[y]==expected[y],'Restored monitor row '..y..' is missing or stale') end
window,os.clock=savedWindow,savedClock
print('Pixel failure acknowledgement and same-size monitor recovery passed')

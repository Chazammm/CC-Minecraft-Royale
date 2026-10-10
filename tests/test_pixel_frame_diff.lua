-- PixelBox frame-diff regression for unchanged and changing arena frames.
-- Uses the REAL renderer/PixelBox conversion with a deterministic virtual
-- window. No Minecraft monitor/network assumptions.
colors = {
    white=1,orange=2,magenta=4,lightBlue=8,yellow=16,lime=32,
    pink=64,gray=128,lightGray=256,cyan=512,purple=1024,
    blue=2048,brown=4096,green=8192,red=16384,black=32768,
}
package.path="./?.lua;./?/init.lua;"..package.path
local Game = require("src.game")
local pixelArena = require("src.pixel_arena")
local oldWindow = window
local monitors = {}
window = {create=function(monitor,_,_,w,h)
    local y = 1
    local record = monitors[monitor]
    return {
        getSize=function() return w,h end,
        getBackgroundColor=function() return colors.black end,
        setBackgroundColor=function() end,
        clear=function() end,
        setCursorPos=function(_,vy) y=vy end,
        blit=function(chars,fg,bg)
            record.calls=record.calls+1
            record.rows[y]=chars.."|"..fg.."|"..bg
        end,
    }
end}
local rect={x1=1,y1=3,x2=51,y2=42}
local checks=0
for owner=1,2 do
    local monitor={}
    monitors[monitor]={calls=0,rows={}}
    local record=monitors[monitor]
    local oracleMonitor={}
    monitors[oracleMonitor]={calls=0,rows={}}
    local state=Game.new(nil,{headlessSimulation=true})
    Game.debugLoadScenario(state,"full")
    local function oracle(label)
        pixelArena.draw(oracleMonitor,state,owner,rect,true)
        local actual=table.concat(record.rows,"\n")
        local expected=table.concat(monitors[oracleMonitor].rows,"\n")
        assert(actual==expected,"Pixel-perfect cached/full-encode mismatch: "..label)
        checks=checks+1
    end
    pixelArena.draw(monitor,state,owner,rect)
    oracle("initial")
    assert(record.calls>0,"Initial frame must transmit rows")
    local frame1=table.concat(record.rows,"\n")
    local count=record.calls
    pixelArena.draw(monitor,state,owner,rect)
    oracle("identical")
    assert(record.calls==count,"Identical pixel frame must produce zero new blits")
    checks=checks+1

    assert(Game.debugSpawnCard(state,owner,"creeper",50,100))
    pixelArena.draw(monitor,state,owner,rect)
    oracle("spawn")
    assert(record.calls>count,"Spawn must invalidate arena")
    local frame2=table.concat(record.rows,"\n")
    assert(frame2~=frame1,"Spawn must visibly change pixel output")
    checks=checks+1

    count=record.calls
    pixelArena.draw(monitor,state,owner,rect)
    oracle("static spawned")
    assert(record.calls==count,"Static spawned sprite must not resend")
    checks=checks+1

    -- Effects may change while every unit stays still. Position-only
    -- invalidation is not sufficient: the final-pixel comparison MUST catch
    -- a temporary impact, including its subsequent disappearance.
    count=record.calls
    state.effects[#state.effects+1]={
        kind="hit", x=50, y=100, radius=9, ttl=0.2, owner=2,
    }
    pixelArena.draw(monitor,state,owner,rect)
    oracle("static impact appeared")
    assert(record.calls>count,"Visual effect must invalidate static pixels")
    checks=checks+1
    count=record.calls
    state.effects={}
    pixelArena.draw(monitor,state,owner,rect)
    oracle("static impact disappeared")
    assert(record.calls>count,"Expired visual effect must restore background")
    checks=checks+1

    -- Moving the sprite must redraw old and new footprints.
    for _,entity in ipairs(state.entities) do
        if entity.owner==owner and entity.sourceCardId=="creeper" then
            entity.x=entity.x+20
            entity.y=entity.y-7
        end
    end
    pixelArena.draw(monitor,state,owner,rect)
    oracle("movement")
    assert(record.calls>count,"Unit movement must not be missed by frame cache")
    checks=checks+1

    -- Even an identical canvas MUST be redrawn after countdown text was
    -- overlaid directly onto the terminal during a phase transition.
    count=record.calls
    state.phase="countdown"
    pixelArena.draw(monitor,state,owner,rect)
    oracle("phase transition")
    assert(record.calls>count,"Phase transition must force terminal overwrite")
    checks=checks+1
    count=record.calls
    pixelArena.draw(monitor,state,owner,rect)
    oracle("stable countdown")
    assert(record.calls==count,"Stable countdown canvas should be cached")
    checks=checks+1
end
window=oldWindow
print("PixelBox frame-diff regressions passed ("..checks.." checks)")

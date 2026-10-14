colors={white=1,orange=2,magenta=4,lightBlue=8,yellow=16,lime=32,pink=64,
    gray=128,lightGray=256,cyan=512,purple=1024,blue=2048,brown=4096,
    green=8192,red=16384,black=32768}
colors.toBlit=function(c)
    for i=0,15 do if c==2^i then return ('%x'):format(i) end end
    error('invalid colour')
end
local Game=require('src.game')
local cards=require('src.cards')
local render=require('src.render')
local adminRender=require('src.admin_render')
local diagnostics=require('src.diagnostics')
local checks,failures,windows=0,0,0
local function check(ok,msg)
    checks=checks+1;if not ok then failures=failures+1;print('FAIL '..msg) end
end
local oldWindow=window
window={create=function(_,_,_,w,h)
    windows=windows+1;assert(w>0 and h>0,'invalid arena window')
    return {getSize=function()return w,h end,getBackgroundColor=function()return colors.black end,
        setBackgroundColor=function()end,clear=function()end,setCursorPos=function()end,
        blit=function(chars,fg,bg)assert(#chars==w and #fg==w and #bg==w)end}
end}
local w,h,calls=20,10,0
local monitor={getSize=function()calls=calls+1;return w,h end,
    setBackgroundColor=function()end,setTextColor=function()end,setCursorPos=function()end,
    write=function()end,blit=function(chars,fg,bg)assert(#chars==w and #fg==w and #bg==w)end}
local s=Game.new(nil,{headlessSimulation=true})
Game.startHeadlessBattle(s,0.1)
local before=diagnostics.combatSnapshot(s)
for _,size in ipairs({{20,10},{44,42},{45,41},{1,1},{45,42},{57,52},{20,10},{45,42}}) do
    w,h=size[1],size[2]
    local small=w<45 or h<42
    local layout=render.layoutFor(monitor)
    check((layout.tooSmall==true)==small,'Size guard '..w..'x'..h)
    local previousWindows=windows;local previousCalls=calls
    local ok,err=pcall(render.draw,monitor,s,1,'audit_monitor')
    check(ok,'Render '..w..'x'..h..': '..tostring(err))
    check(calls-previousCalls==1,'Renderer should query peripheral size once per frame')
    if small then
        check(windows==previousWindows,'Small monitor created an arena window')
        local selected=s.players[1].selectedSlot
        Game.handleTouch(s,1,1,h,layout)
        check(s.players[1].selectedSlot==selected,'Invisible small-monitor card zone accepted touch')
        local okAdmin=pcall(adminRender.draw,monitor,s,1,{owner=1,selectedCard='zombie'})
        check(okAdmin,'Admin small-monitor fallback')
    end
    check(diagnostics.combatSnapshot(s)==before,'Rendering altered combat state')
end
window=oldWindow
assert(failures==0,('%d monitor boundary regressions failed'):format(failures))
print(('Monitor resize/interaction boundaries passed: %d checks'):format(checks))

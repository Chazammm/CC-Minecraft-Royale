-- Execute both real entry loops; only external peripherals/render IO are stubbed.
colors={white=1,orange=2,magenta=4,lightBlue=8,yellow=16,lime=32,pink=64,
    gray=128,lightGray=256,cyan=512,purple=1024,blue=2048,brown=4096,
    green=8192,red=16384,black=32768}
local Game=require('src.game')
local normalRender=require('src.render')
local adminRender=require('src.admin_render')
local savedNew=Game.new
local savedStart,savedPull,savedEpoch=os.startTimer,os.pullEventRaw,os.epoch
local savedPrint,savedError,savedFs=print,printError,fs
local savedHardware,savedMusic=package.loaded['src.hardware'],package.loaded['src.music']
local failures,checks=0,0
local function check(ok,msg)checks=checks+1;if not ok then failures=failures+1;savedPrint('FAIL '..msg)end end
for _,entry in ipairs({'main.lua','admin.lua'}) do
    local unavailable=false
    local monitor={getSize=function()if unavailable then error('Monitor detached')end;return 51,52 end}
    local ctx={monitors={monitor,monitor},monitorNames={'left','right'}}
    local cleared,errors,events=0,0,0
    local state
    Game.new=function(...)state=savedNew(...);return state end
    package.loaded['src.hardware']={init=function()return ctx end,
        playerForMonitor=function(_,name)return name=='left' and 1 or 2 end,
        playSound=function()end,clear=function()cleared=cleared+1 end}
    package.loaded['src.music']={new=function()return {}end,handleEvent=function()end,
        stop=function()end,start=function()end,pump=function()end}
    local key=entry=='main.lua' and 'src.render' or 'src.admin_render'
    local actual=entry=='main.lua' and normalRender or adminRender
    package.loaded[key]={layoutFor=actual.layoutFor,draw=function()end}
    fs=nil;print=function()end;printError=function()errors=errors+1 end
    os.epoch=function()return 0 end;os.startTimer=function()return 123 end
    os.pullEventRaw=function()
        events=events+1
        if events==1 then unavailable=true;return 'monitor_touch','left',1,1 end
        return 'terminate'
    end
    local ok,err=pcall(dofile,entry)
    check(ok,entry..' aborted on a queued detached-monitor touch: '..tostring(err))
    check(events==2 and cleared==1,entry..' did not reach clean termination')
    check(state and state.combatTick==0,entry..' advanced gameplay on a rejected touch')
    check(errors==1,entry..' should report the peripheral failure once')
    package.loaded[key]=actual
end
Game.new=savedNew
os.startTimer,os.pullEventRaw,os.epoch=savedStart,savedPull,savedEpoch
print,printError,fs=savedPrint,savedError,savedFs
package.loaded['src.hardware'],package.loaded['src.music']=savedHardware,savedMusic
assert(failures==0,('%d touch disconnect checks failed'):format(failures))
print(('Queued monitor-touch disconnect recovery passed: %d checks'):format(checks))

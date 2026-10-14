-- Exercise the optional subsystem's failure paths without audio/network IO.
local savedFs,savedHttp,savedEpoch=fs,http,os.epoch
local savedMusic,savedManifest,savedDfpwm=package.loaded['src.music'],
    package.loaded['src.music_manifest'],package.loaded['cc.audio.dfpwm']
local failures,checks=0,0
local function check(ok,msg)checks=checks+1;if not ok then failures=failures+1;print('FAIL '..msg)end end
local time=0;os.epoch=function()return time*1000 end
for _,fault in ipairs({'seek_read','open','size','speaker'}) do
    local closed,plays=0,0
    package.loaded['src.music']=nil
    package.loaded['src.music_manifest']={tracks={{id=1,offset=5,bytes=12,pack=1}},
        packs={{path='audit_pack',size=26}},chunkBytes=4,volume=0.1}
    package.loaded['cc.audio.dfpwm']={make_decoder=function()return function(s)return s end end}
    http=nil
    fs={exists=function(p)return p=='audit_pack'end,
        getSize=function()if fault=='size' then error('storage unavailable') end;return 26 end,
        open=function()
            if fault=='open' then error('open failure') end
            return {seek=function()return false end,
                read=function(n)if fault=='seek_read' then error('read failure')end;return ('a'):rep(n) end,
                close=function()closed=closed+1 end}
        end}
    local Music=require('src.music')
    local speaker={playAudio=function()plays=plays+1;if fault=='speaker' then error('detached speaker')end;return true end}
    local ok,controller=pcall(Music.new,speaker,'speaker')
    check(ok,'Optional pack discovery threw '..fault)
    if ok then
        time=0;local started,startResult=pcall(Music.start,controller)
        check(started,'Optional stream start threw '..fault)
        if fault=='seek_read' then check(closed==1 and startResult==false,'Failed seek leaked its handle') end
        if fault=='speaker' and started then
            local before=plays
            for i=1,4 do time=i*0.1;Music.pump(controller) end
            check(plays==before,'Failed pending audio ignored its backoff deadline')
        end
        Music.stop(controller,true)
    end
end
fs,http,os.epoch=savedFs,savedHttp,savedEpoch
package.loaded['src.music'],package.loaded['src.music_manifest'],package.loaded['cc.audio.dfpwm']=
    savedMusic,savedManifest,savedDfpwm
assert(failures==0,('%d optional music faults failed'):format(failures))
print(('Optional music fault isolation passed: %d checks'):format(checks))

-- Deep audit AF-013: a seek() false result must not claim the stream
-- was repositioned; an empty fallback read must always terminate.
colors={white=1,black=32768}
package.path="./?.lua;./?/init.lua;"..package.path

local oldFs=fs
local savedMusic=package.loaded["src.music"]
local savedManifest=package.loaded["src.music_manifest"]
local savedDfpwm=package.loaded["cc.audio.dfpwm"]
local chunks={}
local payload="ABCDEFGHIJKLMNOPQRSTUVWXYZ"

package.loaded["src.music"]=nil
package.loaded["src.music_manifest"]={
    tracks={{id="seek_test",offset=5,bytes=12,pack=1}},
    packs={{path="audit_music_pack.bin",size=#payload}},
    chunkBytes=4,
    volume=0.1,
}
package.loaded["cc.audio.dfpwm"]={
    make_decoder=function()return function(s)return s end end,
}
local forceEmpty=false
fs={
    exists=function(p)return p=="audit_music_pack.bin" end,
    getSize=function()return #payload end,
    open=function(p,mode)
        assert(p=="audit_music_pack.bin" and mode=="rb")
        local pos=0
        return {
            seek=function(whence,offset)
                assert(whence=="set")
                -- Deliberately non-throwing failed seek, as allowed in
                -- wrapper/fault-injection APIs.
                return false
            end,
            read=function(n)
                if forceEmpty then return "" end
                local part=payload:sub(pos+1,pos+n)
                pos=pos+#part
                return #part>0 and part or nil
            end,
            close=function()end,
        }
    end,
}
local Music=require("src.music")
local speaker={playAudio=function(data)
    chunks[#chunks+1]=data
    return true
end}
local m=Music.new(speaker,"audit_speaker")
assert(m.available,"fake local pack source not recognized")
assert(Music.start(m),"music stream must use fallback after false seek")
assert(chunks[1]=="FGHI","false seek must not play from offset 0: "
    ..tostring(chunks[1]))
Music.stop(m,true)

-- Second independent fixture: seek fails; fallback immediately returns an
-- empty string rather than nil (some wrappers do this at EOF). The read must
-- terminate rather than busy-looping or pumping forever.
forceEmpty=true
local m2=Music.new(speaker,"audit_speaker")
assert(not Music.start(m2),"empty seek fallback must fail promptly")
assert(m2.error and m2.error:find("SEEK",1,true),
    "empty fallback should report seek failure")
Music.stop(m2,true)

fs=oldFs
package.loaded["src.music"]=savedMusic
package.loaded["src.music_manifest"]=savedManifest
package.loaded["cc.audio.dfpwm"]=savedDfpwm
print("Music seek fallback failure diagnostics passed")

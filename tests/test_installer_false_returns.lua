-- AF-014 fault injection: installer must honor explicit false returns from
-- fs.delete, fs.write and fs.close before it destroys any previous version.
colors={white=1,black=32768}
package.path="./?.lua;./?/init.lua;"..package.path

local oldFs,oldHttp,oldTextutils,oldWrite=fs,http,textutils,write
local checked=0
local function includes(value,needle)
    assert(tostring(value):find(needle,1,true),
        "Expected "..needle.." in "..tostring(value))
    checked=checked+1
end

do
    local files={[".cc_royale_update"]="EXISTING_LEGACY_STAGE"}
    fs={
        exists=function(p)return files[p]~=nil end,
        isDir=function(p)return p==".cc_royale_update" end,
        delete=function(p)
            if p==".cc_royale_update" then return false end
            files[p]=nil
        end,
    }
    http={get=function()error("reached network before failed cleanup")end}
    local ok,err=pcall(dofile,"install.lua")
    assert(not ok,"installer must reject nonthrowing failed legacy cleanup")
    includes(err,"Could not remove legacy update directory")
    assert(files[".cc_royale_update"]~=nil,"legacy stage was not removed")
end

for _,markerFailure in ipairs({"false_return","silent_truncate"}) do
    local stored={["main.lua"]="VALUABLE_CURRENT"}
    fs={
        exists=function(p)return stored[p]~=nil end,
        isDir=function()return false end,
        getDir=function(p)return p:match("^(.*)/[^/]+$") or "" end,
        makeDir=function()end,
        delete=function(p)stored[p]=nil end,
        open=function(p,mode)
            if mode=="r" then
                if stored[p]==nil then return nil end
                return {readAll=function()return stored[p]end,close=function()end}
            end
            assert(mode=="w","unexpected file mode")
            local buffer=""
            return {
                write=function(v)
                    if p==".cc_royale_installing" then
                        if markerFailure=="false_return" then return false end
                        return nil -- falsely successful but discarded write
                    end
                    buffer=buffer..tostring(v)
                end,
                close=function()
                    stored[p]=buffer
                end,
            }
        end,
    }
    http={
        get=function(opts)
            local url=type(opts)=="table" and opts.url or opts
            local body
            if url:find("/commits/main",1,true) then
                body="FAKE_JSON"
            else
                body="return {}"
            end
            return {
                getResponseCode=function()return 200 end,
                readAll=function()return body end,
                close=function()end,
            }
        end,
    }
    textutils={
        unserializeJSON=function()
            return {sha="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}
        end,
    }
    write=function()end
    local ok,err=pcall(dofile,"install.lua")
    assert(not ok,"installer must stop on failed or silently empty marker: "..markerFailure)
    includes(err,"Could not create install recovery marker")
    assert(stored["main.lua"]=="VALUABLE_CURRENT",
        "no managed file may be replaced without recovery marker")
    checked=checked+1
end

fs,http,textutils,write=oldFs,oldHttp,oldTextutils,oldWrite
print("Installer false-return fault injections passed: "..checked)

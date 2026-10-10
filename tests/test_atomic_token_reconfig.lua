-- AC-021: reconnection with a NEW token must never destroy the existing
-- working token if a power/disk/rename failure happens while replacing it.
package.path="./?.lua;./?/init.lua;"..package.path
local Sync=require("src.report_sync")
local oldFs,oldHttp,oldTextutils,oldWrite,oldRead=fs,http,textutils,write,read
local oldToken="ghp_FAKE_original_credential_for_test_12345"
local newToken="ghp_FAKE_replacement_credential_for_test_67890"
local TOKEN=Sync.tokenPath()
local assertions=0
local function check(ok,msg)
    assert(ok,msg)
    assertions=assertions+1
end
local function scenario(mode)
    local files={[TOKEN]=oldToken.."\n"}
    if mode=="corrupt_active_backup" then
        files[TOKEN]="TRUNCATED"
        files[TOKEN..".bak"]=oldToken.."\n"
    end
    local localDir=true
    fs={
        getDir=function()return ".cc_royale" end,
        exists=function(p)
            if p==".cc_royale" then return localDir end
            return files[p]~=nil
        end,
        isDir=function(p)return p==".cc_royale" end,
        makeDir=function()localDir=true end,
        delete=function(p)files[p]=nil end,
        move=function(from,to)
            if mode=="noop_promotion" and from==TOKEN..".tmp" then
                return nil
            end
            if files[from]==nil then error("missing move source "..from) end
            files[to]=files[from]
            files[from]=nil
        end,
        open=function(p,m)
            if m=="r" then
                if files[p]==nil then return nil end
                return {readAll=function()return files[p]end,close=function()end}
            end
            if m~="w" then error("unexpected mode") end
            local buffer=""
            return {
                write=function(s)
                    if mode=="write_false" or mode=="corrupt_active_backup" then
                        return false
                    end
                    if mode=="truncated_write" then s=s:sub(1,5) end
                    buffer=buffer..s
                end,
                close=function()files[p]=buffer end,
            }
        end,
    }
    http={
        get=function()
            return {
                getResponseCode=function()return 200 end,
                readAll=function()return "FAKE_JSON" end,
                close=function()end,
            }
        end,
    }
    textutils={
        unserializeJSON=function()return {permissions={push=true}}end,
    }
    write=function()end
    read=function()return newToken end
    local ok,msg=Sync.setupInteractive()
    if mode=="normal" then
        check(ok==true,"normal token replacement rejected: "..tostring(msg))
        check(files[TOKEN]==newToken.."\n","new token not committed")
    elseif mode=="corrupt_active_backup" then
        check(ok==false,"corrupt-primary reconfiguration failure must fail")
        check(Sync.readToken()==oldToken,
            "reconfiguration must not destroy valid recovery backup")
        check(files[TOKEN..".bak"]==oldToken.."\n",
            "valid previous credential backup was lost")
    else
        check(ok==false,mode.." must reject failed replacement")
        check(files[TOKEN]==oldToken.."\n",
            mode.." erased or modified previous working credential")
    end
end
for _,mode in ipairs({
    "write_false","truncated_write","noop_promotion",
    "corrupt_active_backup","normal",
}) do
    scenario(mode)
end
fs,http,textutils,write,read=oldFs,oldHttp,oldTextutils,oldWrite,oldRead
print("Atomic token reconfiguration fault scenarios passed: "..assertions)

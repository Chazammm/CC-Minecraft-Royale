-- AF-018: report-sync token setup must not report success when a filesystem
-- write, close, directory creation or postwrite readback fails.
package.path="./?.lua;./?/init.lua;"..package.path
local oldFs,oldHttp,oldTextutils,oldWrite,oldRead=fs,http,textutils,write,read
local Sync=require("src.report_sync")
local TOKEN="ghp_fake_nonsecret_token_for_diagnostics_123"
local checks=0
local function check(x,msg)
    assert(x,msg)
    checks=checks+1
end
local function run(mode)
    local files={}
    local tokenFile=Sync.tokenPath()
    local dirExists=false
    fs={
        getDir=function()return ".cc_royale" end,
        exists=function(p)
            if p==".cc_royale" then return dirExists end
            return files[p]~=nil
        end,
        isDir=function(p)return p==".cc_royale" end,
        makeDir=function(p)
            check(p==".cc_royale","unexpected mkdir")
            if mode=="mkdir_false" then return false end
            dirExists=true
        end,
        delete=function(p)files[p]=nil end,
        move=function(from,to)
            check(files[from]~=nil,"missing move source")
            files[to]=files[from]
            files[from]=nil
        end,
        open=function(p,m)
            check(p==tokenFile or p==tokenFile..".tmp"
                or p==tokenFile..".bak","unexpected token transaction path")
            if m=="w" then
                local buf=""
                return {
                    write=function(x)
                        if mode=="write_false" then return false end
                        buf=buf..x
                    end,
                    close=function()
                        if mode=="close_false" then return false end
                        if mode~="silent_drop" then files[p]=buf end
                    end,
                }
            elseif m=="r" then
                if files[p]==nil then return nil end
                return {readAll=function()return files[p] end,close=function()end}
            end
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
    read=function()return TOKEN end
    local ok,message=Sync.setupInteractive()
    if mode=="normal" then
        check(ok==true,"successful setup rejected: "..tostring(message))
        check(Sync.isConfigured(),"saved valid token not readable")
    else
        check(ok==false,"setup falsely claimed success when mode="..mode)
    end
end
for _,mode in ipairs({"mkdir_false","write_false","close_false","silent_drop","normal"}) do
    run(mode)
end
fs,http,textutils,write,read=oldFs,oldHttp,oldTextutils,oldWrite,oldRead
print("Token setup IO fault tests passed: "..checks)

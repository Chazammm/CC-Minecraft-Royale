-- No network access: fault-inject request/read/close/decode boundaries.
local Sync=require('src.report_sync')
local requests,closed,checks=0,0,0
local token='audit-dummy-token-000000000000'
local oldHttp,oldTextutils=http,textutils
local function check(ok,message) checks=checks+1;assert(ok,message) end
for _,fault in ipairs({'request','code','read','close','json','json_type','permissions_type'}) do
    local before=closed
    http={get=function()
        requests=requests+1
        if fault=='request' then error('request failure') end
        return {
            getResponseCode=function()
                if fault=='code' then error('code failure') end
                return 200
            end,
            readAll=function()
                if fault=='read' then error('read failure') end
                return '{}'
            end,
            close=function()
                closed=closed+1
                if fault=='close' then error('close failure') end
            end,
        }
    end}
    textutils={unserializeJSON=function()
        if fault=='json' then error('decode failure') end
        if fault=='json_type' then return true end
        if fault=='permissions_type' then return {permissions=true} end
        return {permissions={push=true}}
    end}
    local ok,result,err=pcall(Sync.verifyToken,token)
    check(ok and result==false and type(err)=='string',
        fault..' must return a diagnostic rather than throw or claim success')
    check(closed-before==(fault=='request' and 0 or 1),fault..' leaked response')
end
local oldFs=fs
for _,fault in ipairs({'ref','parent','blob','tree','commit'}) do
    local patches=0
    fs={exists=function()return true end,isDir=function()return false end,
        getName=function()return 'mechanics_report.txt' end,
        open=function()return {readAll=function()return 'report body'end,close=function()end}end}
    local function response(tag,code)
        return {getResponseCode=function()return code end,readAll=function()return tag end,
            close=function()closed=closed+1 end}
    end
    http={get=function(spec)
        return response(spec.url:find('/git/ref/',1,true) and 'ref' or 'parent',200)
    end,post=function(spec)
        if spec.method=='PATCH' then patches=patches+1 end
        local tag=spec.url:match('/([^/]+)$')
        return response(({blobs='blob',trees='tree',commits='commit'})[tag] or 'ref_update',201)
    end}
    textutils={serializeJSON=function()return '{}'end,unserializeJSON=function(tag)
        if tag=='ref' then return {object=fault=='ref' and true or {sha='parent-sha'}} end
        if tag=='parent' then return {tree=fault=='parent' and true or {sha='base-tree-sha'}} end
        return {sha=tag==fault and true or 'created-sha'}
    end}
    local ok,result,err=pcall(Sync.upload,'mechanics','mechanics_report.txt',token,'1792000000000')
    check(ok and result==false and type(err)=='string',fault..' invalid nested SHA must fail safely')
    check(patches==0,fault..' attempted a branch write using an invalid response')
end
fs=oldFs;http, textutils=oldHttp,oldTextutils
print(('HTTP boundary faults passed: %d checks, %d requests'):format(checks,requests))

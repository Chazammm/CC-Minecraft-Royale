-- Deep audit AF-015: logout may not say "token removed" if fs.delete
-- explicitly refused deletion without raising. Keep this a zero-network test.
package.path="./?.lua;./?/init.lua;"..package.path
local oldFs=fs
local Sync=require("src.report_sync")
local tokenPath=Sync.tokenPath()
local hasToken=true
local mustFail=true
fs={
    exists=function(p)return p==tokenPath and hasToken end,
    isDir=function()return false end,
    delete=function(p)
        assert(p==tokenPath)
        if mustFail then return false end
        hasToken=false
    end,
}
local ok,err=Sync.clearToken()
assert(ok==false,"logout must not report success when fs.delete returns false")
assert(hasToken,"failed logout must not corrupt token state")
mustFail=false
local cleared=Sync.clearToken()
assert(cleared==true and not hasToken,"working logout should remove token")
-- Transactional token replacement may leave a valid .bak or .tmp
-- after a crash. Logging out must remove ALL credential-bearing files;
-- otherwise old secrets are still stored even after a success message.
do
    local files={
        [tokenPath]="FAKE_ACTIVE_TOKEN",
        [tokenPath..".tmp"]="FAKE_PENDING_TOKEN",
        [tokenPath..".bak"]="FAKE_BACKUP_TOKEN",
    }
    fs={
        exists=function(p)return files[p]~=nil end,
        isDir=function()return false end,
        delete=function(p)files[p]=nil end,
    }
    local loggedOut=Sync.clearToken()
    assert(loggedOut==true,"normal logout should remove token and backup debris")
    assert(files[tokenPath]==nil and files[tokenPath..".tmp"]==nil
        and files[tokenPath..".bak"]==nil,
        "logout left credentials in a transaction backup")
end

fs=oldFs
print("GitHub token logout false-return regression passed")

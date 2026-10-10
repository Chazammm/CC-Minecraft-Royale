-- AC-022: a power loss between token->.bak and .tmp->token must not
-- permanently disable report sync. Reading the verified backup is safe.
package.path="./?.lua;./?/init.lua;"..package.path
local Sync=require("src.report_sync")
local oldFs=fs
local token="ghp_FAKE_existing_recovery_token_1234567"
local path=Sync.tokenPath()
local files={[path..".bak"]=token.."\n"}
fs={
  exists=function(p)return files[p]~=nil end,
  isDir=function()return false end,
  open=function(p,mode)
      if mode~="r" or files[p]==nil then return nil end
      return {readAll=function()return files[p]end,close=function()end}
  end,
}
assert(Sync.isConfigured(),"valid sole token backup must be usable after reboot")
local recovered=Sync.readToken()
assert(recovered==token,"backup credential read must preserve exact token")
assert(files[path..".bak"]==token.."\n","read must not damage recovery copy")
fs=oldFs
print("Interrupted token promotion backup recovery passed")

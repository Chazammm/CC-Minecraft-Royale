-- Audit loop round 1: token active path may be truncated by a crash,
-- while .bak still contains the only usable credential.
package.path="./?.lua;./?/init.lua;"..package.path
local Sync=require("src.report_sync")
local oldFs=fs
local token="ghp_FAKE_valuable_backup_token_123456789"
local path=Sync.tokenPath()
local cases={
  {active="BAD", backup=token.."\n", expect=token},
  {active=nil, backup=token.."\n", expect=token},
  {active="ghp_FAKE_new_valid_token_123456789\n",backup=token.."\n",expect="ghp_FAKE_new_valid_token_123456789"},
}
local count=0
for _,entry in ipairs(cases) do
  local files={
    [path]=entry.active,
    [path..".bak"]=entry.backup,
  }
  fs={
    exists=function(p)return files[p]~=nil end,
    isDir=function()return false end,
    open=function(p,mode)
      assert(mode=="r")
      if not files[p] then return nil end
      return {
        readAll=function()return files[p]end,
        close=function()end,
      }
    end,
  }
  assert(Sync.isConfigured(),"backup fallback must report configured")
  local got=Sync.readToken()
  assert(got==entry.expect,
      "incorrect fallback: expected "..entry.expect.." got "..tostring(got))
  count=count+1
end
fs=oldFs
print("Token degraded-active recovery oracle passed: "..count)

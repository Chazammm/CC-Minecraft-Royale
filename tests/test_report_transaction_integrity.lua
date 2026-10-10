-- AC-023: "successful" report writes/renames may still truncate output.
-- A complete previous report must survive and upload must be refused.
package.path="./?.lua;./?/init.lua;"..package.path
local output=require("src.report_output")
local originalFs=fs
local checks=0
local function eq(a,b,message)
  assert(a==b,(message or "mismatch")..": expected "..tostring(b)..", got "..tostring(a))
  checks=checks+1
end
local function fixture(mode)
  local files={["balance_results.txt"]="VALID PRIOR REPORT"}
  fs={
    exists=function(p)return files[p]~=nil end,
    isDir=function()return false end,
    delete=function(p)files[p]=nil end,
    move=function(from,to)
      if mode=="noop_promote" and from=="balance_results.txt.tmp" then
        return nil
      end
      assert(files[from]~=nil,"missing source "..from)
      files[to]=files[from]
      files[from]=nil
    end,
    open=function(p,m)
      if m=="r" then
        if files[p]==nil then return nil end
        return {readAll=function()return files[p]end,close=function()end}
      end
      assert(m=="w")
      local buffer=""
      return {
        write=function(value)
          if mode=="truncate" and p=="balance_results.txt.tmp" then
            buffer=buffer..tostring(value):sub(1,4)
          else
            buffer=buffer..tostring(value)
          end
        end,
        close=function()files[p]=buffer end,
      }
    end,
  }
  return files
end
for _,mode in ipairs({"truncate","noop_promote","normal"}) do
  local files=fixture(mode)
  local writer=assert(output.start("balance_results.txt"))
  writer.write("COMPLETE NEW REPORT")
  local ok=output.commit("balance_results.txt",writer)
  if mode=="normal" then
    eq(ok,true,"normal publish")
    eq(files["balance_results.txt"],"COMPLETE NEW REPORT","valid committed output")
  else
    eq(ok,false,mode..": must reject false-success file operation")
    eq(files["balance_results.txt"],"VALID PRIOR REPORT",
      mode..": old complete report must survive")
  end
end
fs=originalFs
print("Report publishing integrity oracle passed: "..checks)

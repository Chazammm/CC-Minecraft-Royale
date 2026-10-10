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
-- Start-up recovery is itself transactional. A fake successful no-op move
-- of the only complete .bak must not erase that recoverable copy.
do
  local files={
    ["balance_results.txt.bak"]="GOOD COMPLETE BACKUP",
    ["balance_results.txt.tmp"]="INTERRUPTED PARTIAL",
  }
  fs={
    exists=function(p)return files[p]~=nil end,
    isDir=function()return false end,
    delete=function(p)files[p]=nil end,
    move=function(from,to)
      if from=="balance_results.txt.bak" then return nil end
      assert(files[from]~=nil,"missing source")
      files[to]=files[from]
      files[from]=nil
    end,
    open=function(p,m)
      if m=="r" then
        if files[p]==nil then return nil end
        return {readAll=function()return files[p]end,close=function()end}
      end
      local value=""
      return {
        write=function(s)value=value..s end,
        close=function()files[p]=value end,
      }
    end,
  }
  local writer=output.start("balance_results.txt")
  eq(writer,nil,"no-op backup restore must not claim successful start")
  eq(files["balance_results.txt.bak"],"GOOD COMPLETE BACKUP",
    "failed restore must not delete only good report")
end

-- If the current complete report is temporarily unreadable, a leftover
-- good backup must never be deleted by the next run's startup cleanup.
do
  local files={
    ["balance_results.txt"]="COMPLETE_PRIMARY_STILL_ON_DISK",
    ["balance_results.txt.bak"]="COMPLETE_RECOVERY_BACKUP",
  }
  fs={
    exists=function(p)return files[p]~=nil end,
    isDir=function()return false end,
    delete=function(p)files[p]=nil end,
    move=function(from,to)
      files[to]=files[from]
      files[from]=nil
    end,
    open=function(p,m)
      if m=="r" then
        if p=="balance_results.txt" then return nil end
        if files[p]==nil then return nil end
        return {readAll=function()return files[p]end,close=function()end}
      end
      return {write=function()end,close=function()end}
    end,
  }
  local writer=output.start("balance_results.txt")
  eq(writer,nil,"unreadable active report must block unsafe startup cleanup")
  eq(files["balance_results.txt.bak"],"COMPLETE_RECOVERY_BACKUP",
    "good recovery backup must be retained while primary is unreadable")
  eq(files["balance_results.txt"],"COMPLETE_PRIMARY_STILL_ON_DISK",
    "unreadable active report must remain untouched")
end

fs=originalFs
print("Report publishing integrity oracle passed: "..checks)

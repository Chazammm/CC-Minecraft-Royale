-- Linux adapter for actual CraftOS CLI chunks; reports remain in memory and
-- are written only to the explicitly requested local evidence path afterward.
colors={white=1,orange=2,magenta=4,lightBlue=8,yellow=16,lime=32,pink=64,
    gray=128,lightGray=256,cyan=512,purple=1024,blue=2048,brown=4096,
    green=8192,red=16384,black=32768}
package.path='./?.lua;./?/init.lua;'..package.path
local cliPath,outputPath,revision=arg[1],arg[2],arg[3]
local cliArgs={};for i=4,#arg do cliArgs[#cliArgs+1]=arg[i] end
local files={['.cc_royale_version']=revision}
write=function(value)io.write(tostring(value))end
fs={exists=function(p)return files[p]~=nil end,isDir=function()return false end,
    getName=function(p)return p:match('[^/]+$') end,
    getDir=function(p)return p:match('^(.*)/') or '' end,
    delete=function(p)files[p]=nil end,
    move=function(a,b)assert(files[a] and not files[b]);files[b]=files[a];files[a]=nil end,
    open=function(p,mode)
        if mode=='r' and files[p] then return {readAll=function()return files[p]end,close=function()end} end
        if mode=='w' then
            local body='';return {write=function(s)body=body..s end,
                close=function()files[p]=body end}
        end
    end}
assert(loadfile(cliPath))( (table.unpack or unpack)(cliArgs) )
local map={['simulate.lua']='balance_results.txt',['compare.lua']='comparison_results.txt',
    ['evo_compare.lua']='evolution_results.txt',['mechanics_test.lua']='mechanics_report.txt'}
if map[cliPath] then
    local body=assert(files[map[cliPath]],'Actual CLI failed to commit a complete report')
    local out=assert(io.open(outputPath,'w'));out:write(body);out:close()
end

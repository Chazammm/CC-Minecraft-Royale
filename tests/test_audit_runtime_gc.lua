-- The reusable runtime command must also work on Cobalt, which has no GC API.
colors={white=1,orange=2,magenta=4,lightBlue=8,yellow=16,lime=32,pink=64,
    gray=128,lightGray=256,cyan=512,purple=1024,blue=2048,brown=4096,
    green=8192,red=16384,black=32768}
local savedGc,savedPrint=collectgarbage,print
local checks,failures=0,0
for _,mode in ipairs({'missing','count_only','throws'}) do
    local lines={}
    if mode=='missing' then collectgarbage=nil
    elseif mode=='count_only' then collectgarbage=function(op)
        if op=='count' then return 123 end;error('Unsupported GC option')
    end
    else collectgarbage=function()error('GC unavailable')end end
    print=function(line)lines[#lines+1]=tostring(line)end
    local ok,err=pcall(assert(loadfile('audit_matches.lua')),'1','20261014')
    print=savedPrint;collectgarbage=savedGc
    checks=checks+1
    if not ok then failures=failures+1;print('FAIL '..mode..': '..tostring(err)) end
    local body=table.concat(lines,'\n')
    checks=checks+1
    local expected=mode=='count_only' and 'gc_min_kib=123.00' or 'gc_min_kib=unavailable'
    if not body:find(expected,1,true) then failures=failures+1;print('FAIL dishonest/missing GC summary '..mode) end
end
assert(failures==0,('%d CraftOS GC compatibility checks failed'):format(failures))
print(('CraftOS audit-runner GC compatibility passed: %d checks'):format(checks))

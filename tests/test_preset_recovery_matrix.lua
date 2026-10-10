-- Exhaustive finite-state recovery matrix: absent, valid, readable-corrupt and
-- unreadable final/temp/backup across ALL 5^3 = 125 combinations.
colors=colors or {white=1,orange=2,magenta=4,lightBlue=8,yellow=16,
 lime=32,pink=64,gray=128,lightGray=256,cyan=512,purple=1024,
 blue=2048,brown=4096,green=8192,red=16384,black=32768}
package.path="./?.lua;./?/init.lua;"..package.path
local Cards=require("src.cards")
local Presets=require("src.presets")
local savedFs,savedTextutils=fs,textutils
local names={"deck_presets.db","deck_presets.db.tmp","deck_presets.db.bak"}
local statuses={"absent","A","B","corrupt","unreadable"}
local checks,scenarios=0,0
local function expect(value,message)
    assert(value,message)
    checks=checks+1
end
local validDeck=Cards.defaultDeck()
local function decode(raw)
    if raw=="A" or raw=="B" then
        return {[1]={[1]=validDeck},[2]={}}
    end
end
for i=1,#statuses do
    for j=1,#statuses do
        for k=1,#statuses do
            scenarios=scenarios+1
            local status={statuses[i],statuses[j],statuses[k]}
            local store={}
            local unreadable={}
            for n=1,3 do
                local x=status[n]
                if x=="A" or x=="B" then
                    store[names[n]]=x
                elseif x=="corrupt" then
                    store[names[n]]="NOT_VALID"
                elseif x=="unreadable" then
                    store[names[n]]="POTENTIALLY_GOOD"
                    unreadable[names[n]]=true
                end
            end
            fs={
                exists=function(p)return store[p]~=nil end,
                isDir=function()return false end,
                delete=function(p)store[p]=nil end,
                move=function(from,to)
                    assert(store[from]~=nil,"missing move source: "..from)
                    store[to]=store[from]
                    store[from]=nil
                end,
                open=function(p,mode)
                    if mode~="r" or unreadable[p] or store[p]==nil then
                        return nil
                    end
                    return {
                        readAll=function()return store[p]end,
                        close=function()end,
                    }
                end,
            }
            textutils={unserialize=decode}
            local before={}
            for n=1,3 do before[names[n]]=store[names[n]] end
            local loaded=Presets.load()
            local selected=status[1]=="A" and "A" or status[1]=="B" and "B"
                or status[2]=="A" and "A" or status[2]=="B" and "B"
                or status[3]=="A" and "A" or status[3]=="B" and "B"
            local ctx=table.concat(status,",")
            if selected then
                expect(Cards.isValidDeck(loaded[1][1]),
                    "expected recoverable deck for "..ctx)
                if status[1]~="A" and status[1]~="B"
                    and not unreadable[names[1]]
                then
                    expect(store[names[1]]==selected,
                        "priority recovery not promoted for "..ctx)
                end
            else
                expect(loaded[1][1]==nil,
                    "nonexistent valid deck should stay empty: "..ctx)
            end
            for n=1,3 do
                if unreadable[names[n]] then
                    expect(store[names[n]]==before[names[n]],
                        "unreadable file was deleted by recovery: "..ctx)
                end
            end
        end
    end
end
fs,textutils=savedFs,savedTextutils
print(("Preset recovery matrix passed: %d scenarios / %d assertions")
    :format(scenarios,checks))

-- AC-019/020: actually successful filesystem calls can still leave a partial
-- or absent transaction. Detect silent write truncation, no-op renames,
-- and interrupted promotions WITHOUT discarding the only previous good deck.
colors={white=1,orange=2,magenta=4,lightBlue=8,yellow=16,lime=32,
 pink=64,gray=128,lightGray=256,cyan=512,purple=1024,blue=2048,
 brown=4096,green=8192,red=16384,black=32768}
package.path="./?.lua;./?/init.lua;"..package.path
local cards=require("src.cards")
local Presets=require("src.presets")
local oldFs,oldTextutils=fs,textutils
local checks=0
local function check(ok,msg)
    assert(ok,msg)
    checks=checks+1
end
local function setup(mode)
    local stored={["deck_presets.db"]="VALID_OLD"}
    fs={
        exists=function(p)return stored[p]~=nil end,
        isDir=function()return false end,
        delete=function(p)stored[p]=nil end,
        move=function(from,to)
            if mode=="noop_old_move" and from=="deck_presets.db" then return nil end
            if mode=="noop_new_move" and from=="deck_presets.db.tmp" then return nil end
            assert(stored[from]~=nil,"missing source "..from)
            stored[to]=stored[from]
            stored[from]=nil
        end,
        open=function(p,m)
            if m=="r" then
                if not stored[p] then return nil end
                return {readAll=function()return stored[p] end,close=function()end}
            end
            local buffer=""
            return {
                write=function(s)
                    if mode=="partial_write" and p=="deck_presets.db.tmp" then
                        buffer=buffer..s:sub(1,5)
                    else
                        buffer=buffer..s
                    end
                end,
                close=function()stored[p]=buffer end,
            }
        end,
    }
    textutils={
        serialize=function()return "VALID_NEW_CONTENT" end,
        unserialize=function(s)
            if s=="VALID_OLD" or s=="VALID_NEW_CONTENT" then
                return {[1]={[1]=cards.defaultDeck()},[2]={}}
            end
        end,
    }
    return stored
end

for _,mode in ipairs({"partial_write","noop_old_move","noop_new_move","normal"}) do
    local stored=setup(mode)
    local deck={[1]={[1]=cards.defaultDeck()},[2]={}}
    local ok=Presets.save(deck)
    if mode=="normal" then
        check(ok==true,"normal save must succeed")
        check(stored["deck_presets.db"]=="VALID_NEW_CONTENT","new deck present")
    else
        check(ok==false,mode..": silent disk failure must NOT count as success")
        check(stored["deck_presets.db"]=="VALID_OLD",
            mode..": original deck must stay in final path")
        check(stored["deck_presets.db.bak"]==nil,
            mode..": old deck should not be accidentally abandoned")
    end
end

fs,textutils=oldFs,oldTextutils
print("Preset transaction integrity oracle passed: "..checks)

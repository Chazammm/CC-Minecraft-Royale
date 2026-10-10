-- Deep-audit AF-012: CC-style file APIs may return false instead of throwing.
-- These fault injections MUST NOT accept a failed write/move/delete as a
-- committed preset, or destroy the only complete recoverable backup.
colors = {
    white=1,orange=2,magenta=4,lightBlue=8,yellow=16,lime=32,pink=64,
    gray=128,lightGray=256,cyan=512,purple=1024,blue=2048,brown=4096,
    green=8192,red=16384,black=32768,
}
package.path="./?.lua;./?/init.lua;"..package.path

local cards=require("src.cards")
local presets=require("src.presets")
local oldFs,oldTextutils=fs,textutils
local checks=0

local function eq(a,b,message)
    assert(a==b,(message or "equality")..": expected "..tostring(b)
        ..", got "..tostring(a))
    checks=checks+1
end

local function fixture(files, opts)
    opts=opts or {}
    local stored={}
    for k,v in pairs(files or {}) do stored[k]=v end
    fs={
        exists=function(p)return stored[p]~=nil end,
        isDir=function()return false end,
        open=function(p,mode)
            if mode=="r" then
                if opts.unreadablePath==p then return nil end
                if stored[p]==nil then return nil end
                return {readAll=function()return stored[p] end,close=function()end}
            end
            if mode~="w" then return nil end
            local result=""
            return {
                write=function(v)
                    if opts.falseWrite then return false end
                    result=result..v
                end,
                close=function()
                    if opts.falseClose then return false end
                    stored[p]=result
                end,
            }
        end,
        delete=function(p)
            if opts.falseDelete==p then return false end
            stored[p]=nil
        end,
        move=function(from,to)
            if opts.falseMoveFrom==from then return false end
            assert(stored[from]~=nil,"move source missing: "..from)
            stored[to]=stored[from]
            stored[from]=nil
        end,
    }
    textutils={
        serialize=function()return "NEW_VALID" end,
        unserialize=function(raw)
            if raw=="VALID_BACKUP" or raw=="NEW_VALID"
                or raw=="OLD_VALID"
            then
                return {[1]={[1]=cards.defaultDeck()},[2]={}}
            end
            return nil
        end,
    }
    return stored
end

local deck={[1]={[1]=cards.defaultDeck()},[2]={}}

do
    local stored=fixture({["deck_presets.db"]="OLD_VALID"},
        {falseMoveFrom="deck_presets.db"})
    eq(presets.save(deck),false,"old->backup false return must fail save")
    eq(stored["deck_presets.db"],"OLD_VALID","old final remains")
end

do
    local stored=fixture({["deck_presets.db"]="OLD_VALID"},
        {falseMoveFrom="deck_presets.db.tmp"})
    eq(presets.save(deck),false,"temp->final false return must fail save")
    eq(stored["deck_presets.db"],"OLD_VALID","rollback recovers old final")
    eq(stored["deck_presets.db.bak"],nil,"successful rollback consumed backup")
end

do
    local stored=fixture({["deck_presets.db.tmp"]="NEW_VALID",
        ["deck_presets.db.bak"]="VALID_BACKUP"},
        {falseMoveFrom="deck_presets.db.tmp"})
    local recovered=presets.load()
    eq(cards.isValidDeck(recovered[1][1]),true,"recovered in-memory preset")
    eq(stored["deck_presets.db.bak"],"VALID_BACKUP",
        "failed temp promotion must preserve backup")
    eq(stored["deck_presets.db.tmp"],"NEW_VALID",
        "failed temp promotion must preserve newer temp")
end

do
    local stored=fixture({["deck_presets.db"]="OLD_VALID",
        ["deck_presets.db.bak"]="VALID_BACKUP"},
        {falseDelete="deck_presets.db.bak"})
    eq(presets.save(deck),false,"failed backup delete must block save")
    eq(stored["deck_presets.db"],"OLD_VALID","failed delete keeps final")
    eq(stored["deck_presets.db.bak"],"VALID_BACKUP","failed delete keeps backup")
end

do
    local stored=fixture({["deck_presets.db"]="OLD_VALID"},
        {falseWrite=true})
    eq(presets.save(deck),false,"false-return write must reject save")
    eq(stored["deck_presets.db"],"OLD_VALID","failed write preserves final")
end

do
    local stored=fixture({["deck_presets.db"]="OLD_VALID"},
        {falseClose=true})
    eq(presets.save(deck),false,"false-return close must reject save")
    eq(stored["deck_presets.db"],"OLD_VALID","failed close preserves final")
end

-- The previous fix conservatively rejected any .bak file when the final
-- was missing. A CORRUPT backup, however, is not recoverable: it should
-- not block the user from ever saving a fresh valid deck.
do
    local stored=fixture({["deck_presets.db.bak"]="CORRUPTED"})
    eq(presets.save(deck),true,"invalid orphan backup must not block new saves")
    eq(stored["deck_presets.db"],"NEW_VALID","new valid preset promoted")
end

-- Conversely, a valid orphan .tmp is the only complete copy and must NOT
-- be erased by an attempted save just because no .bak exists.
do
    local stored=fixture({["deck_presets.db.tmp"]="OLD_VALID"})
    eq(presets.save(deck),false,"valid orphan temp must be recovered before save")
    eq(stored["deck_presets.db.tmp"],"OLD_VALID","orphan temp preserved")
end

-- A corrupt final alongside a valid backup must not allow save() to delete
-- the only recoverable deck; load() must repair it first.
do
    local stored=fixture({
        ["deck_presets.db"]="CORRUPTED",
        ["deck_presets.db.bak"]="VALID_BACKUP",
    })
    eq(presets.save(deck),false,"valid backup with invalid final blocks overwrite")
    eq(stored["deck_presets.db.bak"],"VALID_BACKUP",
        "valid backup survived attempted save")
end

-- Do not destroy an unreadable recovery candidate just because its body
-- could not be decoded; on a real computer this may be I/O failure.
do
    local stored=fixture({["deck_presets.db.bak"]="VALID_BACKUP"},
        {unreadablePath="deck_presets.db.bak"})
    eq(presets.save(deck),false,"unreadable orphan backup must be protected")
    eq(stored["deck_presets.db.bak"],"VALID_BACKUP",
        "unreadable backup must not be deleted")
end

-- A clearly corrupt orphan temporary transaction is also nonrecoverable.
-- Do not leave players locked out of saving fresh decks.
do
    local stored=fixture({["deck_presets.db.tmp"]="CORRUPTED"})
    eq(presets.save(deck),true,"invalid orphan temp may be replaced")
    eq(stored["deck_presets.db"],"NEW_VALID",
        "fresh valid final replaces invalid orphan temp")
end

fs,textutils=oldFs,oldTextutils
print("Preset false-return transaction regressions passed: "..checks)

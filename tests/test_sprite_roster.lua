-- The approved art must remain usable through the actual arena/PixelBox path.
colors = {
    white=1,orange=2,magenta=4,lightBlue=8,yellow=16,lime=32,
    pink=64,gray=128,lightGray=256,cyan=512,purple=1024,
    blue=2048,brown=4096,green=8192,red=16384,black=32768,
}
package.path="./?.lua;./?/init.lua;"..package.path
local arena = require("src.pixel_arena")
local config = require("config")

-- Inspect the renderer's real data without adding a production debug API.
local function findUpvalue(fn, target, seen)
    seen = seen or {}
    if seen[fn] then return nil end
    seen[fn] = true
    for i=1,math.huge do
        local name,value = debug.getupvalue(fn,i)
        if not name then break end
        if name == target then return value end
        if type(value) == "function" then
            local found = findUpvalue(value,target,seen)
            if found then return found end
        end
    end
end
local sprites = assert(findUpvalue(arena.draw,"SPRITES"))
local palette = assert(findUpvalue(arena.draw,"PALETTE"))
local mapping = assert(findUpvalue(arena.draw,"NAME_TO_SPRITE"))
local names = {
    "zombie","baby_zombie","skeleton","wither_skeleton","piglin",
    "iron_golem","diamond_golem","snow_golem","creeper","charged_creeper",
    "slime","mini_slime","magma_cube","mini_magma_cube","blaze",
    "witch","evoker","vex","enderman","bat_swarm",
    "spider","wolf","endermite","mega_mite","ghast",
    "guardian","elder_guardian","villager","emerald_bank","pillager_outpost",
    "cannon","nether_portal","ghast_portal","princess_tower","king_tower",
}
local count = 0
for _ in pairs(sprites) do count=count+1 end
assert(count==#names,"Incomplete sprite roster")
local validColors = {}
for _,color in pairs(colors) do validColors[color]=true end
local reverse = {}
for name,key in pairs(mapping) do
    assert(sprites[key],"Name maps to a missing sprite: "..name)
    reverse[key]=name
end
for _,key in ipairs(names) do
    local sprite = assert(sprites[key],"Missing model: "..key)
    assert(sprite.width<=16 and sprite.height<=18,"Oversized arena sprite: "..key)
    assert(sprite.height==#sprite.rows,"Stale normalized height: "..key)
    local visible = 0
    for _,row in ipairs(sprite.rows) do
        assert(#row==sprite.width,"Ragged sprite row: "..key)
        for i=1,#row do
            local token=row:sub(i,i)
            if token~="." then
                assert(token=="T" or validColors[palette[token]],
                    "Invalid native colour in "..key..": "..token)
                visible=visible+1
            end
        end
    end
    assert(visible>=8,"Empty/unusable sprite: "..key)
end

local oldWindow,oldClock = window,os.clock
os.clock=function() return 0 end -- Stable portal shimmer while checking cache.
-- Virtual monitors must be collectible like the renderer's weak-key cache.
-- Keeping all 70 alive causes unnecessary canvas/GC pressure under Lua 5.2.
local records = setmetatable({}, {__mode="k"})
window={create=function(monitor,_,_,w,h)
    local y=1
    local record=records[monitor]
    return {
        getSize=function() return w,h end,
        getBackgroundColor=function() return colors.black end,
        setBackgroundColor=function() end,
        clear=function() end,
        setCursorPos=function(_,vy) y=vy end,
        blit=function(chars,fg,bg)
            assert(#chars==w and #fg==w and #bg==w,"Malformed monitor scanline")
            assert(not fg:find("[^0-9a-f]") and not bg:find("[^0-9a-f]"),
                "Invalid monitor palette encoding")
            record.calls=record.calls+1
            record.rows[y]=chars.."|"..fg.."|"..bg
            record.parts[y]={chars=chars,fg=fg,bg=bg}
        end,
    }
end}
local function snapshot(record) return table.concat(record.rows,"\n") end
local rect={x1=1,y1=1,x2=51,y2=40}
local captures,checks = {},0
local parents={diamond_golem="Iron Golem",charged_creeper="Creeper",
    elder_guardian="Guardian",emerald_bank="Villager",mega_mite="Endermite",
    ghast_portal="Nether Portal"}

for _,key in ipairs(names) do
    local tower=key=="princess_tower" or key=="king_tower"
    for player=1,2 do
        local monitor={}
        local record={calls=0,rows={},parts={}}
        records[monitor]=record
        local state={phase="battle",entities={},projectiles={},effects={}}
        arena.draw(monitor,state,player,rect)
        local empty=snapshot(record)
        local entity={id=1,alive=true,owner=1,x=config.ARENA.width/2,
            y=config.ARENA.height/4,hp=100,maxHp=100,
            name=parents[key] or reverse[key],kind=tower and "tower" or "unit",
            towerType=key=="king_tower" and "king" or "princess",
            visualVariant=parents[key] and key or nil}
        assert(entity.name or tower,"Model cannot be selected by the game: "..key)
        state.entities={entity}
        arena.draw(monitor,state,player,rect)
        local normal=snapshot(record)
        assert(normal~=empty,"Model is invisible through PixelBox: "..key)
        checks=checks+1
        if player==1 then
            local parts={}
            for y,row in ipairs(record.parts) do
                parts[y]={chars=row.chars,fg=row.fg,bg=row.bg}
            end
            captures[key]=parts
        end
        local calls=record.calls
        arena.draw(monitor,state,player,rect)
        assert(record.calls==calls,"Static model defeats frame caching: "..key)
        checks=checks+1
        -- Unknown variants must retain the base-name fallback.
        if not parents[key] and not tower then
            entity.visualVariant="not_a_sprite"
            arena.draw(monitor,state,player,rect)
            assert(snapshot(record)==normal,"Invalid variant changed base model")
            entity.visualVariant=nil
            checks=checks+1
        end
        if parents[key] then
            entity.visualVariant=nil
            arena.draw(monitor,state,player,rect)
            assert(snapshot(record)~=normal,"Evolution is indistinguishable: "..key)
            entity.visualVariant=key
            checks=checks+1
        end
        entity.damageFlash=1
        arena.draw(monitor,state,player,rect)
        assert(snapshot(record)~=normal,"Damage flash is invisible: "..key)
        entity.damageFlash=nil
        arena.draw(monitor,state,player,rect)
        assert(snapshot(record)==normal,"Damage flash did not clear: "..key)
        checks=checks+2
        entity.hp=20
        arena.draw(monitor,state,player,rect)
        assert(snapshot(record)~=normal,"Health/team overlay missing: "..key)
        entity.hp=100
        entity.owner=2
        arena.draw(monitor,state,player,rect)
        assert(snapshot(record)~=normal,"Team identity disappeared: "..key)
        checks=checks+2
        state.entities={}
        arena.draw(monitor,state,player,rect)
        assert(snapshot(record)==empty,"Removed model left ghost pixels: "..key)
        checks=checks+1
        records[monitor]=nil
    end
end
window,os.clock=oldWindow,oldClock
print("Native sprite roster passed (35 models, "..checks.." renderer checks)")
return {sprites=sprites,captures=captures,names=names}

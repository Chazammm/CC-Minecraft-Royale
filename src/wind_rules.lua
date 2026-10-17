-- Bounded deterministic displacement. No RNG, renderer, or targeting changes.
local arena=require('src.arena')
local config=require('config')
local modifiers=require('src.combat_modifiers')
local spatial=require('src.spatial')
local rules={}

local function bridgeChoice(entity,target)
    if not target or not target.alive then return nil end
    local a=config.ARENA
    local es=entity.y<a.riverTop and -1 or (entity.y>a.riverBottom and 1 or 0)
    local ts=target.y<a.riverTop and -1 or (target.y>a.riverBottom and 1 or 0)
    if ts~=0 and es~=ts then return (arena.navigationPoint(entity,target)) end
end

function rules.apply(state,projectile,target)
    local spec=projectile.windBurst
    if not spec or not target or not target.alive or target.owner==projectile.owner
        or target.kind~='unit' or target.flying or target.waterOnly
        or (target.windImmunityRemaining or 0)>1e-9 then return 0 end
    local travel=math.min(spec.maxDistance,math.max(0,modifiers.moveSpeed(target))*spec.moveSeconds)
    if travel<=1e-9 then return 0 end
    local source=state.entityById[projectile.sourceEntityId]
    local sx,sy=projectile.windOriginX,projectile.windOriginY
    if source and source.alive then sx,sy=source.x,source.y end
    local dx,dy=target.x-sx,target.y-sy
    local length=math.sqrt(dx*dx+dy*dy)
    if length<=1e-9 then return 0 end
    local victimTarget=state.entityById[target.lockedTargetId or target.targetId]
    -- One scratch entity per push, not one allocation per sampled step.
    local probe={x=target.x,y=target.y,owner=target.owner}
    local bridge=bridgeChoice(probe,victimTarget)
    local x,y=target.x,target.y
    for i=1,math.ceil(travel/spec.step) do
        local d=math.min(travel,i*spec.step)
        local nx,ny=target.x+dx/length*d,target.y+dy/length*d
        if not arena.isWalkable(target,nx,ny) then break end
        probe.x,probe.y=nx,ny
        local nextBridge=bridgeChoice(probe,victimTarget)
        if bridge and nextBridge and nextBridge~=bridge then break end
        bridge=bridge or nextBridge
        x,y=nx,ny
    end
    local distance=math.sqrt((x-target.x)^2+(y-target.y)^2)
    if distance>1e-9 then
        target.x,target.y=x,y
        target.windImmunityRemaining=spec.immunity
        spatial.index(state,target)
    end
    return distance
end
return rules

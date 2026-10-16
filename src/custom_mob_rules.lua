-- Shared deterministic rules; no rendering, clocks, RNG or Game dependency.
local arena = require('src.arena')
local rules = {}
function rules.hookEligible(source, target)
    return target and target.alive and source.owner ~= target.owner
        and target.kind == 'unit' and not target.flying and not target.waterOnly
end
function rules.pullPosition(source, target, spec)
    local dx,dy=source.x-target.x,source.y-target.y
    local distance=math.sqrt(dx*dx+dy*dy)
    local travel=math.min(spec.maxPullDistance,math.max(0,distance-spec.stopRange))
    if travel<=1e-9 then return target.x,target.y end
    local steps=math.ceil(travel/.5)
    local x,y=target.x,target.y
    for i=1,steps do
        local d=math.min(travel,i*.5)
        local nx,ny=target.x+dx/distance*d,target.y+dy/distance*d
        if not arena.isWalkable(target,nx,ny) then break end
        x,y=nx,ny
    end
    return x,y
end
function rules.wormDamage(source,target)
    local damage=source.damage or 0
    if target.kind=='tower' then return damage*source.burrow.towerMultiplier end
    if target.kind=='unit' and not source.wormOpenerUsed and (source.wormOpenerRemaining or 0)>0 then
        source.wormOpenerUsed=true
        return damage+source.burrow.openerBonus
    end
    return damage
end
return rules

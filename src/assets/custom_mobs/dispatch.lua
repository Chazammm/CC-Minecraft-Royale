local frames=require('src.assets.custom_mobs.frames')
local art={frames=frames}
function art.sprite(entity,clock)
    local key=entity.visualVariant
    local a=entity.visualAnimation or {}
    if key=='king_frog' or entity.name=='King Frog' then
        local pose=entity.tongueWindup and 'king_frog_tongue'
            or ((a.tongueLeft or 0)>0 and 'king_frog_tongue')
            or ((a.primaryLeft or 0)>0 and 'king_frog_melee')
            or (a.moving and math.floor((a.walkTime or 0)*6)%2==1 and 'king_frog_walk')
            or 'king_frog'
        return frames[pose],pose
    elseif key=='nether_worm' or entity.name=='Nether Worm' then
        local pose=(entity.emergenceRemaining and 'nether_worm_emerging')
            or ((a.primaryLeft or 0)>0 and 'nether_worm_bite')
            or (a.moving and math.floor((a.walkTime or 0)*7)%2==1 and 'nether_worm_move')
            or 'nether_worm'
        return frames[pose],pose
    end
end
function art.effect(kind)
    if kind=='nether_worm_warning' then return frames.nether_worm_warning end
end
return art

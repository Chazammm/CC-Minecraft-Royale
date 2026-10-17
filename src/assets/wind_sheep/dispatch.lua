local sets={breeze=require('src.assets.wind_sheep.breeze'),adventure_sheep=require('src.assets.wind_sheep.adventure_sheep')}
local wind=require('src.assets.wind_sheep.breeze_effects').frames
local sword=require('src.assets.wind_sheep.sheep_effects').frames
local art={sprites=sets}
function art.sprite(entity,clock)
    local key=sets[entity.visualVariant] and entity.visualVariant
        or (entity.name=='Breeze' and 'breeze') or (entity.name=='Adventure Sheep' and 'adventure_sheep')
    if not key then return end
    local a=entity.visualAnimation or {};local pose='idle'
    if (a.primaryLeft or 0)>.15 then pose='attack'
    elseif (a.primaryLeft or 0)>0 then pose='recovery'
    elseif a.moving then pose=math.floor((a.walkTime or 0)*6)%2==0 and 'move_a' or 'move_b'
    elseif entity.targetId and (entity.attackCooldownLeft or 0)<=.3
        and (key=='adventure_sheep' or (entity.windShotsFired or 0)%3==2) then pose='windup'
    elseif key=='breeze' and math.floor((clock or 0)*3)%2==1 then pose='idle_b' end
    return sets[key].frames[pose],key..'_'..pose
end
function art.effect(kind,clock,progress)
    local second=(progress and progress>=.5) or (not progress and math.floor((clock or 0)*8)%2==1)
    if kind=='breeze_shot' then return wind.wind_shot
    elseif kind=='breeze_gust' then return wind[second and 'wind_gust_b' or 'wind_gust_a']
    elseif kind=='sheep_sword' then return sword[second and 'sword_arc_b' or 'sword_arc_a']
    elseif kind=='breeze_death' or kind=='sheep_death' then
        local set=kind=='breeze_death' and sets.breeze or sets.adventure_sheep
        local phase=(progress or 0)<1/3 and 'death_a' or ((progress or 0)<2/3 and 'death_b' or 'death_c')
        return set.frames[phase]
    end
end
return art

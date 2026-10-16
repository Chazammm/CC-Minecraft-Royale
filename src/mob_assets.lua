-- Load only native Lua rasters once. PNG/GIF previews are never runtime inputs.
local custom = require('src.assets.custom_mobs.dispatch')
local assets = {
    ravager_rider = require('src.assets.four_mobs.sprites.ravager_rider'),
    baby_ender_dragon = require('src.assets.four_mobs.sprites.baby_ender_dragon'),
    minoshroom = require('src.assets.four_mobs.sprites.minoshroom'),
    hero_spider = require('src.assets.four_mobs.sprites.hero_spider'),
}
local effects = {
    ravager_rider = require('src.assets.four_mobs.effects.ravager_rider'),
    baby_ender_dragon = require('src.assets.four_mobs.effects.baby_ender_dragon'),
    minoshroom = require('src.assets.four_mobs.effects.minoshroom'),
    hero_spider = require('src.assets.four_mobs.effects.hero_spider'),
}
local names = {['Ravager Rider']='ravager_rider',['Baby Ender Dragon']='baby_ender_dragon',
    Minoshroom='minoshroom',['Hero Spider']='hero_spider'}
local module = { sprites=assets, effects=effects }
local flightCycle=assets.baby_ender_dragon.previewSequences.fly
local flightDuration=0
for _,entry in ipairs(flightCycle) do flightDuration=flightDuration+entry.durationMs end
local function flightFrame(clock)
    local remaining=((clock or 0)*1000)%flightDuration
    for _,entry in ipairs(flightCycle) do
        if remaining<entry.durationMs then return entry.frame end
        remaining=remaining-entry.durationMs
    end
    return flightCycle[1].frame
end
function module.sprite(entity, clock)
    local frame,pose=custom.sprite(entity,clock)
    if frame then return frame,pose end
    local key=assets[entity.visualVariant] and entity.visualVariant or names[entity.name]
    local set=key and assets[key]
    if not set then return nil end
    local a=entity.visualAnimation or {}
    local primary=(a.primaryLeft or 0)>0
    local pose='idle'
    if key=='ravager_rider' then
        local shot=(a.riderLeft or 0)>0
        if primary and shot then pose='combined_hit_shot'
        elseif shot then pose='rider_shot'
        elseif primary then pose='building_hit'
        elseif a.moving then pose=math.floor((a.walkTime or 0)*6)%2==0 and 'walk_a' or 'walk_b'
        elseif entity.riderTargetId and (entity.riderCooldownLeft or 0)<.2 then pose='rider_reload'
        elseif entity.targetId and (entity.attackCooldownLeft or 0)<.3 and entity.initialBuildingImpactUsed then pose='building_windup' end
    elseif key=='baby_ender_dragon' then
        if primary then pose='attack_release'
        elseif entity.targetId and (entity.attackCooldownLeft or 0)<.2 then pose='attack_charge'
        else pose=flightFrame(clock) end
    elseif key=='minoshroom' then
        if primary then pose=(a.primaryLeft or 0)>.15 and 'swing' or 'recovery'
        elseif a.moving then pose=math.floor((a.walkTime or 0)*5)%2==0 and 'walk_a' or 'walk_b'
        elseif entity.targetId and (entity.attackCooldownLeft or 0)<.35 then pose='windup' end
    else
        if (a.webLeft or 0)>0 then pose='web_release'
        elseif primary then pose='melee_bite'
        elseif a.webCharging then pose='web_charge'
        elseif a.moving then pose=math.floor((a.walkTime or 0)*8)%2==0 and 'walk_a' or 'walk_b' end
    end
    return assert(set.frames[pose]),pose
end
function module.effect(kind, clock, progress)
    local frame=custom.effect(kind)
    if frame then return frame end
    local second=(progress and progress>=.5) or (not progress and math.floor((clock or 0)*8)%2==1)
    if kind=='rider_bolt' then return effects.ravager_rider.frames.crossbow_bolt
    elseif kind=='rider_muzzle' then return effects.ravager_rider.frames.muzzle
    elseif kind=='ravager_impact' then return effects.ravager_rider.frames[second and 'initial_impact_b' or 'initial_impact_a']
    elseif kind=='ender_fireball' then return effects.baby_ender_dragon.frames[second and 'fireball_b' or 'fireball_a']
    elseif kind=='ender_splash' then return effects.baby_ender_dragon.frames[second and 'splash_b' or 'splash_a']
    elseif kind=='minoshroom_impact' then return effects.minoshroom.frames[second and 'axe_hit_b' or 'axe_hit_a']
    elseif kind=='hero_web' then return effects.hero_spider.frames[second and 'web_projectile_b' or 'web_projectile_a']
    elseif kind=='hero_web_hit' then return effects.hero_spider.frames[second and 'web_hit_b' or 'web_hit_a']
    elseif kind=='hero_web_status' then return effects.hero_spider.frames.web_status end
end
return module

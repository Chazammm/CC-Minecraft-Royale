local H=require('assets.proposed.four_mobs_phase1.tools.harness')
local cards=require('src.cards')
local config=require('config')
local names={'ravager_rider','baby_ender_dragon','minoshroom','hero_spider'}
local function capture(frame,kind,options)
    local result=H.capture(frame,kind,options)
    result.canvas=nil;result.terminal=nil
    return result
end
local output={units={},effects={},reference={},baselineRevision='4490cbdd00c2a7995155eb6bcb5828b3ac65d04e'}
for _,name in ipairs(names)do
    local asset=H.read('sprites',name);local fx=H.read('effects',name)
    output.units[name]={frames={},sequences=asset.previewSequences}
    output.effects[name]={frames={}}
    for key,frame in pairs(asset.frames)do output.units[name].frames[key]=capture(frame,'unit')end
    for key,frame in pairs(fx.frames)do output.effects[name].frames[key]=capture(frame,'effect')end
end
output.comparison={spider=capture(H.sprites.spider,'unit')}
output.webOnZombie=capture(H.read('effects','hero_spider').frames.web_hit_a,'effect',{target=true})
for _,name in ipairs({'zombie','iron_golem','wither_skeleton','blaze','bat_swarm','skeleton','spider'})do
    local card=cards.get(name);output.reference[name]={cost=card.cost,unit=card.unit}
end
output.reference.diamond_golem=cards.evolvedCopy('iron_golem')
output.reference.ghast=cards.internalUnits.ghast
output.reference.match=config.MATCH
local Game=require('src.game')
local state=Game.new(nil,{headlessSimulation=true})
assert(Game.startHeadlessBattle(state,config.TICK_RATE))
output.reference.towers={}
for _,entity in ipairs(state.entities)do if entity.owner==1 and entity.kind=='tower' then
    output.reference.towers[entity.towerType]={maxHp=entity.maxHp,damage=entity.damage,
        attackCooldown=entity.attackCooldown,attackRange=entity.attackRange}
end end
H.write(H.root..'evidence/captures.json',output)
print('Actual row-file sprites captured through the unchanged arena and PixelBox renderer')

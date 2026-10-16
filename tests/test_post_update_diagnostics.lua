-- Negative controls for the observer used by the long mixed-match audit.
colors={white=1,orange=2,magenta=4,lightBlue=8,yellow=16,lime=32,pink=64,
    gray=128,lightGray=256,cyan=512,purple=1024,blue=2048,brown=4096,
    green=8192,red=16384,black=32768}
local Game=require('src.game')
local diagnostics=require('src.diagnostics')
local state=Game.new(nil,{headlessSimulation=true})
assert(Game.startHeadlessBattle(state,.1))
local target=state.entities[1]
state.projectiles[1]={alive=true,owner=2,x=25,y=28,targetId=target.id,
    lastTargetX=target.x,lastTargetY=target.y,damage=80,speed=60}
assert(diagnostics.assertState(state,'valid ordinary projectile'))
local projectile=state.projectiles[1]
local mutations={
    {'x',0/0}, {'y',math.huge}, {'damage',0/0}, {'damage',-1},
    {'speed',0}, {'speed',-1}, {'speed',math.huge}, {'owner',3},
    {'targetId',0}, {'targetId',1.5}, {'lastTargetX',0/0},
    {'lastTargetY',math.huge},
}
for _,mutation in ipairs(mutations) do
    local field,value=mutation[1],mutation[2]
    local original=projectile[field];projectile[field]=value
    local ok=pcall(diagnostics.assertState,state,'injected '..field)
    projectile[field]=original
    assert(not ok,'Observer accepted invalid ordinary projectile '..field..'='..tostring(value))
    assert(diagnostics.assertState(state,'restored projectile'))
end
-- A live source/target reference is deliberately not required: in-flight AoE
-- is allowed to outlive its source and its primary victim.
projectile.sourceEntityId=999999;projectile.targetId=999998
assert(diagnostics.assertState(state,'legitimate orphaned AoE flight'))
print('Post-update diagnostics passed: 12 rejected corruptions and valid orphaned flight')

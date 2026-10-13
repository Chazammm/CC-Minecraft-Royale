-- A declared projectile must advance; 0 is truthy in Lua and creates a
-- permanently in-flight projectile when the target starts out of hit range.
colors = {
    white=1, orange=2, magenta=4, lightBlue=8,
    yellow=16, lime=32, pink=64, gray=128,
    lightGray=256, cyan=512, purple=1024, blue=2048,
    brown=4096, green=8192, red=16384, black=32768,
}
package.path = "./?.lua;./?/init.lua;" .. package.path

local Cards = require("src.cards")

local function checkRejected(payload, description)
    local original = payload.projectileSpeed
    payload.projectileSpeed = 0
    local ok, err = pcall(Cards.validate)
    payload.projectileSpeed = original
    assert(not ok, description .. ": projectileSpeed=0 must fail validation")
    assert(tostring(err):find("projectileSpeed", 1, true),
        description .. ": failure must identify projectileSpeed")
end

checkRejected(Cards.byId.skeleton.unit, "Standard projectile")
checkRejected(Cards.internalUnits.piglin, "Internal summon projectile")
assert(Cards.validate() == true, "Current positive-speed card definitions remain valid")

-- Existing legal values and non-projectile melee attacks are unchanged.
assert(Cards.byId.zombie.unit.projectileSpeed == nil, "Melee must remain projectile-free")
assert(Cards.byId.skeleton.unit.projectileSpeed > 0, "Fixture must restore source data")
print("Projectile-speed schema invariant passed")

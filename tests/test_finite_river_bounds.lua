-- NaN river bounds bypass ordinary comparisons and make the river vanish
-- from arena collision/bridge navigation. Startup must reject them.
package.path = "./?.lua;./?/init.lua;" .. package.path
local config = require("config")
local originalTop, originalBottom = config.ARENA.riverTop, config.ARENA.riverBottom

local function assertRejected(key, value)
    config.ARENA.riverTop = originalTop
    config.ARENA.riverBottom = originalBottom
    config.ARENA[key] = value
    local ok, err = pcall(config.validate)
    config.ARENA.riverTop = originalTop
    config.ARENA.riverBottom = originalBottom
    assert(not ok, "Arena " .. key .. " must reject a non-finite bound")
    assert(tostring(err):find(key, 1, true), "Validation error must name " .. key)
end

local nan = 0 / 0
assertRejected("riverTop", nan)
assertRejected("riverBottom", nan)
assertRejected("riverTop", math.huge)
assertRejected("riverBottom", -math.huge)
assert(config.validate(), "Valid default river geometry must remain accepted")

print("Finite river geometry invariant passed")

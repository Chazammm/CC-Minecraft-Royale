-- Entity-local combat modifiers shared by the live engine and Bot forecasts.
-- Timers remain in base-attack seconds: applying/removing a modifier preserves
-- existing attack progress rather than destructively changing card statistics.
local util = require("src.util")
local modifiers = {}

function modifiers.attackFrequency(entity)
    return entity.heroWeb and entity.heroWeb.attackFactor or 1
end

function modifiers.moveSpeed(entity)
    local factor = 1
    if entity.slowRemaining and entity.slowRemaining > 0 then
        factor = entity.slowFactor or 1
    end
    if entity.heroWeb then factor = math.min(factor, entity.heroWeb.moveFactor) end
    return (entity.moveSpeed or 0) * factor * (entity.globalMoveSpeedFactor or 1)
end

function modifiers.precise(entity)
    return entity.preciseAttackTiming or entity.heroWeb ~= nil
end

function modifiers.advance(entity, field, dt)
    local remaining = entity[field] or 0
    if modifiers.precise(entity) then
        -- A ready attack cannot bank time while there is no legal attack.
        entity[field] = remaining > 0
            and util.tickRemaining(remaining, dt * modifiers.attackFrequency(entity)) or 0
    else
        entity[field] = math.max(0, util.tickRemaining(remaining, dt))
    end
end

function modifiers.arm(entity, field, interval)
    local carry = modifiers.precise(entity) and math.min(0, entity[field] or 0) or 0
    entity[field] = interval + carry
end

return modifiers

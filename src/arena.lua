local config = require("config")
local util = require("src.util")

local arena = {}
local A = config.ARENA

local function inBridge(x)
    for _, center in ipairs(A.bridgeCenters) do
        if math.abs(x - center) <= A.bridgeHalfWidth then
            return true
        end
    end
    return false
end

function arena.isRiver(y)
    return y >= A.riverTop and y <= A.riverBottom
end

-- Minimum straight-line distance from an open-water point to terrain a normal
-- ground unit may stand on: either river bank or one of the bridge rectangles.
-- This lets targeting reject water units that a ground attacker could never
-- bring inside its actual attack/trigger range.
function arena.distanceToGroundReach(x, y)
    if not arena.isRiver(y) then return 0 end
    if inBridge(x) then return 0 end

    local distance = math.min(
        math.abs(y - A.riverTop),
        math.abs(A.riverBottom - y)
    )

    for _, center in ipairs(A.bridgeCenters) do
        local left = center - A.bridgeHalfWidth
        local right = center + A.bridgeHalfWidth

        local horizontal
        if x < left then
            horizontal = left - x
        elseif x > right then
            horizontal = x - right
        else
            horizontal = 0
        end

        distance = math.min(distance, horizontal)
    end

    return math.max(0, distance)
end

function arena.groundReachPoint(entity, target)
    local x, y = target.x, target.y
    if not arena.isRiver(y) or inBridge(x) then return x, y end

    local candidates = {
        { x = x, y = A.riverTop - 0.01 },
        { x = x, y = A.riverBottom + 0.01 },
    }

    for _, center in ipairs(A.bridgeCenters) do
        candidates[#candidates + 1] = {
            x = center - A.bridgeHalfWidth,
            y = y,
        }
        candidates[#candidates + 1] = {
            x = center + A.bridgeHalfWidth,
            y = y,
        }
    end

    local best = candidates[1]
    local bestTargetD2 = math.huge
    local bestTravelD2 = math.huge

    for _, candidate in ipairs(candidates) do
        local targetD2 = util.distanceSquared(
            candidate.x,
            candidate.y,
            x,
            y
        )
        local travelD2 = entity and util.distanceSquared(
            entity.x,
            entity.y,
            candidate.x,
            candidate.y
        ) or 0

        if targetD2 < bestTargetD2 - 1e-9
            or (
                math.abs(targetD2 - bestTargetD2) <= 1e-9
                and travelD2 < bestTravelD2
            )
        then
            best = candidate
            bestTargetD2 = targetD2
            bestTravelD2 = travelD2
        end
    end

    return best.x, best.y
end

function arena.isBridge(x, y)
    return arena.isRiver(y) and inBridge(x)
end

function arena.terrainAt(x, y)
    if arena.isRiver(y) then
        if inBridge(x) then return "bridge" end
        return "river"
    end
    return "grass"
end

function arena.isWalkable(entity, x, y)
    if x < 1 or x > A.width - 1 or y < 1 or y > A.height - 1 then
        return false
    end
    if entity and entity.flying then return true end
    if entity and entity.waterOnly then
        return arena.isRiver(y) and not inBridge(x)
    end
    if arena.isRiver(y) then return inBridge(x) end
    return true
end

local function sideOfRiver(y)
    if y < A.riverTop then return -1 end
    if y > A.riverBottom then return 1 end
    return 0
end

function arena.laneForX(x)
    return x < A.width / 2 and "left" or "right"
end

local function enemyPocketUnlocked(state, playerId, x)
    if not state or state.phase ~= "battle" or not state.destroyedSideTowers then
        return false
    end

    local enemyId = playerId == 1 and 2 or 1
    local destroyed = state.destroyedSideTowers[enemyId]
    if not destroyed then return false end

    local lane = arena.laneForX(x)
    return destroyed[lane] == true
end

local function insideUnlockedPocket(state, playerId, x, y)
    if not enemyPocketUnlocked(state, playerId, x) then return false end

    local centerGap = A.pocketCenterGap or 6
    local lane = arena.laneForX(x)

    if lane == "left" and x > A.width / 2 - centerGap then return false end
    if lane == "right" and x < A.width / 2 + centerGap then return false end

    local towerYTop = A.enemyPrincessYTop or 28
    local towerYBottom = A.enemyPrincessYBottom or (A.height - towerYTop)
    local pastTower = A.pocketPastTower or 4

    if playerId == 1 then
        return y >= towerYTop - pastTower and y < A.riverTop - 2
    else
        return y <= towerYBottom + pastTower and y > A.riverBottom + 2
    end
end

local function nearestBridge(x1, y1, x2, y2)
    local best = A.bridgeCenters[1]
    local bestScore = math.huge
    local midY = (A.riverTop + A.riverBottom) / 2
    for _, bx in ipairs(A.bridgeCenters) do
        local score = util.distance(x1, y1, bx, midY) + util.distance(bx, midY, x2, y2)
        if score < bestScore then
            bestScore = score
            best = bx
        end
    end
    return best
end

function arena.navigationPoint(entity, target)
    if entity.flying then
        return target.x, target.y
    end

    -- Ground attackers that are allowed to engage a water-only target must
    -- path to the closest terrain point from which that target is reachable,
    -- rather than trying to walk directly into open river water.
    if target.waterOnly and not entity.waterOnly then
        local reachX, reachY = arena.groundReachPoint(entity, target)
        target = { x = reachX, y = reachY }
    end

    local es = sideOfRiver(entity.y)
    local ts = sideOfRiver(target.y)

    if es == 0 then
        local bx = nearestBridge(entity.x, entity.y, target.x, target.y)
        if ts < 0 then
            return bx, A.riverTop - 2
        elseif ts > 0 then
            return bx, A.riverBottom + 2
        end
        return target.x, target.y
    end

    if ts ~= 0 and es ~= ts then
        local bx = nearestBridge(entity.x, entity.y, target.x, target.y)
        return bx, (A.riverTop + A.riverBottom) / 2
    end

    return target.x, target.y
end

function arena.placementAllowed(playerId, x, y, placement, state)
    if x < 3 or x > A.width - 3 or y < 3 or y > A.height - 3 then
        return false
    end

    if placement == "anywhere" then
        return true
    end

    if placement == "water" then
        return arena.isRiver(y) and not inBridge(x)
    end

    if arena.isRiver(y) then return false end

    local ownHalf
    if playerId == 1 then
        ownHalf = y > A.riverBottom + 2
    else
        ownHalf = y < A.riverTop - 2
    end

    if ownHalf then return true end

    -- Destroying an enemy Princess Tower unlocks only that lane's pocket.
    -- The opposite lane and the centre around the King Tower remain locked.
    return insideUnlockedPocket(state, playerId, x, y)
end

function arena.worldToScreen(playerId, x, y, rect)
    local vx, vy = x, y
    if playerId == 2 then
        vx = A.width - vx
        vy = A.height - vy
    end

    local nx = util.clamp(vx / A.width, 0, 1)
    local ny = util.clamp(vy / A.height, 0, 1)

    local sx = rect.x1 + math.floor(nx * (rect.x2 - rect.x1))
    local sy = rect.y1 + math.floor(ny * (rect.y2 - rect.y1))
    return sx, sy
end

function arena.screenToWorld(playerId, sx, sy, rect)
    local nx = (sx - rect.x1) / math.max(1, rect.x2 - rect.x1)
    local ny = (sy - rect.y1) / math.max(1, rect.y2 - rect.y1)

    local x = util.clamp(nx, 0, 1) * A.width
    local y = util.clamp(ny, 0, 1) * A.height

    if playerId == 2 then
        x = A.width - x
        y = A.height - y
    end

    return x, y
end

function arena.towerBlueprints()
    return {
        { owner = 1, towerType = "princess", x = 25, y = 132 },
        { owner = 1, towerType = "princess", x = 75, y = 132 },
        { owner = 1, towerType = "king", x = 50, y = 151 },
        { owner = 2, towerType = "princess", x = 25, y = 28 },
        { owner = 2, towerType = "princess", x = 75, y = 28 },
        { owner = 2, towerType = "king", x = 50, y = 9 },
    }
end

return arena

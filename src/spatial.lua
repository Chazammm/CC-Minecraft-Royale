local spatial = {}

local CELL_SIZE = 16
local KEY_STRIDE = 1024

local function cellCoords(x, y)
    return math.floor((x or 0) / CELL_SIZE),
        math.floor((y or 0) / CELL_SIZE)
end

local function key(cx, cy)
    return cy * KEY_STRIDE + cx
end

function spatial.newIndex()
    return {
        cellSize = CELL_SIZE,
        buckets = { [1] = {}, [2] = {} },
    }
end

function spatial.ensure(state)
    if not state.spatialIndex then
        state.spatialIndex = spatial.newIndex()
    end
    return state.spatialIndex
end

function spatial.remove(state, entity)
    if not entity or not entity._spatialKey or not entity._spatialOwner then
        return
    end

    local index = state.spatialIndex
    local ownerBuckets = index
        and index.buckets
        and index.buckets[entity._spatialOwner]
    local bucket = ownerBuckets and ownerBuckets[entity._spatialKey]
    if bucket then
        bucket[entity.id] = nil
        if next(bucket) == nil then
            ownerBuckets[entity._spatialKey] = nil
        end
    end

    entity._spatialKey = nil
    entity._spatialOwner = nil
end

function spatial.index(state, entity)
    if not entity or not entity.alive then return end
    if entity.owner ~= 1 and entity.owner ~= 2 then return end

    local index = spatial.ensure(state)
    local cx, cy = cellCoords(entity.x, entity.y)
    local cellKey = key(cx, cy)

    if entity._spatialKey == cellKey
        and entity._spatialOwner == entity.owner
    then
        return
    end

    spatial.remove(state, entity)

    local ownerBuckets = index.buckets[entity.owner]
    local bucket = ownerBuckets[cellKey]
    if not bucket then
        bucket = {}
        ownerBuckets[cellKey] = bucket
    end
    bucket[entity.id] = entity
    entity._spatialKey = cellKey
    entity._spatialOwner = entity.owner
end

function spatial.rebuild(state)
    state.spatialIndex = spatial.newIndex()

    for order, entity in ipairs(state.entities or {}) do
        entity._spatialKey = nil
        entity._spatialOwner = nil
        entity._spatialOrder = order
        if entity.alive then
            spatial.index(state, entity)
        end
    end
end

function spatial.forEachInBounds(
    state,
    owner,
    minX,
    minY,
    maxX,
    maxY,
    callback
)
    local index = state.spatialIndex
    local ownerBuckets = index and index.buckets and index.buckets[owner]
    if not ownerBuckets then
        local fallback = state.entitiesByOwner
            and state.entitiesByOwner[owner]
            or state.entities
        for _, entity in ipairs(fallback or {}) do
            if entity.alive then callback(entity) end
        end
        return
    end

    local minCx, minCy = cellCoords(minX, minY)
    local maxCx, maxCy = cellCoords(maxX, maxY)

    for cx = minCx, maxCx do
        for cy = minCy, maxCy do
            local bucket = ownerBuckets[key(cx, cy)]
            if bucket then
                for _, entity in pairs(bucket) do
                    if entity.alive then callback(entity) end
                end
            end
        end
    end
end

function spatial.candidatesInBounds(
    state,
    owner,
    minX,
    minY,
    maxX,
    maxY
)
    local index = state.spatialIndex
    local ownerBuckets = index and index.buckets and index.buckets[owner]
    if not ownerBuckets then
        return state.entitiesByOwner
            and state.entitiesByOwner[owner]
            or state.entities
    end

    local minCx, minCy = cellCoords(minX, minY)
    local maxCx, maxCy = cellCoords(maxX, maxY)
    local out = {}

    for cx = minCx, maxCx do
        for cy = minCy, maxCy do
            local bucket = ownerBuckets[key(cx, cy)]
            if bucket then
                for _, entity in pairs(bucket) do
                    if entity.alive then out[#out + 1] = entity end
                end
            end
        end
    end

    table.sort(out, function(a, b)
        local ao = a._spatialOrder or a.id
        local bo = b._spatialOrder or b.id
        if ao == bo then return a.id < b.id end
        return ao < bo
    end)
    return out
end

function spatial.candidatesInRadius(state, owner, x, y, radius)
    radius = math.max(0, radius or 0)
    return spatial.candidatesInBounds(
        state,
        owner,
        x - radius,
        y - radius,
        x + radius,
        y + radius
    )
end

return spatial

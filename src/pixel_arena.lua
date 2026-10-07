local config = require("config")
local pixelbox = require("lib.pixelbox_lite")

local pixelArena = {}

local A = config.ARENA
local cache = setmetatable({}, { __mode = "k" })

local PALETTE = {
    K = colors.black,
    W = colors.white,
    S = colors.lightGray,
    D = colors.gray,
    G = colors.green,
    L = colors.lime,
    B = colors.blue,
    A = colors.lightBlue,
    C = colors.cyan,
    R = colors.red,
    Y = colors.yellow,
    N = colors.brown,
    P = colors.purple,
    M = colors.magenta,
    O = colors.orange,
}

local SPRITES = {
    zombie = {
        rows = {
            "..GGG..",
            ".GKGKG.",
            ".GGGGG.",
            "..GGG..",
            ".AAAAA.",
            "A.AAA.A",
            "..AAA..",
            "..BBB..",
            ".B...B.",
        },
    },
    skeleton = {
        rows = {
            "..WWW..",
            ".WKWKW.",
            "..WWW..",
            "...W...",
            "N.WWW.N",
            ".N.W.N.",
            "...W...",
            "..W.W..",
            ".W...W.",
        },
    },
    iron_golem = {
        rows = {
            "..SSSSS..",
            ".SSRSRSS.",
            ".SSSSSSS.",
            "...SSS...",
            "SSSSSSSSS",
            "S.SSSSS.S",
            "..SSSSS..",
            "..SGGGS..",
            "...SSS...",
            "..S...S..",
            ".SS...SS.",
        },
    },
    bat_swarm = {
        rows = {
            "P.......P",
            ".PP...PP.",
            "..PPKPP..",
            "...PPP...",
            "....P....",
        },
    },
    cannon = {
        rows = {
            "....DDD....",
            "..DDSSSDD..",
            "DDSSSSSSDDD",
            "..DDSSSD...",
            "...NNNN....",
            "..NN..NN...",
            ".NN....NN..",
        },
    },
    creeper = {
        rows = {
            "..LLLL..",
            ".LLLLLL.",
            ".LKLLKL.",
            ".LLLLLL.",
            ".LLKKLL.",
            ".LKKKKL.",
            "..LLLL..",
            "..L..L..",
            ".LL..LL.",
        },
    },
    slime = {
        rows = {
            "..LLLL..",
            ".LLLLLL.",
            "LLKLLKLL",
            "LLLLLLLL",
            ".LKKKKL.",
            "..LLLL..",
        },
    },
    mini_slime = {
        rows = {
            ".LLL.",
            "LKLKL",
            "LLLLL",
            ".LLL.",
        },
    },
    princess_tower = {
        rows = {
            "...TTT...",
            "..TTTTT..",
            ".TTTTTTT.",
            "...YYY...",
            "..SSSSS..",
            ".SSSKSSS.",
            ".SSSSSSS.",
            ".SSSSSSS.",
            ".SSSKSSS.",
            ".SSSSSSS.",
            "SSSSSSSSS",
            "SSS...SSS",
            "SSS...SSS",
        },
    },
    king_tower = {
        rows = {
            "Y.Y.Y.Y.Y",
            ".YYYYYYY.",
            "..YYYYY..",
            "..TTTTT..",
            ".TTTTTTT.",
            "TTTTTTTTT",
            "..SSSSS..",
            ".SSSKSSS.",
            ".SSSSSSS.",
            ".SSSSSSS.",
            ".SSSKSSS.",
            ".SSSSSSS.",
            "SSSSSSSSS",
            "SSS...SSS",
            "SSS...SSS",
        },
    },
}

local NAME_TO_SPRITE = {
    ["Zombie"] = "zombie",
    ["Skeleton"] = "skeleton",
    ["Iron Golem"] = "iron_golem",
    ["Bat Swarm"] = "bat_swarm",
    ["Cannon"] = "cannon",
    ["Creeper"] = "creeper",
    ["Slime"] = "slime",
    ["Mini Slime"] = "mini_slime",
}

local function normalizeSprites()
    for _, sprite in pairs(SPRITES) do
        local width = 1
        for _, row in ipairs(sprite.rows) do width = math.max(width, #row) end
        sprite.width = width
        sprite.height = #sprite.rows
    end
end
normalizeSprites()

local function spriteFor(entity)
    if entity.kind == "tower" then
        return entity.towerType == "king" and SPRITES.king_tower or SPRITES.princess_tower
    end
    return SPRITES[NAME_TO_SPRITE[entity.name]] or SPRITES.zombie
end

local function getSurface(monitor, rect)
    local w = rect.x2 - rect.x1 + 1
    local h = rect.y2 - rect.y1 + 1
    local cached = cache[monitor]

    if not cached
        or cached.x ~= rect.x1
        or cached.y ~= rect.y1
        or cached.w ~= w
        or cached.h ~= h
    then
        local win = window.create(monitor, rect.x1, rect.y1, w, h, true)
        win.setBackgroundColor(colors.black)
        win.clear()

        cached = {
            x = rect.x1,
            y = rect.y1,
            w = w,
            h = h,
            window = win,
            box = pixelbox.new(win, colors.green),
        }
        cache[monitor] = cached
    end

    return cached.box
end

local function put(box, x, y, color)
    x, y = math.floor(x + 0.5), math.floor(y + 0.5)
    if x >= 1 and x <= box.width and y >= 1 and y <= box.height then
        box.canvas[y][x] = color
    end
end

local function fillRect(box, x1, y1, x2, y2, color)
    x1 = math.max(1, math.floor(x1))
    y1 = math.max(1, math.floor(y1))
    x2 = math.min(box.width, math.ceil(x2))
    y2 = math.min(box.height, math.ceil(y2))
    for y = y1, y2 do
        local row = box.canvas[y]
        for x = x1, x2 do row[x] = color end
    end
end

local function drawLine(box, x1, y1, x2, y2, color)
    local dx, dy = x2 - x1, y2 - y1
    local steps = math.max(math.abs(dx), math.abs(dy))
    if steps < 1 then
        put(box, x1, y1, color)
        return
    end
    for i = 0, steps do
        local t = i / steps
        put(box, x1 + dx * t, y1 + dy * t, color)
    end
end

local function worldToPixel(box, playerId, x, y)
    local vx, vy = x, y
    if playerId == 2 then
        vx = A.width - vx
        vy = A.height - vy
    end
    local px = 1 + (vx / A.width) * (box.width - 1)
    local py = 1 + (vy / A.height) * (box.height - 1)
    return px, py
end

local function worldRadiusX(box, radius)
    return math.max(1, radius / A.width * box.width)
end

local function worldRadiusY(box, radius)
    return math.max(1, radius / A.height * box.height)
end

local function drawTerrain(box)
    box:clear(colors.green)

    local riverY1 = 1 + (A.riverTop / A.height) * (box.height - 1)
    local riverY2 = 1 + (A.riverBottom / A.height) * (box.height - 1)
    fillRect(box, 1, riverY1, box.width, riverY2, colors.blue)

    for _, bx in ipairs(A.bridgeCenters) do
        local x1 = 1 + ((bx - A.bridgeHalfWidth) / A.width) * (box.width - 1)
        local x2 = 1 + ((bx + A.bridgeHalfWidth) / A.width) * (box.width - 1)
        fillRect(box, x1, riverY1, x2, riverY2, colors.brown)

        -- small dark bridge rails for depth/readability
        drawLine(box, x1, riverY1, x1, riverY2, colors.gray)
        drawLine(box, x2, riverY1, x2, riverY2, colors.gray)
    end
end

local function hpColor(entity)
    local ratio = entity.hp / math.max(1, entity.maxHp)
    if ratio > 0.60 then return colors.lime end
    if ratio > 0.30 then return colors.yellow end
    return colors.red
end

local function drawHp(box, entity, playerId, cx, topY, width)
    local barW = math.max(7, width)
    local x1 = math.floor(cx - barW / 2)
    local y = math.floor(topY - 3)
    local team = entity.owner == playerId and colors.lightBlue or colors.red
    local ratio = math.max(0, math.min(1, entity.hp / math.max(1, entity.maxHp)))
    local filled = math.floor((barW - 2) * ratio + 0.5)

    fillRect(box, x1, y, x1 + barW - 1, y + 1, colors.black)
    drawLine(box, x1, y, x1 + barW - 1, y, team)
    for i = 0, filled - 1 do put(box, x1 + 1 + i, y + 1, hpColor(entity)) end
end

local function drawSprite(box, entity, playerId)
    local sprite = spriteFor(entity)
    local cx, cy = worldToPixel(box, playerId, entity.x, entity.y)
    local x1 = math.floor(cx - sprite.width / 2)
    local y1 = math.floor(cy - sprite.height / 2)
    local team = entity.owner == playerId and colors.lightBlue or colors.red
    local flash = entity.damageFlash and entity.damageFlash > 0
    local fuseBlink = entity.fuseRemaining
        and math.floor(entity.fuseRemaining * 10) % 2 == 0

    if entity.kind ~= "tower" then
        local shadowY = y1 + sprite.height
        drawLine(box, x1 + 1, shadowY, x1 + sprite.width - 2, shadowY, colors.black)
    end

    for rowIndex, row in ipairs(sprite.rows) do
        for col = 1, #row do
            local token = row:sub(col, col)
            if token ~= "." then
                local color
                if token == "T" then
                    color = team
                else
                    color = PALETTE[token]
                end

                if color then
                    if flash then
                        color = colors.white
                    elseif fuseBlink and entity.name == "Creeper" then
                        color = token == "K" and colors.black or colors.white
                    end
                    put(box, x1 + col - 1, y1 + rowIndex - 1, color)
                end
            end
        end
    end

    if entity.kind ~= "tower" then
        drawLine(box, x1, y1 + sprite.height + 1, x1 + sprite.width - 1, y1 + sprite.height + 1, team)
    end

    drawHp(box, entity, playerId, cx, y1, sprite.width + 2)
end

local function getEntityById(state, id)
    if not id then return nil end
    for _, entity in ipairs(state.entities) do
        if entity.id == id and entity.alive then return entity end
    end
    return nil
end

local function drawProjectile(box, state, playerId, projectile)
    local px, py = worldToPixel(box, playerId, projectile.x, projectile.y)

    if projectile.visual == "arrow" then
        local target = getEntityById(state, projectile.targetId)
        local dx, dy = 1, 0
        if target then
            local tx, ty = worldToPixel(box, playerId, target.x, target.y)
            dx, dy = tx - px, ty - py
            local length = math.sqrt(dx * dx + dy * dy)
            if length > 0 then dx, dy = dx / length, dy / length end
        end
        drawLine(box, px - dx * 2, py - dy * 2, px + dx * 2, py + dy * 2, colors.white)
        put(box, px + dx * 2, py + dy * 2, colors.lightGray)
    elseif projectile.visual == "cannonball" then
        fillRect(box, px - 1, py - 1, px + 1, py + 1, colors.gray)
        put(box, px, py, colors.lightGray)
    elseif projectile.visual == "tower_shot" then
        fillRect(box, px - 1, py - 1, px + 1, py + 1, colors.yellow)
    else
        put(box, px, py, colors.white)
    end
end

local function drawExplosion(box, playerId, effect)
    local cx, cy = worldToPixel(box, playerId, effect.x, effect.y)
    local duration = math.max(0.001, effect.duration or 0.5)
    local progress = math.max(0, math.min(1, 1 - effect.ttl / duration))
    local maxRx = worldRadiusX(box, effect.radius or 6)
    local maxRy = worldRadiusY(box, effect.radius or 6)
    local rx = math.max(2, maxRx * (0.25 + progress * 0.75))
    local ry = math.max(2, maxRy * (0.25 + progress * 0.75))
    local color = progress < 0.45 and colors.white
        or (progress < 0.75 and colors.yellow or colors.orange)

    for y = math.floor(-ry), math.ceil(ry) do
        for x = math.floor(-rx), math.ceil(rx) do
            local nx, ny = x / rx, y / ry
            local d = nx * nx + ny * ny
            if d <= 1 and d >= 0.45 then
                put(box, cx + x, cy + y, color)
            end
        end
    end
end

local function drawArrowVolley(box, playerId, effect)
    local cx, cy = worldToPixel(box, playerId, effect.x, effect.y)
    local rx = worldRadiusX(box, effect.radius or 10)
    local ry = worldRadiusY(box, effect.radius or 10)
    local duration = math.max(0.001, effect.duration or 0.45)
    local progress = math.max(0, math.min(1, 1 - effect.ttl / duration))

    for i = 1, 17 do
        local fx = ((i * 37) % 101) / 100 * 2 - 1
        local fy = ((i * 61) % 97) / 96 * 2 - 1
        if fx * fx + fy * fy <= 1 then
            local x = cx + fx * rx
            local baseY = cy + fy * ry
            local y = baseY - (1 - progress) * 10
            drawLine(box, x, y - 3, x, y + 2, colors.lightGray)
            put(box, x, y + 3, colors.white)
        end
    end
end

local function drawHit(box, playerId, effect)
    local x, y = worldToPixel(box, playerId, effect.x, effect.y)
    drawLine(box, x - 2, y, x + 2, y, colors.white)
    drawLine(box, x, y - 2, x, y + 2, colors.white)
end

local function drawEffect(box, playerId, effect)
    if effect.kind == "arrows" then
        drawArrowVolley(box, playerId, effect)
    elseif effect.kind == "hit" then
        drawHit(box, playerId, effect)
    else
        drawExplosion(box, playerId, effect)
    end
end

function pixelArena.draw(monitor, state, playerId, rect)
    local box = getSurface(monitor, rect)
    drawTerrain(box)

    for _, entity in ipairs(state.entities) do
        if entity.alive then drawSprite(box, entity, playerId) end
    end

    for _, projectile in ipairs(state.projectiles) do
        if projectile.alive then drawProjectile(box, state, playerId, projectile) end
    end

    for _, effect in ipairs(state.effects) do
        drawEffect(box, playerId, effect)
    end

    box:render()
end

function pixelArena.getLogicalSize(monitor, rect)
    local box = getSurface(monitor, rect)
    return box.width, box.height
end

return pixelArena

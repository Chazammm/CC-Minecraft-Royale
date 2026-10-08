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
        -- Green block head, blue shirt, purple trousers.
        rows = {
            "..LLL..",
            ".LKLKL.",
            "..LLL..",
            ".BBBBB.",
            "BBBBBBB",
            "..BBB..",
            "..P.P..",
            "..P.P..",
            ".PP.PP.",
        },
    },
    skeleton = {
        rows = {
            ".WWW.",
            ".WKW.",
            ".WWW.",
            "..W..",
            ".WWW.",
            "W.W.W",
            ".W.W.",
        },
    },
    wither_skeleton = {
        rows = {
            ".DDD.",
            ".DKD.",
            ".DDD.",
            "..D..",
            ".DDD.",
            "D.D.D",
            ".D.D.",
        },
    },
    iron_golem = {
        rows = {
            "..SSS..",
            ".SSKSS.",
            ".SSSSS.",
            "SSSSSSS",
            "S.SSS.S",
            "..SSS..",
            "..SSS..",
            ".SS.SS.",
            "SS...SS",
        },
    },
    bat_swarm = {
        rows = {
            "P.....P",
            "PP...PP",
            ".PPKPP.",
            "..PPP..",
        },
    },
    cannon = {
        rows = {
            "...DDD.",
            "DDDDDDD",
            "..DDD..",
            "...D...",
            ".KKKKK.",
            "K.....K",
        },
    },
    pillager_outpost = {
        rows = {
            "..NNN..",
            ".NNNNN.",
            "NNDDDDD",
            ".NDDDN.",
            ".NNKNN.",
            ".NNNNN.",
            "NN...NN",
            "NN...NN",
        },
    },
    creeper = {
        -- Oversized Minecraft head, narrow body and split feet.
        rows = {
            ".LLLLL.",
            ".LKLKL.",
            ".LLKLL.",
            ".LKKKL.",
            "..LLL..",
            "..LLL..",
            "..LLL..",
            ".LL.LL.",
            ".L...L.",
            "LL...LL",
        },
    },
    slime = {
        rows = {
            ".LLL.",
            "LLLLL",
            "LKLKL",
            "LLLLL",
        },
    },
    mini_slime = {
        rows = {
            "LLL",
            "LKL",
            "LLL",
        },
    },
    magma_cube = {
        rows = {
            ".OOO.",
            "ORORO",
            "OKOKO",
            "OOOOO",
        },
    },
    mini_magma_cube = {
        rows = {
            "OOO",
            "OKO",
            "ORO",
        },
    },
    baby_zombie = {
        rows = {
            ".LL.",
            ".LKL",
            ".LL.",
            "LLLL",
            ".L.L",
        },
    },
    blaze = {
        rows = {
            "..OOO..",
            ".OKOKO.",
            "..OOO..",
            "O.O.O.O",
            ".O.O.O.",
            "O..O..O",
        },
    },
    witch = {
        -- Hat / face / robe are split vertically to keep Pixelbox clean.
        rows = {
            "...P...",
            "..PPP..",
            ".PPPPP.",
            "..OOO..",
            ".OKOKO.",
            "...O...",
            "..PPP..",
            ".PPPPP.",
            "..P.P..",
            ".P...P.",
        },
    },
    enderman = {
        -- 6x12: full 2x3 head texel block, then extremely long limbs.
        -- Keeping purple confined to the filled head avoids Pixelbox colour bleed.
        rows = {
            "KKKKKK",
            "KPKKPK",
            "KKKKKK",
            "K.KK.K",
            "K.KK.K",
            "K.KK.K",
            "K.KK.K",
            "K.KK.K",
            "K.KK.K",
            "K....K",
            "K....K",
            "K....K",
        },
    },
    spider = {
        rows = {
            "D.....D",
            ".D.D.D.",
            "..DDD..",
            ".DKDKD.",
            "..DDD..",
            ".D.D.D.",
            "D.....D",
        },
    },
    snow_golem = {
        rows = {
            "..WWW..",
            ".WKWKW.",
            "..WWW..",
            "...W...",
            "..WWW..",
            ".WWWWW.",
            "..W.W..",
        },
    },
    villager = {
        -- 6x12. Large square head, distinct nose and long brown robe.
        rows = {
            "OOOOOO",
            "OKOOKO",
            "OOOOOO",
            "OONNOO",
            "OONNOO",
            "OOOOOO",
            ".NNNN.",
            "NNNNNN",
            "NNNNNN",
            ".NNNN.",
            ".NNNN.",
            ".N..N.",
        },
    },
    endermite = {
        rows = {
            ".PPP.",
            "PKPKP",
            ".PPP.",
        },
    },
    wolf = {
        -- 12x9 side profile with a clear red tamed-wolf collar.
        rows = {
            "SSSS........",
            "SKSS........",
            "SSSS........",
            "SSRRSSSSSSSS",
            "SSRRSSSSSSSS",
            "SSRRSSSSSSSS",
            "..SSSSSSSS..",
            "..SS..SS....",
            "..SS..SS....",
        },
    },
    nether_portal = {
        rows = {
            ".PPPPP.",
            "PPMMMMM",
            "PPMKKMM",
            "PPMKKMM",
            "PPMKKMM",
            "PPMKKMM",
            "PPMMMMM",
            ".PPPPP.",
        },
    },
    piglin = {
        rows = {
            "..OOO..",
            ".ONONO.",
            "..ONO..",
            ".NNNNN.",
            "NNYNNNN",
            "..NNN..",
            "..N.N..",
            ".NN.NN.",
        },
    },
    princess_tower = {
        rows = {
            "..TTT..",
            ".TTTTT.",
            ".TTTTT.",
            "..TKT..",
            ".TTTTT.",
            ".TTTTT.",
            "TTTTTTT",
            "TT...TT",
        },
    },
    king_tower = {
        rows = {
            "T.T.T.T",
            ".TTTTT.",
            "TTTTTTT",
            ".TTTTT.",
            "..TKT..",
            ".TTTTT.",
            ".TTTTT.",
            "TTTTTTT",
            "TT...TT",
        },
    },
}

local NAME_TO_SPRITE = {
    ["Zombie"] = "zombie",
    ["Skeleton"] = "skeleton",
    ["Wither Skeleton"] = "wither_skeleton",
    ["Iron Golem"] = "iron_golem",
    ["Bat Swarm"] = "bat_swarm",
    ["Cannon"] = "cannon",
    ["Pillager Outpost"] = "pillager_outpost",
    ["Creeper"] = "creeper",
    ["Slime"] = "slime",
    ["Mini Slime"] = "mini_slime",
    ["Magma Cube"] = "magma_cube",
    ["Mini Magma Cube"] = "mini_magma_cube",
    ["Baby Zombie"] = "baby_zombie",
    ["Blaze"] = "blaze",
    ["Witch"] = "witch",
    ["Enderman"] = "enderman",
    ["Spider"] = "spider",
    ["Snow Golem"] = "snow_golem",
    ["Villager"] = "villager",
    ["Endermite"] = "endermite",
    ["Wolf"] = "wolf",
    ["Nether Portal"] = "nether_portal",
    ["Piglin"] = "piglin",
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

local function alignTexelX(x)
    return math.floor((x - 1) / 2) * 2 + 1
end

local function alignTexelY(y)
    return math.floor((y - 1) / 3) * 3 + 1
end

local function drawHp(box, entity, playerId, cx, topY, width)
    local ratio = math.max(0, math.min(1, entity.hp / math.max(1, entity.maxHp)))
    local maxW = entity.kind == "tower" and math.max(12, width + 4) or math.max(5, width)
    local filled = math.max(1, math.floor(maxW * ratio + 0.5))
    local x1 = math.floor(cx - maxW / 2)
    local y = math.floor(topY - 2)

    local barColor
    if entity.kind == "tower" then
        if ratio <= 0.25 then
            barColor = colors.red
        elseif ratio <= 0.55 then
            barColor = colors.yellow
        else
            barColor = colors.lime
        end
    else
        barColor = entity.owner == playerId and colors.lightBlue or colors.red
    end

    fillRect(box, x1, y, x1 + filled - 1, y + 1, barColor)
end

local function drawSprite(box, entity, playerId)
    local sprite = spriteFor(entity)
    local cx, cy = worldToPixel(box, playerId, entity.x, entity.y)

    -- Snap the sprite origin to Pixelbox's 2x3 texel grid. This removes most
    -- edge shimmer/colour bleed while units are moving.
    local rawX = cx - sprite.width / 2
    local rawY = cy - sprite.height / 2
    local x1 = alignTexelX(rawX)
    local y1 = alignTexelY(rawY)

    local team = entity.owner == playerId and colors.lightBlue or colors.red
    local hpRatio = entity.hp / math.max(1, entity.maxHp or 1)
    local flash = entity.damageFlash and entity.damageFlash > 0
    local fuseBlink = entity.fuseRemaining
        and math.floor(entity.fuseRemaining * 10) % 2 == 0

    for rowIndex, row in ipairs(sprite.rows) do
        for col = 1, #row do
            local token = row:sub(col, col)
            if token ~= "." then
                local color = token == "T" and team or PALETTE[token]

                if color then
                    if flash then
                        color = colors.white
                    elseif fuseBlink and entity.name == "Creeper" then
                        color = token == "K" and colors.black or colors.white
                    elseif entity.kind == "tower" and token == "T" then
                        -- Deterministic crack pixels make damaged towers look
                        -- visibly worn without losing their team silhouette.
                        if hpRatio <= 0.25 and (rowIndex + col * 2) % 5 == 0 then
                            color = colors.black
                        elseif hpRatio <= 0.55 and (rowIndex * 2 + col) % 7 == 0 then
                            color = colors.gray
                        end
                    end
                    put(box, x1 + col - 1, y1 + rowIndex - 1, color)
                end
            end
        end
    end

    drawHp(box, entity, playerId, x1 + sprite.width / 2, y1, sprite.width)
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
        drawLine(box, px - dx, py - dy, px + dx, py + dy, colors.white)
        put(box, px + dx, py + dy, colors.lightGray)
    elseif projectile.visual == "cannonball" then
        fillRect(box, px - 1, py - 1, px + 1, py + 1, colors.gray)
        put(box, px, py, colors.lightGray)
    elseif projectile.visual == "tower_shot" then
        fillRect(box, px - 1, py - 1, px + 1, py + 1, colors.yellow)
    elseif projectile.visual == "fireball" then
        fillRect(box, px - 1, py - 1, px + 1, py + 1, colors.orange)
        put(box, px, py, colors.yellow)
    elseif projectile.visual == "potion" then
        fillRect(box, px - 1, py - 1, px + 1, py + 1, colors.purple)
    elseif projectile.visual == "snowball" then
        fillRect(box, px - 1, py - 1, px + 1, py + 1, colors.white)
    elseif projectile.visual == "crossbow_bolt" then
        local target = getEntityById(state, projectile.targetId)
        local dx, dy = 1, 0
        if target then
            local tx, ty = worldToPixel(box, playerId, target.x, target.y)
            dx, dy = tx - px, ty - py
            local length = math.sqrt(dx * dx + dy * dy)
            if length > 0 then dx, dy = dx / length, dy / length end
        end
        drawLine(box, px - dx, py - dy, px + dx * 1.5, py + dy * 1.5, colors.brown)
        put(box, px + dx * 1.5, py + dy * 1.5, colors.lightGray)
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

local function drawRingEffect(box, playerId, effect, color)
    local cx, cy = worldToPixel(box, playerId, effect.x, effect.y)
    local rx = math.max(2, worldRadiusX(box, effect.radius or 4))
    local ry = math.max(2, worldRadiusY(box, effect.radius or 4))

    for y = math.floor(-ry), math.ceil(ry) do
        for x = math.floor(-rx), math.ceil(rx) do
            local nx, ny = x / rx, y / ry
            local d = nx * nx + ny * ny
            if d <= 1 and d >= 0.5 then
                put(box, cx + x, cy + y, color)
            end
        end
    end
end

local function drawSparkle(box, playerId, effect, color)
    local cx, cy = worldToPixel(box, playerId, effect.x, effect.y)
    local duration = math.max(0.001, effect.duration or 0.4)
    local progress = math.max(0, math.min(1, 1 - effect.ttl / duration))
    local rise = progress * 5

    put(box, cx, cy - rise - 1, color)
    put(box, cx - 2, cy - rise + 1, color)
    put(box, cx + 2, cy - rise, color)
    put(box, cx, cy - rise + 2, colors.white)
end

local function drawTowerDown(box, playerId, effect)
    drawExplosion(box, playerId, effect)
    local cx, cy = worldToPixel(box, playerId, effect.x, effect.y)
    local duration = math.max(0.001, effect.duration or 0.7)
    local progress = math.max(0, math.min(1, 1 - effect.ttl / duration))
    local spread = 2 + progress * 9

    for i = 1, 8 do
        local angle = i * 2.399
        local x = cx + math.cos(angle) * spread
        local y = cy + math.sin(angle) * spread * 0.65 + progress * 3
        put(box, x, y, i % 2 == 0 and colors.gray or colors.brown)
    end
end

local function drawAnvilWarning(box, playerId, effect)
    local cx, cy = worldToPixel(box, playerId, effect.x, effect.y)
    local duration = math.max(0.001, effect.duration or 3)
    local progress = math.max(0, math.min(1, 1 - effect.ttl / duration))
    local rx = math.max(2, worldRadiusX(box, effect.radius or 5.5))
    local ry = math.max(2, worldRadiusY(box, effect.radius or 5.5))

    -- Pulsing landing marker.
    local pulse = math.floor(effect.ttl * 4) % 2 == 0
    local ringColor = pulse and colors.red or colors.orange
    for i = 0, 15 do
        local angle = i / 16 * math.pi * 2
        put(box, cx + math.cos(angle) * rx, cy + math.sin(angle) * ry, ringColor)
    end
    drawLine(box, cx - 2, cy, cx + 2, cy, colors.white)
    drawLine(box, cx, cy - 2, cx, cy + 2, colors.white)

    -- Anvil drops visibly from above during the three-second telegraph.
    local startY = math.max(2, cy - 30)
    local ay = startY + (cy - startY - 4) * progress
    fillRect(box, cx - 3, ay, cx + 3, ay + 1, colors.gray)
    fillRect(box, cx - 2, ay + 2, cx + 2, ay + 3, colors.lightGray)
    fillRect(box, cx - 1, ay + 4, cx + 1, ay + 5, colors.gray)
end

local function drawAnvilImpact(box, playerId, effect)
    local cx, cy = worldToPixel(box, playerId, effect.x, effect.y)
    drawExplosion(box, playerId, effect)
    fillRect(box, cx - 4, cy - 2, cx + 4, cy - 1, colors.gray)
    fillRect(box, cx - 2, cy, cx + 2, cy + 2, colors.lightGray)
    drawLine(box, cx - 5, cy + 3, cx + 5, cy + 3, colors.brown)
end

local function drawEffect(box, playerId, effect)
    if effect.kind == "arrows" then
        drawArrowVolley(box, playerId, effect)
    elseif effect.kind == "hit" then
        drawHit(box, playerId, effect)
    elseif effect.kind == "teleport" then
        drawRingEffect(box, playerId, effect, colors.magenta)
    elseif effect.kind == "splash" then
        drawRingEffect(box, playerId, effect, colors.purple)
    elseif effect.kind == "summon" then
        drawRingEffect(box, playerId, effect, colors.lime)
    elseif effect.kind == "portal_spawn" then
        drawRingEffect(box, playerId, effect, colors.magenta)
        drawSparkle(box, playerId, effect, colors.purple)
    elseif effect.kind == "spawn" then
        local team = effect.owner == playerId and colors.lightBlue or colors.red
        drawRingEffect(box, playerId, effect, team)
    elseif effect.kind == "death" then
        drawRingEffect(box, playerId, effect, colors.lightGray)
    elseif effect.kind == "slow" then
        drawRingEffect(box, playerId, effect, colors.cyan)
    elseif effect.kind == "emerald" then
        drawSparkle(box, playerId, effect, colors.lime)
    elseif effect.kind == "tower_warning" then
        drawRingEffect(box, playerId, effect, colors.red)
    elseif effect.kind == "tower_down" then
        drawTowerDown(box, playerId, effect)
    elseif effect.kind == "anvil_warning" then
        drawAnvilWarning(box, playerId, effect)
    elseif effect.kind == "anvil_impact" then
        drawAnvilImpact(box, playerId, effect)
    else
        drawExplosion(box, playerId, effect)
    end
end

function pixelArena.draw(monitor, state, playerId, rect)
    local box = getSurface(monitor, rect)
    drawTerrain(box)

    local drawEntities = {}
    for _, entity in ipairs(state.entities) do
        if entity.alive then
            local _, py = worldToPixel(box, playerId, entity.x, entity.y)
            table.insert(drawEntities, { entity = entity, py = py })
        end
    end

    table.sort(drawEntities, function(a, b)
        if a.py == b.py then return a.entity.id < b.entity.id end
        return a.py < b.py
    end)

    for _, entry in ipairs(drawEntities) do
        drawSprite(box, entry.entity, playerId)
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

local config = require("config")
local util = require("src.util")
local arena = require("src.arena")
local cards = require("src.cards")
local sprites = require("src.sprites")

local render = {}

local function newBuffer(width, height)
    local b = { width = width, height = height, chars = {}, fg = {}, bg = {} }
    for y = 1, height do
        b.chars[y], b.fg[y], b.bg[y] = {}, {}, {}
        for x = 1, width do
            b.chars[y][x] = " "
            b.fg[y][x] = colors.white
            b.bg[y][x] = colors.black
        end
    end
    return b
end

local function setCell(b, x, y, ch, fg, bg)
    x, y = math.floor(x), math.floor(y)
    if x < 1 or x > b.width or y < 1 or y > b.height then return end
    b.chars[y][x] = (ch or " "):sub(1, 1)
    if fg then b.fg[y][x] = fg end
    if bg then b.bg[y][x] = bg end
end

local function fill(b, x1, y1, x2, y2, bg)
    for y = math.max(1, y1), math.min(b.height, y2) do
        for x = math.max(1, x1), math.min(b.width, x2) do
            setCell(b, x, y, " ", colors.white, bg)
        end
    end
end

local function writeText(b, x, y, text, fg, bg)
    text = tostring(text or "")
    for i = 1, #text do
        setCell(b, x + i - 1, y, text:sub(i, i), fg or colors.white, bg)
    end
end

local function centered(b, y, text, fg, bg)
    local x = math.floor((b.width - #text) / 2) + 1
    writeText(b, x, y, text, fg, bg)
end

local function flush(b, monitor)
    for y = 1, b.height do
        local chars, fg, bg = {}, {}, {}
        for x = 1, b.width do
            chars[x] = b.chars[y][x]
            fg[x] = colors.toBlit(b.fg[y][x])
            bg[x] = colors.toBlit(b.bg[y][x])
        end
        monitor.setCursorPos(1, y)
        monitor.blit(table.concat(chars), table.concat(fg), table.concat(bg))
    end
end

local function makeColumns(width, count, y1, y2)
    local zones = {}
    for i = 1, count do
        zones[i] = {
            x1 = math.floor((i - 1) * width / count) + 1,
            x2 = math.floor(i * width / count),
            y1 = y1,
            y2 = y2,
        }
    end
    return zones
end

function render.layoutFor(monitor)
    local w, h = monitor.getSize()

    local layout = {
        width = w,
        height = h,
        scenarios = makeColumns(w, 5, 3, 5),
        arena = { x1 = 1, y1 = 6, x2 = w, y2 = h - 18 },
        controls = makeColumns(w, 3, h - 17, h - 14),
        cards = {},
    }

    local top = makeColumns(w, 4, h - 13, h - 7)
    local bottom = makeColumns(w, 4, h - 6, h)
    for i = 1, 4 do layout.cards[i] = top[i] end
    for i = 1, 4 do layout.cards[i + 4] = bottom[i] end

    return layout
end

local function drawButton(b, z, label, active, activeColor)
    local bg = active and (activeColor or colors.lime) or colors.gray
    local fg = active and colors.black or colors.white
    fill(b, z.x1, z.y1, z.x2, z.y2, bg)
    local width = z.x2 - z.x1 + 1
    local text = util.truncate(label, math.max(1, width - 2))
    local x = z.x1 + math.max(0, math.floor((width - #text) / 2))
    local y = math.floor((z.y1 + z.y2) / 2)
    writeText(b, x, y, text, fg, bg)
end

local function terrainColor(wx, wy)
    local t = arena.terrainAt(wx, wy)
    if t == "river" then return colors.blue end
    if t == "bridge" then return colors.brown end
    return colors.green
end

local function inside(rect, x, y)
    return x >= rect.x1 and x <= rect.x2 and y >= rect.y1 and y <= rect.y2
end

local function arenaCell(b, rect, x, y, ch, fg, bg)
    if inside(rect, x, y) then
        setCell(b, x, y, ch, fg, bg)
    end
end

local function drawEntity(b, rect, entity, viewerId)
    local sx, sy = arena.worldToScreen(viewerId, entity.x, entity.y, rect)
    local sprite = sprites.forEntity(entity)
    local x1 = sx - math.floor(sprite.width / 2)
    local y1 = sy - math.floor((sprite.height - 1) / 2)
    local own = entity.owner == viewerId
    local teamBg = own and colors.blue or colors.red
    local fg = entity.color or colors.white
    local bg = sprite.tower and teamBg or colors.black

    if entity.damageFlash and entity.damageFlash > 0 then
        fg = colors.white
        bg = colors.orange
    elseif entity.fuseRemaining then
        fg = math.floor(entity.fuseRemaining * 8) % 2 == 0 and colors.white or colors.yellow
    end

    for rowIndex, row in ipairs(sprite.rows) do
        for col = 1, #row do
            local ch = row:sub(col, col)
            if ch ~= " " and ch ~= "." then
                arenaCell(b, rect, x1 + col - 1, y1 + rowIndex - 1, ch, fg, bg)
            end
        end
    end

    local width = math.max(3, sprite.width)
    local barX = sx - math.floor(width / 2)
    local barY = y1 - 1
    local ratio = math.max(0, math.min(1, entity.hp / math.max(1, entity.maxHp)))
    local filled = math.ceil(ratio * width)
    local hpFg = ratio > 0.6 and colors.lime or (ratio > 0.3 and colors.yellow or colors.red)

    for i = 0, width - 1 do
        arenaCell(
            b,
            rect,
            barX + i,
            barY,
            i < filled and "=" or "-",
            i < filled and hpFg or colors.black,
            teamBg
        )
    end
end

local function findEntity(state, id)
    for _, entity in ipairs(state.entities) do
        if entity.id == id and entity.alive then return entity end
    end
    return nil
end

local function drawProjectile(b, state, viewerId, rect, projectile)
    local sx, sy = arena.worldToScreen(viewerId, projectile.x, projectile.y, rect)
    local ch, fg = ".", colors.white

    if projectile.visual == "arrow" then
        local target = findEntity(state, projectile.targetId)
        ch = ">"
        if target then
            local tx, ty = arena.worldToScreen(viewerId, target.x, target.y, rect)
            local dx, dy = tx - sx, ty - sy
            if math.abs(dy) > math.abs(dx) then
                ch = dy >= 0 and "v" or "^"
            else
                ch = dx >= 0 and ">" or "<"
            end
        end
    elseif projectile.visual == "cannonball" then
        ch, fg = "o", colors.lightGray
    elseif projectile.visual == "tower_shot" then
        ch, fg = "*", colors.yellow
    end

    local bg = b.bg[sy] and b.bg[sy][sx] or colors.black
    arenaCell(b, rect, sx, sy, ch, fg, bg)
end

local function drawEffect(b, viewerId, rect, effect)
    local sx, sy = arena.worldToScreen(viewerId, effect.x, effect.y, rect)

    if effect.kind == "hit" then
        local bg = b.bg[sy] and b.bg[sy][sx] or colors.black
        arenaCell(b, rect, sx, sy, "+", colors.white, bg)
        return
    end

    local ex = arena.worldToScreen(viewerId, effect.x + (effect.radius or 1), effect.y, rect)
    local _, ey = arena.worldToScreen(viewerId, effect.x, effect.y + (effect.radius or 1), rect)
    local rx = math.max(1, math.abs(ex - sx))
    local ry = math.max(1, math.abs(ey - sy))
    local fg = effect.kind == "arrows" and colors.yellow or colors.orange
    local ch = effect.kind == "arrows" and "v" or "*"

    for dy = -ry, ry do
        for dx = -rx, rx do
            local nx, ny = dx / rx, dy / ry
            if nx * nx + ny * ny <= 1 then
                local shouldDraw = effect.kind == "arrows"
                    and (math.abs(dx * 3 + dy * 5) % 4 == 0)
                    or (effect.kind ~= "arrows" and (math.abs(dx) + math.abs(dy)) % 2 == 0)
                if shouldDraw then
                    local px, py = sx + dx, sy + dy
                    local bg = b.bg[py] and b.bg[py][px] or colors.black
                    arenaCell(b, rect, px, py, ch, fg, bg)
                end
            end
        end
    end
end

local function drawArena(b, state, viewerId, rect)
    for sy = rect.y1, rect.y2 do
        for sx = rect.x1, rect.x2 do
            local wx, wy = arena.screenToWorld(viewerId, sx, sy, rect)
            setCell(b, sx, sy, " ", colors.white, terrainColor(wx, wy))
        end
    end

    for _, entity in ipairs(state.entities) do
        if entity.alive then drawEntity(b, rect, entity, viewerId) end
    end

    for _, projectile in ipairs(state.projectiles) do
        if projectile.alive then drawProjectile(b, state, viewerId, rect, projectile) end
    end

    for _, effect in ipairs(state.effects) do
        drawEffect(b, viewerId, rect, effect)
    end
end

local scenarioLabels = { "FULL", "TOWERS", "KING", "1V1 TOWER", "EMPTY" }
local scenarioIds = { "full", "princess", "king", "single_tower", "empty" }

function render.draw(monitor, state, viewerId, ui)
    local w, h = monitor.getSize()
    local b = newBuffer(w, h)
    local layout = render.layoutFor(monitor)

    centered(b, 1, "ADMIN SANDBOX", colors.orange, colors.black)
    local status = string.format(
        "SPAWN:P%d  %s  %s",
        ui.owner,
        state.adminPaused and "PAUSED" or "RUNNING",
        string.upper(state.adminScenario or "full")
    )
    centered(b, 2, util.truncate(status, w), colors.white, colors.black)

    for i, z in ipairs(layout.scenarios) do
        drawButton(b, z, scenarioLabels[i], state.adminScenario == scenarioIds[i], colors.lightBlue)
    end

    drawArena(b, state, viewerId, layout.arena)

    drawButton(b, layout.controls[1], "OWNER P" .. tostring(ui.owner), true, ui.owner == 1 and colors.lightBlue or colors.red)
    drawButton(b, layout.controls[2], state.adminPaused and "RUN" or "PAUSE", state.adminPaused, colors.yellow)
    drawButton(b, layout.controls[3], "CLEAR UNITS", false)

    for i, card in ipairs(cards.list) do
        local selected = ui.selectedCard == card.id
        local label = (card.icon or "?") .. " " .. card.name
        drawButton(b, layout.cards[i], label, selected, card.color or colors.orange)
    end

    flush(b, monitor)
end

render.scenarioIds = scenarioIds

return render

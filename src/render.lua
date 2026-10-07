local config = require("config")
local util = require("src.util")
local arena = require("src.arena")
local cards = require("src.cards")
local sprites = require("src.sprites")

local render = {}

local function newBuffer(width, height, defaultFg, defaultBg)
    local buffer = {
        width = width,
        height = height,
        chars = {},
        fg = {},
        bg = {},
    }

    for y = 1, height do
        buffer.chars[y] = {}
        buffer.fg[y] = {}
        buffer.bg[y] = {}
        for x = 1, width do
            buffer.chars[y][x] = " "
            buffer.fg[y][x] = defaultFg or colors.white
            buffer.bg[y][x] = defaultBg or colors.black
        end
    end

    return buffer
end

local function setCell(buffer, x, y, char, fg, bg)
    x = math.floor(x)
    y = math.floor(y)
    if x < 1 or x > buffer.width or y < 1 or y > buffer.height then return end

    buffer.chars[y][x] = (char or " "):sub(1, 1)
    if fg then buffer.fg[y][x] = fg end
    if bg then buffer.bg[y][x] = bg end
end

local function fill(buffer, x1, y1, x2, y2, bg, char, fg)
    x1 = math.max(1, math.floor(x1))
    y1 = math.max(1, math.floor(y1))
    x2 = math.min(buffer.width, math.floor(x2))
    y2 = math.min(buffer.height, math.floor(y2))

    for y = y1, y2 do
        for x = x1, x2 do
            setCell(buffer, x, y, char or " ", fg or colors.white, bg)
        end
    end
end

local function writeText(buffer, x, y, text, fg, bg)
    text = tostring(text or "")
    for i = 1, #text do
        setCell(buffer, x + i - 1, y, text:sub(i, i), fg or colors.white, bg)
    end
end

local function centered(buffer, y, text, fg, bg)
    local x = math.floor((buffer.width - #text) / 2) + 1
    writeText(buffer, x, y, text, fg, bg)
end

local function flush(buffer, monitor)
    for y = 1, buffer.height do
        local chars = {}
        local fg = {}
        local bg = {}

        for x = 1, buffer.width do
            chars[x] = buffer.chars[y][x]
            fg[x] = colors.toBlit(buffer.fg[y][x])
            bg[x] = colors.toBlit(buffer.bg[y][x])
        end

        monitor.setCursorPos(1, y)
        monitor.blit(table.concat(chars), table.concat(fg), table.concat(bg))
    end
end

function render.layoutFor(monitor)
    local width, height = monitor.getSize()
    local handHeight = math.min(8, math.max(6, math.floor(height * 0.16)))
    local arenaBottom = height - handHeight

    local layout = {
        width = width,
        height = height,
        status = { x1 = 1, y1 = 1, x2 = width, y2 = 2 },
        arena = { x1 = 1, y1 = 3, x2 = width, y2 = arenaBottom },
        hand = { x1 = 1, y1 = arenaBottom + 1, x2 = width, y2 = height },
        cards = {},
        readyButton = {
            x1 = math.floor(width * 0.25),
            x2 = math.ceil(width * 0.75),
            y1 = height - 4,
            y2 = height - 2,
        },
        resultButtons = {},
    }

    local cardWidth = math.floor(width / 4)
    for slot = 1, 4 do
        local x1 = (slot - 1) * cardWidth + 1
        local x2 = slot == 4 and width or slot * cardWidth
        layout.cards[slot] = {
            x1 = x1,
            x2 = x2,
            y1 = layout.hand.y1,
            y2 = layout.hand.y2,
        }
    end

    local buttonWidth = math.max(8, math.floor(width / 3))
    layout.resultButtons.rematch = {
        x1 = 2,
        x2 = math.min(width, buttonWidth),
        y1 = height - 3,
        y2 = height - 1,
    }
    layout.resultButtons.deck = {
        x1 = math.floor((width - buttonWidth) / 2) + 1,
        x2 = math.floor((width + buttonWidth) / 2),
        y1 = height - 3,
        y2 = height - 1,
    }
    layout.resultButtons.exit = {
        x1 = math.max(1, width - buttonWidth + 1),
        x2 = width - 1,
        y1 = height - 3,
        y2 = height - 1,
    }

    return layout
end

local function drawButton(buffer, zone, label, active)
    local bg = active and colors.lime or colors.gray
    local fg = active and colors.black or colors.white
    fill(buffer, zone.x1, zone.y1, zone.x2, zone.y2, bg)

    local y = math.floor((zone.y1 + zone.y2) / 2)
    local width = zone.x2 - zone.x1 + 1
    local text = util.truncate(label, math.max(1, width - 2))
    local x = zone.x1 + math.max(0, math.floor((width - #text) / 2))
    writeText(buffer, x, y, text, fg, bg)
end

local function terrainColor(worldX, worldY)
    local terrain = arena.terrainAt(worldX, worldY)
    if terrain == "river" then return colors.blue end
    if terrain == "bridge" then return colors.brown end
    return colors.green
end

local function drawArenaBackground(buffer, playerId, rect)
    for sy = rect.y1, rect.y2 do
        for sx = rect.x1, rect.x2 do
            local wx, wy = arena.screenToWorld(playerId, sx, sy, rect)
            setCell(buffer, sx, sy, " ", colors.white, terrainColor(wx, wy))
        end
    end
end

local function hpColor(entity)
    local ratio = entity.hp / math.max(1, entity.maxHp)
    if ratio > 0.60 then return colors.lime end
    if ratio > 0.30 then return colors.yellow end
    return colors.red
end

local function inside(rect, x, y)
    return x >= rect.x1 and x <= rect.x2 and y >= rect.y1 and y <= rect.y2
end

local function arenaCell(buffer, rect, x, y, char, fg, bg)
    if inside(rect, x, y) then
        setCell(buffer, x, y, char, fg, bg)
    end
end

local function spriteTopLeft(sprite, cx, cy)
    local x = cx - math.floor(sprite.width / 2)
    local y = cy - math.floor((sprite.height - 1) / 2)
    return x, y
end

local function drawHpBar(buffer, rect, entity, playerId, cx, topY, width)
    width = math.max(3, width or 3)
    local barY = topY - 1
    local x1 = cx - math.floor(width / 2)
    local ratio = util.clamp(entity.hp / math.max(1, entity.maxHp), 0, 1)
    local filled = math.ceil(ratio * width)
    local teamBg = entity.owner == playerId and colors.blue or colors.red

    for i = 0, width - 1 do
        local isFilled = i < filled
        arenaCell(
            buffer,
            rect,
            x1 + i,
            barY,
            isFilled and "=" or "-",
            isFilled and hpColor(entity) or colors.black,
            teamBg
        )
    end
end

local function drawEntitySprite(buffer, rect, entity, playerId, cx, cy)
    local sprite = sprites.forEntity(entity)
    local x1, y1 = spriteTopLeft(sprite, cx, cy)
    local isOwn = entity.owner == playerId
    local teamBg = isOwn and colors.blue or colors.red
    local fg = entity.color or colors.white
    local bg = sprite.tower and teamBg or colors.black

    if entity.damageFlash and entity.damageFlash > 0 then
        fg = colors.white
        bg = colors.orange
    elseif entity.fuseRemaining then
        -- Fast, readable Creeper warning without changing combat timing.
        local blink = math.floor(entity.fuseRemaining * 8) % 2 == 0
        fg = blink and colors.white or colors.yellow
    end

    for rowIndex, row in ipairs(sprite.rows) do
        for col = 1, #row do
            local ch = row:sub(col, col)
            if ch ~= " " and ch ~= "." then
                arenaCell(buffer, rect, x1 + col - 1, y1 + rowIndex - 1, ch, fg, bg)
            end
        end
    end

    drawHpBar(buffer, rect, entity, playerId, cx, y1, sprite.width)
end

local function findEntityById(state, id)
    if not id then return nil end
    for _, entity in ipairs(state.entities) do
        if entity.id == id and entity.alive then return entity end
    end
    return nil
end

local function drawProjectile(buffer, state, playerId, rect, projectile)
    local sx, sy = arena.worldToScreen(playerId, projectile.x, projectile.y, rect)
    local symbol = "."
    local fg = colors.white

    if projectile.visual == "arrow" then
        symbol = ">"
        local target = findEntityById(state, projectile.targetId)
        if target then
            local tx, ty = arena.worldToScreen(playerId, target.x, target.y, rect)
            local dx, dy = tx - sx, ty - sy
            if math.abs(dy) > math.abs(dx) then
                symbol = dy >= 0 and "v" or "^"
            else
                symbol = dx >= 0 and ">" or "<"
            end
        end
        fg = colors.white
    elseif projectile.visual == "cannonball" then
        symbol = "o"
        fg = colors.lightGray
    elseif projectile.visual == "tower_shot" then
        symbol = "*"
        fg = colors.yellow
    end

    local bg = buffer.bg[sy] and buffer.bg[sy][sx] or colors.black
    arenaCell(buffer, rect, sx, sy, symbol, fg, bg)
end

local function effectRadiusOnScreen(playerId, rect, effect)
    local sx, sy = arena.worldToScreen(playerId, effect.x, effect.y, rect)
    local rxX = arena.worldToScreen(playerId, effect.x + (effect.radius or 1), effect.y, rect)
    local _, ryY = arena.worldToScreen(playerId, effect.x, effect.y + (effect.radius or 1), rect)
    return sx, sy, math.max(1, math.abs(rxX - sx)), math.max(1, math.abs(ryY - sy))
end

local function drawEffect(buffer, playerId, rect, effect)
    local sx, sy, rx, ry = effectRadiusOnScreen(playerId, rect, effect)

    if effect.kind == "hit" then
        local bg = buffer.bg[sy] and buffer.bg[sy][sx] or colors.black
        arenaCell(buffer, rect, sx, sy, "+", colors.white, bg)
        return
    end

    local fg = effect.kind == "arrows" and colors.yellow or colors.orange
    local symbol = effect.kind == "arrows" and "v" or "*"

    for dy = -ry, ry do
        for dx = -rx, rx do
            local nx = dx / math.max(1, rx)
            local ny = dy / math.max(1, ry)
            local d2 = nx * nx + ny * ny

            if d2 <= 1 then
                local draw = false
                if effect.kind == "arrows" then
                    draw = (math.abs(dx * 3 + dy * 5) % 4 == 0)
                else
                    draw = ((math.abs(dx) + math.abs(dy)) % 2 == 0)
                end

                if draw then
                    local px, py = sx + dx, sy + dy
                    local bg = buffer.bg[py] and buffer.bg[py][px] or colors.black
                    arenaCell(buffer, rect, px, py, symbol, fg, bg)
                end
            end
        end
    end
end

local function drawEntities(buffer, state, playerId, rect)
    for _, entity in ipairs(state.entities) do
        if entity.alive then
            local sx, sy = arena.worldToScreen(playerId, entity.x, entity.y, rect)
            drawEntitySprite(buffer, rect, entity, playerId, sx, sy)
        end
    end

    for _, projectile in ipairs(state.projectiles) do
        if projectile.alive then
            drawProjectile(buffer, state, playerId, rect, projectile)
        end
    end

    for _, effect in ipairs(state.effects) do
        drawEffect(buffer, playerId, rect, effect)
    end
end

local function drawStatus(buffer, state, playerId)
    local player = state.players[playerId]
    local opponent = state.players[playerId == 1 and 2 or 1]

    fill(buffer, 1, 1, buffer.width, 2, colors.black)
    writeText(buffer, 1, 1, "P" .. tostring(playerId), colors.white, colors.black)

    local phaseText
    if state.phase == "battle" then
        phaseText = state.overtime and ("OT " .. util.formatTime(state.timeLeft)) or util.formatTime(state.timeLeft)
    elseif state.phase == "countdown" then
        phaseText = "STARTING"
    else
        phaseText = string.upper(state.phase)
    end
    centered(buffer, 1, phaseText, state.overtime and colors.yellow or colors.white, colors.black)

    local score = tostring(player.towersDestroyed) .. " - " .. tostring(opponent.towersDestroyed)
    writeText(buffer, math.max(1, buffer.width - #score + 1), 1, score, colors.white, colors.black)

    local emeraldText = string.format("EMERALDS %.1f/%.0f", player.emeralds, player.maxEmeralds)
    writeText(buffer, 1, 2, util.truncate(emeraldText, buffer.width), colors.lime, colors.black)

    if player.feedback then
        local text = util.truncate(player.feedback, math.floor(buffer.width * 0.55))
        writeText(buffer, math.max(1, buffer.width - #text + 1), 2, text, colors.yellow, colors.black)
    end
end

local function drawCard(buffer, zone, card, selected, affordable)
    local bg = selected and colors.orange or colors.gray
    if not affordable then bg = colors.black end

    fill(buffer, zone.x1, zone.y1, zone.x2, zone.y2, bg)

    local width = zone.x2 - zone.x1 + 1
    local centerX = zone.x1 + math.floor((width - 1) / 2)
    local sprite = sprites.forCard(card)
    local spriteX = centerX - math.floor(sprite.width / 2)
    local spriteY = zone.y1 + 1

    if selected then
        local label = "SELECT"
        writeText(
            buffer,
            zone.x1 + math.max(0, math.floor((width - #label) / 2)),
            zone.y1,
            label,
            colors.black,
            bg
        )
    end

    for rowIndex, row in ipairs(sprite.rows) do
        for col = 1, #row do
            local ch = row:sub(col, col)
            if ch ~= " " and ch ~= "." then
                setCell(
                    buffer,
                    spriteX + col - 1,
                    spriteY + rowIndex - 1,
                    ch,
                    card.color or colors.white,
                    colors.black
                )
            end
        end
    end

    local nameY = math.min(zone.y2 - 2, zone.y1 + 4)
    local name = util.truncate(card.name, math.max(1, width - 2))
    writeText(
        buffer,
        zone.x1 + math.max(0, math.floor((width - #name) / 2)),
        nameY,
        name,
        colors.white,
        bg
    )

    local cost = (selected and "TAP " or "") .. tostring(card.cost) .. "E"
    writeText(
        buffer,
        zone.x1 + math.max(0, math.floor((width - #cost) / 2)),
        zone.y2 - 1,
        cost,
        affordable and colors.lime or colors.red,
        bg
    )
end

local function drawBattle(buffer, state, playerId, layout)
    drawArenaBackground(buffer, playerId, layout.arena)
    drawEntities(buffer, state, playerId, layout.arena)
    drawStatus(buffer, state, playerId)

    local player = state.players[playerId]
    for slot = 1, 4 do
        local card = cards.get(player.hand[slot])
        if card then
            drawCard(
                buffer,
                layout.cards[slot],
                card,
                player.selectedSlot == slot,
                player.emeralds + 0.0001 >= card.cost
            )
        end
    end

    if state.phase == "countdown" then
        local number = tostring(math.max(1, math.ceil(state.countdown)))
        centered(
            buffer,
            math.floor((layout.arena.y1 + layout.arena.y2) / 2),
            number,
            colors.yellow,
            colors.black
        )
    end
end

local function drawLobby(buffer, state, playerId, layout, monitorName)
    fill(buffer, 1, 1, buffer.width, buffer.height, colors.black)

    centered(buffer, 2, "CC-MINECRAFT ROYALE", colors.lime, colors.black)
    centered(buffer, 4, "PLAYER " .. tostring(playerId), colors.white, colors.black)

    local widthWarning = buffer.width < config.MIN_RECOMMENDED_WIDTH
    local heightWarning = buffer.height < config.MIN_RECOMMENDED_HEIGHT

    local info = string.format("%dx%d @ scale %.1f", buffer.width, buffer.height, config.TEXT_SCALE)
    centered(buffer, 6, info, (widthWarning or heightWarning) and colors.orange or colors.lightGray, colors.black)
    centered(buffer, 7, util.truncate(monitorName, math.max(1, buffer.width - 2)), colors.gray, colors.black)

    if widthWarning or heightWarning then
        centered(buffer, 9, "WARNING: SMALL DISPLAY", colors.orange, colors.black)
    else
        centered(buffer, 9, "3x4 RECOMMENDED LAYOUT READY", colors.lightBlue, colors.black)
    end

    centered(buffer, 11, "V1 TEST DECK - ALL 8 CARDS", colors.yellow, colors.black)

    local allCards = cards.list
    local row = 13
    local columnWidth = math.floor(buffer.width / 2)
    for i, card in ipairs(allCards) do
        local col = (i - 1) % 2
        local listRow = row + math.floor((i - 1) / 2) * 2
        local text = string.format("%s %s %dE", card.icon, card.name, card.cost)
        writeText(
            buffer,
            2 + col * columnWidth,
            listRow,
            util.truncate(text, columnWidth - 3),
            card.color or colors.white,
            colors.black
        )
    end

    local otherId = playerId == 1 and 2 or 1
    local status = state.players[otherId].ready and "OPPONENT: READY" or "OPPONENT: NOT READY"
    centered(buffer, layout.readyButton.y1 - 2, status, state.players[otherId].ready and colors.lime or colors.red, colors.black)
    drawButton(buffer, layout.readyButton, state.players[playerId].ready and "READY!" or "TOGGLE READY", state.players[playerId].ready)
end

local function drawResult(buffer, state, playerId, layout)
    fill(buffer, 1, 1, buffer.width, buffer.height, colors.black)

    local headline
    local headlineColor
    if not state.winner then
        headline = "DRAW"
        headlineColor = colors.yellow
    elseif state.winner == playerId then
        headline = "VICTORY"
        headlineColor = colors.lime
    else
        headline = "DEFEAT"
        headlineColor = colors.red
    end

    centered(buffer, 5, headline, headlineColor, colors.black)
    centered(buffer, 7, util.truncate(state.resultReason or "MATCH OVER", buffer.width - 2), colors.white, colors.black)

    local p = state.players[playerId]
    local o = state.players[playerId == 1 and 2 or 1]
    centered(buffer, 10, string.format("TOWERS %d - %d", p.towersDestroyed, o.towersDestroyed), colors.lightGray, colors.black)

    local rematchStatus = state.players[playerId].rematch and "REMATCH READY" or "REMATCH"
    drawButton(buffer, layout.resultButtons.rematch, rematchStatus, state.players[playerId].rematch)
    drawButton(buffer, layout.resultButtons.deck, "DECK/LOBBY", false)
    drawButton(buffer, layout.resultButtons.exit, "EXIT", false)

    local otherId = playerId == 1 and 2 or 1
    if state.players[otherId].rematch then
        centered(buffer, layout.resultButtons.rematch.y1 - 2, "OPPONENT WANTS REMATCH", colors.lime, colors.black)
    end
end

function render.draw(monitor, state, playerId, monitorName)
    local width, height = monitor.getSize()
    local buffer = newBuffer(width, height, colors.white, colors.black)
    local layout = render.layoutFor(monitor)

    if state.phase == "lobby" then
        drawLobby(buffer, state, playerId, layout, monitorName or "")
    elseif state.phase == "result" then
        drawResult(buffer, state, playerId, layout)
    else
        drawBattle(buffer, state, playerId, layout)
    end

    flush(buffer, monitor)
end

return render

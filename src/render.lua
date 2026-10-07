local config = require("config")
local util = require("src.util")
local cards = require("src.cards")
local pixelArena = require("src.pixel_arena")

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
    local label = selected and ("> " .. (card.icon or "?") .. " <") or (card.icon or "?")
    local name = util.truncate(card.name, math.max(1, width - 2))
    local cost = tostring(card.cost) .. "E"

    writeText(
        buffer,
        zone.x1 + math.max(0, math.floor((width - #label) / 2)),
        zone.y1 + 1,
        label,
        selected and colors.black or (card.color or colors.white),
        bg
    )

    writeText(
        buffer,
        zone.x1 + math.max(0, math.floor((width - #name) / 2)),
        math.min(zone.y2 - 2, zone.y1 + 3),
        name,
        colors.white,
        bg
    )

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
end

local function drawCountdownOverlay(monitor, state, layout)
    if state.phase ~= "countdown" then return end

    local number = tostring(math.max(1, math.ceil(state.countdown)))
    local text = " " .. number .. " "
    local x = math.floor((layout.width - #text) / 2) + 1
    local y = math.floor((layout.arena.y1 + layout.arena.y2) / 2)

    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.yellow)
    monitor.setCursorPos(x, y)
    monitor.write(text)
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
        centered(buffer, 9, "SEMIGRAPHICS PIXEL ARENA READY", colors.lightBlue, colors.black)
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
        flush(buffer, monitor)
    elseif state.phase == "result" then
        drawResult(buffer, state, playerId, layout)
        flush(buffer, monitor)
    else
        drawBattle(buffer, state, playerId, layout)
        flush(buffer, monitor)
        pixelArena.draw(monitor, state, playerId, layout.arena)
        drawCountdownOverlay(monitor, state, layout)
    end
end

return render

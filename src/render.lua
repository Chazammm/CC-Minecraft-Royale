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
        collectionCards = {},
        deckSlots = {},
        modeButton = {
            x1 = math.floor(width * 0.25),
            x2 = math.ceil(width * 0.75),
            y1 = height - 10,
            y2 = height - 8,
        },
        readyButton = {
            x1 = math.floor(width * 0.25),
            x2 = math.ceil(width * 0.75),
            y1 = height - 4,
            y2 = height - 2,
        },
        resultButtons = {},
    }

    local collectionStartY = 5
    local collectionCellH = 5
    for i = 1, 16 do
        local col = (i - 1) % 4
        local row = math.floor((i - 1) / 4)
        layout.collectionCards[i] = {
            x1 = math.floor(col * width / 4) + 1,
            x2 = math.floor((col + 1) * width / 4),
            y1 = collectionStartY + row * collectionCellH,
            y2 = collectionStartY + row * collectionCellH + collectionCellH - 1,
        }
    end

    local deckStartY = 28
    local deckCellH = 4
    for i = 1, 8 do
        local col = (i - 1) % 4
        local row = math.floor((i - 1) / 4)
        layout.deckSlots[i] = {
            x1 = math.floor(col * width / 4) + 1,
            x2 = math.floor((col + 1) * width / 4),
            y1 = deckStartY + row * deckCellH,
            y2 = deckStartY + row * deckCellH + deckCellH - 1,
        }
    end

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

    local emeraldBoost = 0
    for _, entity in ipairs(state.entities) do
        if entity.alive and entity.owner == playerId and entity.emeraldBoost then
            emeraldBoost = emeraldBoost + entity.emeraldBoost
        end
    end

    local emeraldText = string.format("EMERALDS %.1f/%.0f", player.emeralds, player.maxEmeralds)
    if emeraldBoost > 0 then
        emeraldText = emeraldText .. string.format("  +%d%%", math.floor(emeraldBoost * 100 + 0.5))
    end
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

local function deckContains(deck, cardId)
    for _, id in ipairs(deck) do
        if id == cardId then return true end
    end
    return false
end

local function drawCollectionCard(buffer, zone, card, selected)
    local bg = selected and colors.blue or colors.gray
    local fg = selected and colors.white or (card.color or colors.white)
    fill(buffer, zone.x1, zone.y1, zone.x2, zone.y2, bg)

    local width = zone.x2 - zone.x1 + 1
    local top = string.format("%s  %dE", card.icon or "?", card.cost)
    local name = util.truncate(card.name, math.max(1, width - 2))
    local stateText = selected and "IN DECK" or "TAP TO ADD"

    writeText(
        buffer,
        zone.x1 + math.max(0, math.floor((width - #top) / 2)),
        zone.y1,
        top,
        fg,
        bg
    )
    writeText(
        buffer,
        zone.x1 + math.max(0, math.floor((width - #name) / 2)),
        zone.y1 + 2,
        name,
        colors.white,
        bg
    )
    writeText(
        buffer,
        zone.x1 + math.max(0, math.floor((width - #stateText) / 2)),
        zone.y2,
        util.truncate(stateText, width),
        selected and colors.lime or colors.lightGray,
        bg
    )
end

local function drawDeckSlot(buffer, zone, slot, card)
    local bg = card and colors.black or colors.gray
    fill(buffer, zone.x1, zone.y1, zone.x2, zone.y2, bg)

    local width = zone.x2 - zone.x1 + 1
    local label = "SLOT " .. tostring(slot)
    writeText(
        buffer,
        zone.x1 + math.max(0, math.floor((width - #label) / 2)),
        zone.y1,
        label,
        colors.lightGray,
        bg
    )

    if card then
        local name = util.truncate(card.name, math.max(1, width - 2))
        local line = string.format("%s %s", card.icon or "?", name)
        writeText(
            buffer,
            zone.x1 + math.max(0, math.floor((width - #line) / 2)),
            zone.y1 + 2,
            util.truncate(line, width),
            card.color or colors.white,
            bg
        )
    else
        local empty = "-- EMPTY --"
        writeText(
            buffer,
            zone.x1 + math.max(0, math.floor((width - #empty) / 2)),
            zone.y1 + 2,
            empty,
            colors.red,
            bg
        )
    end
end

local function drawLobby(buffer, state, playerId, layout, monitorName)
    fill(buffer, 1, 1, buffer.width, buffer.height, colors.black)

    local player = state.players[playerId]
    local otherId = playerId == 1 and 2 or 1
    local deckCount = #player.deck
    local validDeck = cards.isValidDeck(player.deck)

    centered(buffer, 1, "CC-MINECRAFT ROYALE", colors.lime, colors.black)
    centered(
        buffer,
        2,
        string.format("PLAYER %d - DECK BUILDER  %d/8", playerId, deckCount),
        validDeck and colors.lightBlue or colors.yellow,
        colors.black
    )
    centered(
        buffer,
        3,
        (state.gameMode == "bot" and playerId == 2)
            and "NORMAL BOT DECK - CONTROLLED BY AI"
            or "TAP A CARD TO ADD / REMOVE",
        colors.lightGray,
        colors.black
    )

    for i, card in ipairs(cards.list) do
        drawCollectionCard(
            buffer,
            layout.collectionCards[i],
            card,
            deckContains(player.deck, card.id)
        )
    end

    centered(buffer, 26, "YOUR 8-CARD DECK", colors.yellow, colors.black)

    for slot = 1, 8 do
        local cardId = player.deck[slot]
        drawDeckSlot(buffer, layout.deckSlots[slot], slot, cardId and cards.get(cardId) or nil)
    end

    if player.feedback then
        centered(
            buffer,
            38,
            util.truncate(player.feedback, buffer.width - 2),
            colors.yellow,
            colors.black
        )
    else
        centered(
            buffer,
            38,
            validDeck and "DECK READY" or "SELECT EXACTLY 8 UNIQUE CARDS",
            validDeck and colors.lime or colors.orange,
            colors.black
        )
    end

    centered(
        buffer,
        41,
        util.truncate(string.format("%s  %dx%d", monitorName or "", buffer.width, buffer.height), buffer.width - 2),
        colors.gray,
        colors.black
    )

    if playerId == 1 then
        drawButton(
            buffer,
            layout.modeButton,
            state.gameMode == "bot" and "MODE: VS BOT" or "MODE: PVP",
            state.gameMode == "bot"
        )
    elseif state.gameMode == "bot" then
        drawButton(buffer, layout.modeButton, "P2: BOT CONTROLLED", true)
    end

    local opponentReady = state.players[otherId].ready
    local opponentText
    if state.gameMode == "bot" then
        opponentText = playerId == 1 and "OPPONENT: NORMAL BOT" or "WAITING FOR PLAYER 1"
    else
        opponentText = opponentReady and "OPPONENT: READY" or "OPPONENT: NOT READY"
    end

    centered(
        buffer,
        layout.readyButton.y1 - 2,
        opponentText,
        (state.gameMode == "bot" or opponentReady) and colors.lime or colors.red,
        colors.black
    )

    local readyLabel
    if not validDeck then
        readyLabel = string.format("NEED %d/8", deckCount)
    elseif player.ready then
        readyLabel = "READY!"
    else
        readyLabel = "READY"
    end

    drawButton(buffer, layout.readyButton, readyLabel, player.ready and validDeck)
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

    -- state.stats is a plain data snapshot maintained by the game logic.
    local ps = state.stats and state.stats.players[playerId] or nil
    if ps then
        centered(
            buffer,
            13,
            string.format("PLAYED %d   SPENT %.0fE", ps.cardsPlayed or 0, ps.emeraldSpent or 0),
            colors.white,
            colors.black
        )
        centered(
            buffer,
            15,
            string.format("DMG UNITS %.0f   TOWERS %.0f", ps.unitDamage or 0, ps.towerDamage or 0),
            colors.lightGray,
            colors.black
        )
        centered(
            buffer,
            17,
            string.format("KILLS %d   VILLAGER +%.1fE", ps.kills or 0, ps.villagerBonus or 0),
            colors.lime,
            colors.black
        )
        centered(
            buffer,
            19,
            string.format("WASTED %.1fE   TIME %s", ps.emeraldWasted or 0, util.formatTime(state.stats.elapsed or 0)),
            colors.yellow,
            colors.black
        )

        local bestId, bestValue = nil, -1
        for cardId, stat in pairs(ps.cards or {}) do
            local value = (stat.towerDamage or 0) * 1.5
                + (stat.unitDamage or 0)
                + (stat.kills or 0) * 75
                + (stat.towersKilled or 0) * 400
            if value > bestValue then
                bestId, bestValue = cardId, value
            end
        end

        if bestId then
            local bestCard = cards.get(bestId)
            centered(
                buffer,
                21,
                "TOP CARD: " .. (bestCard and bestCard.name or bestId),
                colors.orange,
                colors.black
            )
        end
    end

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

local config = require("config")
local util = require("src.util")
local cards = require("src.cards")
local pixelArena = require("src.pixel_arena")

local render = {}

local layoutCache = setmetatable({}, { __mode = "k" })
local bufferCache = setmetatable({}, { __mode = "k" })

local function newBuffer(
    width,
    height,
    defaultFg,
    defaultBg,
    skipZone,
    reusable
)
    local buffer = reusable
    if not buffer
        or buffer.width ~= width
        or buffer.height ~= height
    then
        buffer = {
            width = width,
            height = height,
            chars = {},
            fg = {},
            bg = {},
            flushChars = {},
            flushFg = {},
            flushBg = {},
        }
    end

    buffer.width = width
    buffer.height = height

    for y = 1, height do
        local skipped = skipZone
            and y >= skipZone.y1
            and y <= skipZone.y2

        if skipped then
            buffer.chars[y] = nil
            buffer.fg[y] = nil
            buffer.bg[y] = nil
        else
            local chars = buffer.chars[y] or {}
            local fg = buffer.fg[y] or {}
            local bg = buffer.bg[y] or {}
            buffer.chars[y] = chars
            buffer.fg[y] = fg
            buffer.bg[y] = bg

            for x = 1, width do
                chars[x] = " "
                fg[x] = defaultFg or colors.white
                bg[x] = defaultBg or colors.black
            end
        end
    end

    return buffer
end

local function setCell(buffer, x, y, char, fg, bg)
    x = math.floor(x)
    y = math.floor(y)
    if x < 1 or x > buffer.width or y < 1 or y > buffer.height then return end
    if not buffer.chars[y] then return end

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

local function flush(buffer, monitor, skipZone)
    for y = 1, buffer.height do
        local skipped = skipZone
            and y >= skipZone.y1
            and y <= skipZone.y2

        if not skipped then
            local chars = buffer.flushChars[y] or {}
            local fg = buffer.flushFg[y] or {}
            local bg = buffer.flushBg[y] or {}
            buffer.flushChars[y] = chars
            buffer.flushFg[y] = fg
            buffer.flushBg[y] = bg

            for x = 1, buffer.width do
                chars[x] = buffer.chars[y][x]
                fg[x] = colors.toBlit(buffer.fg[y][x])
                bg[x] = colors.toBlit(buffer.bg[y][x])
            end

            monitor.setCursorPos(1, y)
            monitor.blit(table.concat(chars), table.concat(fg), table.concat(bg))
        end
    end
end

function render.layoutFor(monitor)
    local width, height = monitor.getSize()
    local cached = layoutCache[monitor]
    if cached
        and cached.width == width
        and cached.height == height
    then
        return cached
    end

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
        collectionPageButtons = {},
        deckSlots = {},
        evolutionSlot = {
            x1 = 1,
            x2 = math.floor(width * 0.72),
            y1 = 36,
            y2 = 38,
        },
        randomButton = {
            x1 = math.floor(width * 0.72) + 1,
            x2 = width,
            y1 = 36,
            y2 = 38,
        },
        infoButton = {
            x1 = math.floor(width * 0.25),
            x2 = math.ceil(width * 0.75),
            y1 = height - 13,
            y2 = height - 11,
        },
        modeButton = {
            x1 = 1,
            x2 = math.floor(width * 0.50),
            y1 = height - 10,
            y2 = height - 8,
        },
        rulesetButton = {
            x1 = math.floor(width * 0.50) + 1,
            x2 = width,
            y1 = height - 10,
            y2 = height - 8,
        },
        botDifficultyButton = {
            x1 = math.floor(width * 0.25),
            x2 = math.ceil(width * 0.75),
            y1 = height - 7,
            y2 = height - 5,
        },
        rulesetEvolutionButton = {
            x1 = math.floor(width * 0.18),
            x2 = math.ceil(width * 0.82),
            y1 = 10,
            y2 = 14,
        },
        rulesetBackButton = {
            x1 = math.floor(width * 0.25),
            x2 = math.ceil(width * 0.75),
            y1 = height - 4,
            y2 = height - 2,
        },
        readyButton = {
            x1 = math.floor(width * 0.25),
            x2 = math.ceil(width * 0.75),
            y1 = height - 4,
            y2 = height - 2,
        },
        resultButtons = {},
        compactLobby = height < 52,
    }

    if layout.compactLobby then
        -- The collection/deck/evolution area ends at row 38. On the advertised
        -- 42-row minimum, compress the lower controls to one row each instead
        -- of letting their old three-row boxes overlap deck/evolution touches.
        layout.infoButton.y1 = height - 3
        layout.infoButton.y2 = height - 3
        layout.modeButton.y1 = height - 2
        layout.modeButton.y2 = height - 2
        layout.rulesetButton.y1 = height - 2
        layout.rulesetButton.y2 = height - 2
        layout.botDifficultyButton.y1 = height - 1
        layout.botDifficultyButton.y2 = height - 1
        layout.readyButton.y1 = height
        layout.readyButton.y2 = height
        layout.rulesetBackButton.y1 = height
        layout.rulesetBackButton.y2 = height
        layout.opponentStatusY = height - 1
    else
        layout.opponentStatusY = layout.readyButton.y1 - 2
    end

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

    local pageY = 25
    layout.collectionPageButtons.prev = {
        x1 = 1,
        x2 = math.floor(width * 0.22),
        y1 = pageY,
        y2 = pageY,
    }
    layout.collectionPageButtons.label = {
        x1 = math.floor(width * 0.22) + 1,
        x2 = math.floor(width * 0.78),
        y1 = pageY,
        y2 = pageY,
    }
    layout.collectionPageButtons.next = {
        x1 = math.floor(width * 0.78) + 1,
        x2 = width,
        y1 = pageY,
        y2 = pageY,
    }

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

    layoutCache[monitor] = layout
    return layout
end

local function drawButton(buffer, zone, label, active, activeColor)
    local bg = active and (activeColor or colors.lime) or colors.gray
    local fg = active and colors.black or colors.white
    fill(buffer, zone.x1, zone.y1, zone.x2, zone.y2, bg)

    local y = math.floor((zone.y1 + zone.y2) / 2)
    local width = zone.x2 - zone.x1 + 1
    local text = util.truncate(label, math.max(1, width - 2))
    local x = zone.x1 + math.max(0, math.floor((width - #text) / 2))
    writeText(buffer, x, y, text, fg, bg)
end

local function evolutionsEnabled(state)
    return not (
        state
        and type(state.ruleset) == "table"
        and state.ruleset.evolutions == false
    )
end

local function drawStatus(buffer, state, playerId)
    local player = state.players[playerId]
    local opponent = state.players[playerId == 1 and 2 or 1]

    fill(buffer, 1, 1, buffer.width, 2, colors.black)
    writeText(buffer, 1, 1, "P" .. tostring(playerId), colors.white, colors.black)

    local phaseText
    if state.phase == "battle" then
        if state.tiebreaker then
            phaseText = "TIEBREAK"
        else
            if state.overtime then
                local finalSeconds = config.MATCH.overtimeFinalSeconds or 30
                local multiplier = state.timeLeft <= finalSeconds
                    and (config.MATCH.overtimeFinalMultiplier or 3)
                    or (config.MATCH.overtimeMultiplier or 2)
                phaseText = "OT " .. util.formatTime(state.timeLeft) .. " x" .. tostring(multiplier)
            else
                phaseText = util.formatTime(state.timeLeft)
            end
        end
    elseif state.phase == "countdown" then
        phaseText = "STARTING"
    else
        phaseText = string.upper(state.phase)
    end
    centered(buffer, 1, phaseText, state.overtime and colors.yellow or colors.white, colors.black)

    local score = tostring(player.towersDestroyed) .. " - " .. tostring(opponent.towersDestroyed)
    writeText(buffer, math.max(1, buffer.width - #score + 1), 1, score, colors.white, colors.black)

    local emeraldBoost = state.emeraldBoost
        and (state.emeraldBoost[playerId] or 0)
        or 0

    local emeraldText = string.format("EMERALDS %.1f/%.0f", player.emeralds, player.maxEmeralds)
    if emeraldBoost > 0 then
        emeraldText = emeraldText .. string.format("  +%d%%", math.floor(emeraldBoost * 100 + 0.5))
    end
    writeText(buffer, 1, 2, util.truncate(emeraldText, buffer.width), colors.lime, colors.black)

    local rightText = nil
    local rightColor = colors.lightGray

    if player.feedback then
        rightText = util.truncate(player.feedback, math.floor(buffer.width * 0.50))
        rightColor = colors.yellow
    elseif evolutionsEnabled(state)
        and player.evolutionCardId
        and cards.hasEvolution(player.evolutionCardId)
    then
        local evoCard = cards.get(player.evolutionCardId)
        local cycles = cards.evolutionCycles(evoCard)
        if cycles == nil then cycles = 2 end
        local progress = math.min(cycles, player.evolutionProgress or 0)
        local evoState = progress >= cycles and "READY" or (tostring(progress) .. "/" .. tostring(cycles))
        rightText = "EVO " .. evoCard.name .. " " .. evoState
        rightColor = progress >= cycles and colors.magenta or colors.lightBlue

        if player.queue and player.queue[1] then
            local nextCard = cards.get(player.queue[1])
            if nextCard then
                rightText = rightText .. " | NEXT " .. nextCard.name
            end
        end
    elseif player.queue and player.queue[1] then
        local nextCard = cards.get(player.queue[1])
        if nextCard then
            rightText = "NEXT: " .. nextCard.name
            rightColor = nextCard.color or colors.lightGray
        end
    end

    if rightText then
        rightText = util.truncate(rightText, math.floor(buffer.width * 0.52))
        writeText(buffer, math.max(1, buffer.width - #rightText + 1), 2, rightText, rightColor, colors.black)
    end
end

local function compactNameLines(name, width)
    name = tostring(name or "")
    if #name <= width then return { name } end

    local first, rest = name:match("^(%S+)%s+(.+)$")
    if first and rest and #first <= width and #rest <= width then
        return { first, rest }
    end

    return { util.truncate(name, math.max(1, width)) }
end

local function formatEmeraldCost(value)
    value = tonumber(value) or 0
    if math.abs(value - math.floor(value + 0.5)) < 0.000001 then
        return tostring(math.floor(value + 0.5)) .. "E"
    end
    return string.format("%.1fE", value)
end

local function drawCard(buffer, zone, card, selected, affordable, evolutionInfo)
    local evolutionReady = evolutionInfo and evolutionInfo.ready
    local bg = evolutionReady and colors.blue or (selected and colors.orange or colors.gray)
    if not affordable then bg = colors.black end
    fill(buffer, zone.x1, zone.y1, zone.x2, zone.y2, bg)

    local width = zone.x2 - zone.x1 + 1
    local nameLines = compactNameLines(card.name, width)
    local displayCost = evolutionInfo and evolutionInfo.cost or card.cost
    local cost = formatEmeraldCost(displayCost)

    if evolutionInfo then
        local evoText = evolutionInfo.ready
            and "EVO READY"
            or string.format("EVO %d/%d", evolutionInfo.progress, evolutionInfo.cycles)
        writeText(
            buffer,
            zone.x1 + math.max(0, math.floor((width - #evoText) / 2)),
            zone.y1,
            util.truncate(evoText, width),
            evolutionInfo.ready and colors.magenta or colors.lightBlue,
            bg
        )
    end

    local nameY = evolutionInfo
        and math.min(zone.y2 - 3, zone.y1 + 2)
        or math.min(zone.y2 - 3, zone.y1 + 1)
    for i, line in ipairs(nameLines) do
        writeText(
            buffer,
            zone.x1 + math.max(0, math.floor((width - #line) / 2)),
            nameY + i - 1,
            line,
            colors.white,
            bg
        )
    end

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

    if state.tiebreaker then
        fill(
            buffer,
            layout.hand.x1,
            layout.hand.y1,
            layout.hand.x2,
            layout.hand.y2,
            colors.black
        )
        centered(
            buffer,
            math.floor((layout.hand.y1 + layout.hand.y2) / 2),
            "TIEBREAKER - CARDS LOCKED",
            colors.yellow,
            colors.black
        )
        return
    end

    local player = state.players[playerId]
    for slot = 1, 4 do
        local card = cards.get(player.hand[slot])
        if card then
            local evolutionInfo = nil
            local effectiveCost = card.cost

            if evolutionsEnabled(state)
                and player.evolutionCardId == card.id
                and cards.hasEvolution(card.id)
            then
                local cycles = cards.evolutionCycles(card.id)
                if cycles == nil then cycles = 2 end
                local progress = math.min(cycles, player.evolutionProgress or 0)
                local ready = progress >= cycles

                if ready then
                    effectiveCost = cards.evolutionCost(card.id) or card.cost
                end

                evolutionInfo = {
                    cycles = cycles,
                    progress = progress,
                    ready = ready,
                    cost = effectiveCost,
                }
            end

            drawCard(
                buffer,
                layout.cards[slot],
                card,
                player.selectedSlot == slot,
                player.emeralds + 0.0001 >= effectiveCost,
                evolutionInfo
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

local COLLECTION_PAGE_SIZE = 16

local function collectionPageCount()
    return math.max(1, math.ceil(#cards.list / COLLECTION_PAGE_SIZE))
end

local function collectionCardOnPage(player, slot)
    local pages = collectionPageCount()
    local page = math.max(1, math.min(pages, player.collectionPage or 1))
    local index = (page - 1) * COLLECTION_PAGE_SIZE + slot
    return cards.list[index]
end

local function drawCollectionPager(buffer, player, layout)
    local pages = collectionPageCount()
    if pages <= 1 then return end

    local page = math.max(1, math.min(pages, player.collectionPage or 1))
    drawButton(buffer, layout.collectionPageButtons.prev, "< PREV", false)
    drawButton(
        buffer,
        layout.collectionPageButtons.label,
        string.format("CARDS %d/%d", page, pages),
        false
    )
    drawButton(buffer, layout.collectionPageButtons.next, "NEXT >", false)
end

local function contrastTextColor(bg)
    if bg == colors.white
        or bg == colors.lightGray
        or bg == colors.yellow
        or bg == colors.orange
        or bg == colors.lime
        or bg == colors.lightBlue
        or bg == colors.cyan
        or bg == colors.magenta
    then
        return colors.black
    end

    return colors.white
end

local function drawCollectionCard(buffer, zone, card, selected, evolutionSelected, evolutionSelecting)
    local bg = evolutionSelected and colors.blue or (selected and colors.black or colors.gray)
    local accent = card.color or colors.white
    local accentText = contrastTextColor(accent)
    fill(buffer, zone.x1, zone.y1, zone.x2, zone.y2, bg)

    local width = zone.x2 - zone.x1 + 1
    local evoAvailable = cards.hasEvolution(card)
    local top = evoAvailable
        and string.format("EVO  %dE", card.cost)
        or string.format("%dE", card.cost)
    local nameLines = compactNameLines(card.name, width)
    local stateText

    if evolutionSelected then
        stateText = "EVOLUTION"
    elseif evolutionSelecting then
        if selected and evoAvailable then
            stateText = "SET EVO"
        elseif selected then
            stateText = "NO EVO"
        else
            stateText = "NOT IN DECK"
        end
    else
        stateText = selected and "IN DECK" or "TAP TO ADD"
    end

    -- Always show the actual card colour as a full-width accent strip.
    -- This avoids gray/brown cards disappearing into the neutral tile bg.
    fill(buffer, zone.x1, zone.y1, zone.x2, zone.y1, accent)
    writeText(
        buffer,
        zone.x1 + math.max(0, math.floor((width - #top) / 2)),
        zone.y1,
        top,
        accentText,
        accent
    )
    local nameY = #nameLines > 1 and (zone.y1 + 1) or (zone.y1 + 2)
    for i, line in ipairs(nameLines) do
        writeText(
            buffer,
            zone.x1 + math.max(0, math.floor((width - #line) / 2)),
            nameY + i - 1,
            line,
            colors.white,
            bg
        )
    end
    writeText(
        buffer,
        zone.x1 + math.max(0, math.floor((width - #stateText) / 2)),
        zone.y2,
        util.truncate(stateText, width),
        evolutionSelected and colors.magenta
            or (selected and colors.lime or colors.lightGray),
        bg
    )
end

local function drawDeckSlot(buffer, zone, slot, card, evolutionSelected, evolutionSelecting)
    local eligible = card and cards.hasEvolution(card)
    local bg
    if evolutionSelected then
        bg = colors.blue
    elseif evolutionSelecting and eligible then
        bg = colors.blue
    else
        bg = card and colors.black or colors.gray
    end
    fill(buffer, zone.x1, zone.y1, zone.x2, zone.y2, bg)

    local width = zone.x2 - zone.x1 + 1
    local label = "SLOT " .. tostring(slot)
    if evolutionSelected then
        label = "EVO > " .. label
    elseif eligible then
        label = "EVO " .. label
    end
    writeText(
        buffer,
        zone.x1 + math.max(0, math.floor((width - #label) / 2)),
        zone.y1,
        label,
        colors.lightGray,
        bg
    )

    if card then
        local fullName = tostring(card.name or "")
        local nameLines = compactNameLines(fullName, width)

        local nameY = #nameLines > 1 and (zone.y1 + 1) or (zone.y1 + 2)
        for i, line in ipairs(nameLines) do
            writeText(
                buffer,
                zone.x1 + math.max(0, math.floor((width - #line) / 2)),
                nameY + i - 1,
                line,
                card.color or colors.white,
                bg
            )
        end
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

local function drawEvolutionSlot(buffer, zone, player, enabled)
    local selected = player.evolutionCardId and cards.get(player.evolutionCardId) or nil
    local selecting = player.evolutionSelecting == true
    local bg
    if not enabled then
        bg = colors.gray
    else
        bg = selected and colors.blue or (selecting and colors.gray or colors.black)
    end

    fill(buffer, zone.x1, zone.y1, zone.x2, zone.y2, bg)

    local width = zone.x2 - zone.x1 + 1
    local header
    if not enabled then
        header = "EVOLUTION SLOT - RULESET OFF"
    else
        header = selecting and "EVOLUTION SLOT - SELECTING" or "EVOLUTION SLOT"
    end
    writeText(
        buffer,
        zone.x1 + math.max(0, math.floor((width - #header) / 2)),
        zone.y1,
        util.truncate(header, width),
        selected and colors.magenta or colors.lightBlue,
        bg
    )

    local line
    if not enabled then
        if selected and cards.hasEvolution(selected) then
            line = "SAVED: " .. selected.name
        else
            line = "EVOLUTIONS DISABLED FOR THIS MATCH"
        end
    elseif selected and cards.hasEvolution(selected) then
        local cycles = cards.evolutionCycles(selected)
        if cycles == nil then cycles = 2 end
        local evoCost = cards.evolutionCost(selected) or selected.cost

        if cycles == 0 then
            line = string.format(
                "%s | EVERY PLAY EVO | %s",
                selected.name,
                formatEmeraldCost(evoCost)
            )
        else
            line = string.format(
                "%s | %d NORMAL -> EVO | %s",
                selected.name,
                cycles,
                formatEmeraldCost(evoCost)
            )
        end
    elseif selecting then
        line = "TAP AN ELIGIBLE CARD IN YOUR DECK"
    elseif #cards.evolutionCards() == 0 then
        line = "NO EVOLUTION CARDS DEFINED YET"
    else
        line = "TAP SLOT, THEN CHOOSE AN EVO CARD"
    end

    writeText(
        buffer,
        zone.x1 + math.max(0, math.floor((width - #line) / 2)),
        zone.y1 + 1,
        util.truncate(line, width),
        colors.white,
        bg
    )

    local footer
    if not enabled then
        footer = "CHANGE IN RULESET - SELECTION IS PRESERVED"
    else
        footer = selected and "TAP TO CLEAR" or "EVO CARDS ARE MARKED EVO"
    end
    writeText(
        buffer,
        zone.x1 + math.max(0, math.floor((width - #footer) / 2)),
        zone.y2,
        util.truncate(footer, width),
        colors.lightGray,
        bg
    )
end

local function wrapWords(text, maxWidth)
    local lines = {}
    local line = ""

    for word in tostring(text or ""):gmatch("%S+") do
        if line == "" then
            line = word
        elseif #line + 1 + #word <= maxWidth then
            line = line .. " " .. word
        else
            table.insert(lines, line)
            line = word
        end
    end

    if line ~= "" then table.insert(lines, line) end
    return lines
end

local function numberText(value, decimals)
    if value == nil then return "-" end
    if decimals then return string.format("%." .. tostring(decimals) .. "f", value) end
    if math.floor(value) == value then return tostring(math.floor(value)) end
    return string.format("%.1f", value)
end

local function infoStatLines(card)
    local lines = {}

    if card.kind == "unit" then
        local u = card.unit
        local dps = (u.damage or 0) / math.max(0.01, u.attackCooldown or 1)
        local movement = u.flying and "FLYING" or "GROUND"
        if u.waterOnly then
            movement = "STATIONARY WATER"
        elseif u.passive then
            movement = "STATIONARY"
        end

        local targets = u.canAttackAir and "AIR + GROUND" or "GROUND"
        if u.targetMode == "buildings" then targets = "BUILDINGS + CROWN TOWERS" end
        if u.targetMode == "none" then targets = "NONE" end

        table.insert(lines, movement .. " UNIT  |  TARGETS " .. targets)

        if u.beam then
            table.insert(lines, string.format(
                "HP %s  |  RANGE %s  |  WATER ONLY",
                numberText(u.maxHp),
                numberText(u.attackRange, 1)
            ))
            table.insert(lines, string.format(
                "BEAM DPS %s -> %s over %ss",
                numberText(u.beam.baseDps, 0),
                numberText(u.beam.maxDps, 0),
                numberText(u.beam.rampSeconds, 1)
            ))
        elseif u.passive or u.targetMode == "none" then
            table.insert(lines, string.format(
                "HP %s  |  LIFE %ss",
                numberText(u.maxHp),
                numberText(u.lifetime, 0)
            ))
        elseif u.proximityExplosion then
            table.insert(lines, string.format(
                "HP %s  |  SPEED %s  |  AGGRO %s",
                numberText(u.maxHp),
                numberText(u.moveSpeed, 1),
                numberText(u.aggroRange, 1)
            ))
        else
            table.insert(lines, string.format(
                "HP %s  |  DMG %s  |  DPS %.1f",
                numberText(u.maxHp),
                numberText(u.damage),
                dps
            ))
            table.insert(lines, string.format(
                "RANGE %s  |  SPEED %s  |  HIT CD %ss",
                numberText(u.attackRange, 1),
                numberText(u.moveSpeed, 1),
                numberText(u.attackCooldown, 2)
            ))
        end

        if card.spawnCount then
            table.insert(lines, string.format("DEPLOY: %d units at once", card.spawnCount))
        end

        if u.proximityExplosion then
            local e = u.proximityExplosion
            table.insert(lines, string.format(
                "BLAST %s dmg  |  RADIUS %s  |  FUSE %ss",
                numberText(e.damage),
                numberText(e.radius, 1),
                numberText(e.fuseTime, 2)
            ))
            table.insert(lines, string.format(
                "PRIMES inside %s range; cancels past %s",
                numberText(e.triggerRange, 1),
                numberText(e.cancelRange, 1)
            ))
        end

        if u.beam then
            table.insert(lines, string.format(
                "ON DAMAGE: beam charge keeps %d%%",
                math.floor((1 - (u.beam.chargeLossOnHit or 0.20)) * 100 + 0.5)
            ))
        end

        if u.spikeReflectFlying then
            table.insert(lines, string.format(
                "SPIKES: flying attackers take %.0f%% reflected damage",
                u.spikeReflectFlying * 100
            ))
        end

        if u.groundPulse then
            table.insert(lines, string.format(
                "STOMP WHILE MOVING: %s dmg every %ss  |  RADIUS %s",
                numberText(u.groundPulse.damage),
                numberText(u.groundPulse.interval, 1),
                numberText(u.groundPulse.radius, 1)
            ))
        end

        if u.globalEnemyMoveSlow then
            table.insert(lines, string.format(
                "GLOBAL: enemy unit movement -%d%% while alive",
                math.floor(u.globalEnemyMoveSlow * 100 + 0.5)
            ))
        end

        if u.splitOnDeath then
            local splitUnit = cards.getInternalUnit(u.splitOnDeath.template)
            table.insert(lines, string.format(
                "ON DEATH: splits into %dx %s",
                u.splitOnDeath.count or 2,
                splitUnit and splitUnit.name or tostring(u.splitOnDeath.template)
            ))
        end

        if u.periodicSpawn then
            table.insert(lines, string.format(
                "SUMMON: first %ss, then every %ss, max %d alive",
                numberText(u.periodicSpawn.initialDelay or u.periodicSpawn.interval, 1),
                numberText(u.periodicSpawn.interval, 1),
                u.periodicSpawn.maxAlive or 0
            ))
        end

        if u.teleport then
            table.insert(lines, string.format(
                "TELEPORT: %s-%s range  |  CD %ss",
                numberText(u.teleport.minRange, 1),
                numberText(u.teleport.maxRange, 1),
                numberText(u.teleport.cooldown, 1)
            ))
        end

        if u.onHitSlow then
            table.insert(lines, string.format(
                "ON HIT: slows movement %d%% for %ss",
                math.floor((1 - u.onHitSlow.factor) * 100 + 0.5),
                numberText(u.onHitSlow.duration, 1)
            ))
        end

        if u.emeraldBoost then
            table.insert(lines, string.format(
                "ECONOMY: +%d%% Emerald generation while alive",
                math.floor(u.emeraldBoost * 100 + 0.5)
            ))
        elseif u.lifetime and not u.passive then
            table.insert(lines, "LIFETIME: " .. numberText(u.lifetime, 1) .. "s")
        end

        if u.preferredMinRange then
            table.insert(lines, string.format(
                "KITE: backs off below %s range at %d%% speed",
                numberText(u.preferredMinRange, 1),
                math.floor((u.retreatSpeedMultiplier or 1) * 100 + 0.5)
            ))
        end
    elseif card.kind == "building" then
        local b = card.building
        local dps = (b.damage or 0) / math.max(0.01, b.attackCooldown or 1)
        local buildingTargets = b.targetMode == "none"
            and "NONE"
            or (b.canAttackAir and "AIR + GROUND" or "GROUND")

        table.insert(lines, (b.passive and "PASSIVE BUILDING" or "BUILDING")
            .. "  |  TARGETS " .. buildingTargets)

        if b.passive or b.targetMode == "none" then
            table.insert(lines, string.format(
                "HP %s  |  LIFE %ss",
                numberText(b.maxHp),
                numberText(b.lifetime, 0)
            ))
        else
            table.insert(lines, string.format(
                "HP %s  |  DMG %s  |  DPS %.1f",
                numberText(b.maxHp),
                numberText(b.damage),
                dps
            ))
            table.insert(lines, string.format(
                "RANGE %s  |  HIT CD %ss  |  LIFE %ss",
                numberText(b.attackRange, 1),
                numberText(b.attackCooldown, 2),
                numberText(b.lifetime, 0)
            ))
        end

        if b.lifetime and b.lifetime > 0 then
            local decayMultiplier = (config.BUILDINGS and config.BUILDINGS.lifetimeDecayMultiplier) or 1
            local decayPerSecond = ((b.maxHp or 0) / b.lifetime) * decayMultiplier
            local naturalLife = b.lifetime / decayMultiplier
            table.insert(lines, string.format(
                "HP DECAY %.1f/s  |  NATURAL LIFE %.1fs",
                decayPerSecond,
                naturalLife
            ))
        end

        if b.periodicSpawn then
            local spawned = cards.getInternalUnit(b.periodicSpawn.template)
            local totalSpawns = 0
            local first = b.periodicSpawn.initialDelay
                or b.periodicSpawn.interval
                or 0
            local interval = b.periodicSpawn.interval or 0
            local decayMultiplier = (config.BUILDINGS and config.BUILDINGS.lifetimeDecayMultiplier) or 1
            local effectiveLifetime = b.lifetime and (b.lifetime / decayMultiplier) or nil

            if effectiveLifetime and interval > 0 and first < effectiveLifetime then
                totalSpawns = 1 + math.floor(
                    math.max(0, effectiveLifetime - first - 0.000001) / interval
                )
            end

            table.insert(lines, string.format(
                "SPAWN: %s  |  FIRST %ss  |  EVERY %ss",
                spawned and spawned.name or tostring(b.periodicSpawn.template),
                numberText(first, 1),
                numberText(interval, 1)
            ))

            if totalSpawns > 0 then
                table.insert(lines, "SPAWN LIMIT BY LIFETIME: " .. tostring(totalSpawns))
            end

            if spawned then
                table.insert(lines, string.format(
                    "%s: HP %s  |  SPEED %s  |  LIFE %ss",
                    string.upper(spawned.name),
                    numberText(spawned.maxHp),
                    numberText(spawned.moveSpeed, 1),
                    numberText(spawned.lifetime, 0)
                ))

                if spawned.hybridAttack then
                    table.insert(lines, string.format(
                        "PIGLIN AIR: CROSSBOW %s  |  GROUND: AXE %s",
                        numberText(spawned.hybridAttack.rangedDamage),
                        numberText(spawned.hybridAttack.meleeDamage)
                    ))
                end
            end
        end
    elseif card.kind == "spell" then
        local s = card.spell
        table.insert(lines, "SPELL  |  PLACEMENT ANYWHERE")
        table.insert(lines, string.format(
            "DMG %s  |  RADIUS %s",
            numberText(s.damage),
            numberText(s.radius, 1)
        ))
        table.insert(lines, string.format(
            "CROWN TOWER DMG %.1f  |  %d%% modifier",
            (s.damage or 0) * (s.towerMultiplier or 1),
            math.floor((s.towerMultiplier or 1) * 100 + 0.5)
        ))

        if s.delay then
            table.insert(lines, "IMPACT DELAY: " .. numberText(s.delay, 1) .. "s")
        end

        if s.groundOnly then
            table.insert(lines, "TARGETS: GROUND + BUILDINGS + TOWERS")
        elseif card.id == "falling_anvil" then
            table.insert(lines, "TARGETS: AIR + GROUND + BUILDINGS + TOWERS")
        else
            table.insert(lines, "TARGETS: AIR + GROUND + BUILDINGS + TOWERS")
        end
    end


    return lines
end

local function drawInfoCollectionCard(buffer, zone, card, selected)
    local bg = selected and colors.blue or colors.gray
    fill(buffer, zone.x1, zone.y1, zone.x2, zone.y2, bg)

    local width = zone.x2 - zone.x1 + 1
    local top = cards.hasEvolution(card)
        and string.format("EVO %dE", card.cost)
        or string.format("%dE", card.cost)
    local nameLines = compactNameLines(card.name, width)
    local accent = card.color or colors.white
    local accentText = contrastTextColor(accent)

    fill(buffer, zone.x1, zone.y1, zone.x2, zone.y1, accent)
    writeText(
        buffer,
        zone.x1 + math.max(0, math.floor((width - #top) / 2)),
        zone.y1,
        top,
        accentText,
        accent
    )

    local nameY = #nameLines > 1 and (zone.y1 + 2) or (zone.y1 + 3)
    for i, line in ipairs(nameLines) do
        writeText(
            buffer,
            zone.x1 + math.max(0, math.floor((width - #line) / 2)),
            nameY + i - 1,
            line,
            colors.white,
            bg
        )
    end
end

local function drawCardInfoScreen(buffer, state, playerId, layout)
    fill(buffer, 1, 1, buffer.width, buffer.height, colors.black)

    local player = state.players[playerId]
    local selected = cards.get(player.infoCardId) or cards.list[1]
    local info = selected and cards.getInfo(selected.id) or nil

    centered(buffer, 1, "CC-MINECRAFT ROYALE", colors.lime, colors.black)
    centered(buffer, 2, "UNIT INFO / CARD DATABASE", colors.yellow, colors.black)
    centered(buffer, 3, "TAP ANY CARD TO INSPECT", colors.lightGray, colors.black)

    for slot = 1, COLLECTION_PAGE_SIZE do
        local card = collectionCardOnPage(player, slot)
        if card then
            drawInfoCollectionCard(
                buffer,
                layout.collectionCards[slot],
                card,
                selected and card.id == selected.id
            )
        end
    end
    drawCollectionPager(buffer, player, layout)

    if selected then
        centered(
            buffer,
            26,
            string.format("%s  |  %dE", selected.name, selected.cost),
            selected.color or colors.white,
            colors.black
        )

        local descriptionEndY = 28

        if info then
            centered(
                buffer,
                28,
                string.upper(info.role or selected.kind),
                colors.lightBlue,
                colors.black
            )

            local descriptionLines = wrapWords(info.description or "", buffer.width - 4)
            local y = 29
            for i = 1, math.min(2, #descriptionLines) do
                writeText(buffer, 3, y, descriptionLines[i], colors.white, colors.black)
                descriptionEndY = y
                y = y + 1
            end
        end

        local tacticalY = math.max(31, descriptionEndY + 1)

        if info then
            local good = "GOOD VS: " .. tostring(info.goodAgainst or "-")
            local bad = "WEAK VS: " .. tostring(info.badAgainst or "-")
            writeText(
                buffer,
                3,
                tacticalY,
                util.truncate(good, buffer.width - 4),
                colors.lime,
                colors.black
            )
            tacticalY = tacticalY + 1
            writeText(
                buffer,
                3,
                tacticalY,
                util.truncate(bad, buffer.width - 4),
                colors.red,
                colors.black
            )
            tacticalY = tacticalY + 1
        end

        if cards.hasEvolution(selected) then
            local evo = selected.evolution or {}
            local playNumber = cards.evolutionPlayNumber(selected) or 1
            local evoName = evo.name or ("Evolved " .. selected.name)
            local evoCost = cards.evolutionCost(selected) or selected.cost

            writeText(
                buffer,
                3,
                tacticalY,
                string.format(
                    "EVO: %s | PLAY %d | %s",
                    evoName,
                    playNumber,
                    formatEmeraldCost(evoCost)
                ),
                colors.magenta,
                colors.black
            )
            tacticalY = tacticalY + 1

            if evo.description then
                local evoLines = wrapWords(evo.description, buffer.width - 4)
                for i = 1, math.min(2, #evoLines) do
                    writeText(
                        buffer,
                        3,
                        tacticalY,
                        evoLines[i],
                        colors.lightBlue,
                        colors.black
                    )
                    tacticalY = tacticalY + 1
                end
            end
        end

        local statsHeaderY = tacticalY
        writeText(
            buffer,
            3,
            statsHeaderY,
            "STATS / MECHANICS",
            colors.yellow,
            colors.black
        )

        local statY = statsHeaderY + 1
        local statBottom = layout.readyButton.y1 - 2

        for _, line in ipairs(infoStatLines(selected)) do
            local wrapped = wrapWords(line, buffer.width - 4)
            for _, wrappedLine in ipairs(wrapped) do
                if statY > statBottom then break end
                writeText(
                    buffer,
                    3,
                    statY,
                    wrappedLine,
                    colors.lightGray,
                    colors.black
                )
                statY = statY + 1
            end
            if statY > statBottom then break end
        end
    end

    drawButton(buffer, layout.readyButton, "BACK TO DECK", false)
end

local function drawRulesetScreen(buffer, state, playerId, layout)
    fill(buffer, 1, 1, buffer.width, buffer.height, colors.black)

    centered(buffer, 1, "CC-MINECRAFT ROYALE", colors.lime, colors.black)
    centered(buffer, 3, "MATCH RULESET", colors.yellow, colors.black)
    centered(
        buffer,
        5,
        "SHARED MATCH RULES - CHANGES UNREADY BOTH PLAYERS",
        colors.lightGray,
        colors.black
    )

    local evoEnabled = evolutionsEnabled(state)
    drawButton(
        buffer,
        layout.rulesetEvolutionButton,
        "EVOLUTIONS: " .. (evoEnabled and "ON" or "OFF"),
        evoEnabled,
        evoEnabled and colors.lime or colors.red
    )

    local explanation = evoEnabled
        and "Evolution Slots charge and activate normally."
        or "Evolution selections stay saved, but all cards play as BASE forms."

    centered(
        buffer,
        17,
        util.truncate(explanation, buffer.width - 2),
        evoEnabled and colors.lightBlue or colors.orange,
        colors.black
    )

    centered(
        buffer,
        21,
        "MORE RULES CAN BE ADDED HERE LATER",
        colors.gray,
        colors.black
    )

    drawButton(buffer, layout.rulesetBackButton, "BACK TO DECK", false)
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
        (state.gameMode == "bot" and playerId == state.botPlayerId)
            and (string.upper(state.botDifficulty or "normal") .. " BOT DECK - CONTROLLED BY AI")
            or (player.evolutionSelecting
                and "EVOLUTION: TAP AN ELIGIBLE CARD ALREADY IN DECK"
                or "TAP A CARD TO ADD / REMOVE"),
        colors.lightGray,
        colors.black
    )

    for slot = 1, COLLECTION_PAGE_SIZE do
        local card = collectionCardOnPage(player, slot)
        if card then
            drawCollectionCard(
                buffer,
                layout.collectionCards[slot],
                card,
                deckContains(player.deck, card.id),
                player.evolutionCardId == card.id,
                player.evolutionSelecting == true
            )
        end
    end
    drawCollectionPager(buffer, player, layout)

    centered(
        buffer,
        26,
        player.feedback and util.truncate(player.feedback, buffer.width - 2) or "YOUR 8-CARD DECK",
        player.feedback and colors.yellow or colors.yellow,
        colors.black
    )

    for slot = 1, 8 do
        local cardId = player.deck[slot]
        drawDeckSlot(
            buffer,
            layout.deckSlots[slot],
            slot,
            cardId and cards.get(cardId) or nil,
            cardId ~= nil and player.evolutionCardId == cardId,
            player.evolutionSelecting == true
        )
    end

    drawEvolutionSlot(
        buffer,
        layout.evolutionSlot,
        player,
        evolutionsEnabled(state)
    )

    if not (state.gameMode == "bot" and playerId == state.botPlayerId) then
        drawButton(buffer, layout.randomButton, "RANDOM 8", false)
    else
        drawButton(buffer, layout.randomButton, "BOT LOCKED", false)
    end

    drawButton(buffer, layout.infoButton, "UNIT INFO", false)

    local modeLabel = state.gameMode == "bot" and "MODE: VS BOT" or "MODE: PVP"
    if state.gameMode == "bot" then
        modeLabel = string.format("MODE: VS BOT (P%d AI)", state.botPlayerId or 2)
    end

    -- The mode is visible and switchable on both monitors. In VS BOT mode
    -- only the currently selected AI side has its deck controls locked.
    drawButton(
        buffer,
        layout.modeButton,
        modeLabel,
        state.gameMode == "bot"
    )

    local evoRuleEnabled = evolutionsEnabled(state)
    drawButton(
        buffer,
        layout.rulesetButton,
        "RULESET: EVO " .. (evoRuleEnabled and "ON" or "OFF"),
        not evoRuleEnabled,
        evoRuleEnabled and colors.lightBlue or colors.red
    )

    if state.gameMode == "bot" then
        local difficulty = string.upper(state.botDifficulty or "normal")
        drawButton(
            buffer,
            layout.botDifficultyButton,
            "BOT: " .. difficulty,
            difficulty == "HARD"
        )
    end

    local opponentReady = state.players[otherId].ready
    local opponentText
    if state.gameMode == "bot" then
        if playerId == state.botPlayerId then
            opponentText = "CONTROLLED BY AI"
        else
            opponentText = "OPPONENT: " .. string.upper(state.botDifficulty or "normal") .. " BOT"
        end
    else
        opponentText = opponentReady and "OPPONENT: READY" or "OPPONENT: NOT READY"
    end

    if state.gameMode ~= "bot" then
        centered(
            buffer,
            layout.opponentStatusY or (layout.readyButton.y1 - 2),
            opponentText,
            opponentReady and colors.lime or colors.red,
            colors.black
        )
    end

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
    local layout = render.layoutFor(monitor)
    local isArenaFrame = state.phase ~= "lobby" and state.phase ~= "result"
    local buffer = newBuffer(
        width,
        height,
        colors.white,
        colors.black,
        isArenaFrame and layout.arena or nil,
        bufferCache[monitor]
    )
    bufferCache[monitor] = buffer

    if state.phase == "lobby" then
        if state.players[playerId].rulesetOpen then
            drawRulesetScreen(buffer, state, playerId, layout)
        elseif state.players[playerId].infoOpen then
            drawCardInfoScreen(buffer, state, playerId, layout)
        else
            drawLobby(buffer, state, playerId, layout, monitorName or "")
        end
        flush(buffer, monitor)
    elseif state.phase == "result" then
        drawResult(buffer, state, playerId, layout)
        flush(buffer, monitor)
    else
        drawBattle(buffer, state, playerId, layout)
        -- PixelBox redraws the complete arena immediately afterwards, so
        -- avoid sending those rows once as blank text and then a second time
        -- as pixels over the wired monitor network.
        flush(buffer, monitor, layout.arena)
        pixelArena.draw(monitor, state, playerId, layout.arena)
        drawCountdownOverlay(monitor, state, layout)
    end
end

return render

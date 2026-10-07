local config = require("config")
local util = require("src.util")
local cards = require("src.cards")
local pixelArena = require("src.pixel_arena")

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
        arena = { x1 = 1, y1 = 6, x2 = w, y2 = h - 22 },
        controls = makeColumns(w, 4, h - 21, h - 18),
        cards = {},
    }

    local cardTop = h - 17
    local cardHeight = h - cardTop + 1
    for i = 1, 16 do
        local col = (i - 1) % 4
        local row = math.floor((i - 1) / 4)
        layout.cards[i] = {
            x1 = math.floor(col * w / 4) + 1,
            x2 = math.floor((col + 1) * w / 4),
            y1 = cardTop + math.floor(row * cardHeight / 4),
            y2 = cardTop + math.floor((row + 1) * cardHeight / 4) - 1,
        }
    end

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

local scenarioLabels = { "FULL", "TOWERS", "KING", "1V1 TOWER", "EMPTY" }
local scenarioIds = { "full", "princess", "king", "single_tower", "empty" }

function render.draw(monitor, state, viewerId, ui)
    local w, h = monitor.getSize()
    local b = newBuffer(w, h)
    local layout = render.layoutFor(monitor)

    centered(b, 1, "ADMIN SANDBOX", colors.orange, colors.black)
    local botStatus = ui.bot and ui.bot.enabled
        and string.format("BOT:P%d %.1fE", ui.bot.playerId, state.players[ui.bot.playerId].emeralds)
        or "BOT:OFF"

    local status = string.format(
        "SPAWN:P%d  %s  %s  %s",
        ui.owner,
        state.adminPaused and "PAUSED" or "RUNNING",
        string.upper(state.adminScenario or "full"),
        botStatus
    )
    centered(b, 2, util.truncate(status, w), colors.white, colors.black)

    for i, z in ipairs(layout.scenarios) do
        drawButton(b, z, scenarioLabels[i], state.adminScenario == scenarioIds[i], colors.lightBlue)
    end

    drawButton(b, layout.controls[1], "OWNER P" .. tostring(ui.owner), true, ui.owner == 1 and colors.lightBlue or colors.red)
    drawButton(b, layout.controls[2], state.adminPaused and "RUN" or "PAUSE", state.adminPaused, colors.yellow)
    drawButton(b, layout.controls[3], "CLEAR", false)
    drawButton(
        b,
        layout.controls[4],
        ui.bot and ui.bot.enabled and "BOT P2 ON" or "BOT P2 OFF",
        ui.bot and ui.bot.enabled,
        colors.lime
    )

    for i, card in ipairs(cards.list) do
        local selected = ui.selectedCard == card.id
        local label = (card.icon or "?") .. " " .. card.name
        drawButton(b, layout.cards[i], label, selected, card.color or colors.orange)
    end

    flush(b, monitor)
    pixelArena.draw(monitor, state, viewerId, layout.arena)
end

render.scenarioIds = scenarioIds

return render

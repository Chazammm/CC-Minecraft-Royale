local config = require("config")
local hardware = require("src.hardware")
local Game = require("src.game")
local arena = require("src.arena")
local cards = require("src.cards")
local render = require("src.admin_render")
local Bot = require("src.bot")

local hw = hardware.init()
local state = Game.new(function(name, volume, pitch)
    hardware.playSound(hw, name, volume, pitch)
end)

local bot = Bot.new(2)

local initialSpawnCatalog = cards.adminSpawnCards()

local ui = {
    owner = 1,
    selectedCard = initialSpawnCatalog[1] and initialSpawnCatalog[1].key
        or cards.list[1].id,
    cardPage = 1,
    bot = bot,
    spawnCatalog = initialSpawnCatalog,
}

Game.debugLoadScenario(state, "full")

local function nowSeconds()
    if os.epoch then return os.epoch("utc") / 1000 end
    return os.clock()
end

local function hit(z, x, y)
    return z and x >= z.x1 and x <= z.x2 and y >= z.y1 and y <= z.y2
end

local function redraw()
    for viewerId = 1, 2 do
        local ok = pcall(render.draw, hw.monitors[viewerId], state, viewerId, ui)
        if not ok then return false end
    end
    return true
end

local function refreshHardware()
    local ok, refreshed = pcall(hardware.init)
    if not ok or not refreshed then return false end
    hw = refreshed
    return true
end

local function handleTouch(monitorName, x, y)
    local viewerId = hardware.playerForMonitor(hw, monitorName)
    if not viewerId then return end

    local monitor = hw.monitors[viewerId]
    local layout = render.layoutFor(monitor)

    for i, zone in ipairs(layout.scenarios) do
        if hit(zone, x, y) then
            Game.debugLoadScenario(state, render.scenarioIds[i])
            if bot.enabled then Bot.reset(bot, state) end
            redraw()
            return
        end
    end

    if hit(layout.controls[1], x, y) then
        ui.owner = ui.owner == 1 and 2 or 1
        redraw()
        return
    end

    if hit(layout.controls[2], x, y) then
        Game.debugTogglePaused(state)
        redraw()
        return
    end

    if hit(layout.controls[3], x, y) then
        Game.debugClearUnits(state)
        redraw()
        return
    end

    if hit(layout.controls[4], x, y) then
        Bot.toggle(bot, state)
        redraw()
        return
    end

    local pageSize = 16
    local spawnCatalog = initialSpawnCatalog
    local pages = math.max(1, math.ceil(#spawnCatalog / pageSize))

    if hit(layout.cardPageButtons.prev, x, y) then
        ui.cardPage = (ui.cardPage or 1) - 1
        if ui.cardPage < 1 then ui.cardPage = pages end
        redraw()
        return
    elseif hit(layout.cardPageButtons.next, x, y) then
        ui.cardPage = (ui.cardPage or 1) + 1
        if ui.cardPage > pages then ui.cardPage = 1 end
        redraw()
        return
    end

    for slot, zone in ipairs(layout.cards) do
        if hit(zone, x, y) then
            local entry = spawnCatalog[((ui.cardPage or 1) - 1) * pageSize + slot]
            if entry then
                ui.selectedCard = entry.key
                ui.notice = nil
            end
            redraw()
            return
        end
    end

    if hit(layout.arena, x, y) then
        local wx, wy = arena.screenToWorld(viewerId, x, y, layout.arena)
        local ok, reason = Game.debugSpawnCard(
            state,
            ui.owner,
            ui.selectedCard,
            wx,
            wy
        )
        ui.notice = ok and nil or tostring(reason or "INVALID PLACEMENT")
        redraw()
    end
end

local tickTimer = os.startTimer(config.TICK_RATE)
local lastTick = nowSeconds()
local tickAccumulator = 0
local MAX_CATCHUP_STEPS = 5

redraw()

while true do
    local e = { os.pullEventRaw() }
    local name = e[1]

    if name == "terminate" then
        hardware.clear(hw)
        break

    elseif name == "monitor_touch" then
        handleTouch(e[2], e[3], e[4])

    elseif name == "monitor_resize" then
        redraw()

    elseif name == "peripheral" or name == "peripheral_detach" then
        if refreshHardware() then redraw() end

    elseif name == "key" then
        if e[2] == keys.space then
            Game.debugTogglePaused(state)
            redraw()
        elseif e[2] == keys.one then
            ui.owner = 1
            redraw()
        elseif e[2] == keys.two then
            ui.owner = 2
            redraw()
        elseif e[2] == keys.c then
            Game.debugClearUnits(state)
            redraw()
        elseif e[2] == keys.r then
            Game.debugLoadScenario(state, state.adminScenario or "full")
            if bot.enabled then Bot.reset(bot, state) end
            redraw()
        elseif e[2] == keys.b then
            Bot.toggle(bot, state)
            redraw()
        end

    elseif name == "timer" and e[2] == tickTimer then
        local current = nowSeconds()
        local elapsed = current - lastTick
        lastTick = current
        if elapsed <= 0 then elapsed = config.TICK_RATE end

        -- Keep the sandbox on the same bounded fixed timestep as the real
        -- game. Previously Game.update clamped a long frame to 0.25s while
        -- Bot.update received the full wall-clock dt, letting the admin bot
        -- think/generate Emeralds faster than the simulated world after lag.
        local maxCatchup = config.TICK_RATE * MAX_CATCHUP_STEPS
        tickAccumulator = math.min(tickAccumulator + elapsed, maxCatchup)

        local steps = 0
        while tickAccumulator + 1e-9 >= config.TICK_RATE
            and steps < MAX_CATCHUP_STEPS
        do
            Game.update(state, config.TICK_RATE)
            Bot.update(bot, state, config.TICK_RATE)
            tickAccumulator = tickAccumulator - config.TICK_RATE
            steps = steps + 1
        end

        if tickAccumulator < 1e-9 then tickAccumulator = 0 end

        tickTimer = os.startTimer(config.TICK_RATE)
        if not state.adminPaused then redraw() end
    end
end

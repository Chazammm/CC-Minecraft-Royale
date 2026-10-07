local config = require("config")
local hardware = require("src.hardware")
local Game = require("src.game")
local render = require("src.render")
local Bot = require("src.bot")

local hw = hardware.init()

local state = Game.new(function(name, volume, pitch)
    hardware.playSound(hw, name, volume, pitch)
end)

local bot = Bot.new(2)
local previousMode = state.gameMode
local previousPhase = state.phase

local function syncBot()
    if state.gameMode == "bot" then
        if previousMode ~= "bot" and state.phase == "lobby" then
            Bot.prepare(bot, state)
        end

        if state.phase == "countdown" or state.phase == "battle" then
            bot.enabled = true
        elseif state.phase == "lobby" or state.phase == "result" then
            bot.enabled = false
        end
    else
        bot.enabled = false
    end

    previousMode = state.gameMode
    previousPhase = state.phase
end

local function nowSeconds()
    if os.epoch then
        return os.epoch("utc") / 1000
    end
    return os.clock()
end

local function redraw()
    for playerId = 1, 2 do
        render.draw(
            hw.monitors[playerId],
            state,
            playerId,
            hw.monitorNames[playerId]
        )
    end
end

local function isArenaMonitor(name)
    return name == hw.monitorNames[1] or name == hw.monitorNames[2]
end

local tickTimer = os.startTimer(config.TICK_RATE)
local lastTick = nowSeconds()

redraw()

while true do
    local event = { os.pullEventRaw() }
    local name = event[1]

    if name == "terminate" then
        hardware.clear(hw)
        break

    elseif name == "monitor_touch" then
        local monitorName = event[2]
        local x = event[3]
        local y = event[4]
        local playerId = hardware.playerForMonitor(hw, monitorName)

        if playerId then
            local layout = render.layoutFor(hw.monitors[playerId])
            Game.handleTouch(state, playerId, x, y, layout)
            syncBot()
            redraw()
        end

    elseif name == "monitor_resize" then
        local monitorName = event[2]
        if isArenaMonitor(monitorName) then
            redraw()
        end

    elseif name == "timer" and event[2] == tickTimer then
        local current = nowSeconds()
        local dt = current - lastTick
        lastTick = current

        if dt <= 0 then dt = config.TICK_RATE end
        Game.update(state, dt)
        syncBot()
        Bot.update(bot, state, dt)

        tickTimer = os.startTimer(config.TICK_RATE)
        redraw()
    end
end

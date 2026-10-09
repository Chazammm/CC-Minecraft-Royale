local config = require("config")
local hardware = require("src.hardware")
local Game = require("src.game")
local render = require("src.render")
local Bot = require("src.bot")
local Music = require("src.music")

local hw = hardware.init()

local state = Game.new(function(name, volume, pitch)
    hardware.playSound(hw, name, volume, pitch)
end)

local bot = Bot.new(2)
local music = Music.new(hw.musicSpeaker, hw.musicSpeakerName)
music.volume = (config.MUSIC and config.MUSIC.volume) or music.volume
local previousMode = state.gameMode
local previousPhase = state.phase
local previousMusicPhase = state.phase

local function syncBot()
    Bot.setDifficulty(bot, state.botDifficulty or "normal")

    local desiredBotPlayerId = state.botPlayerId or 2
    local botSideChanged = bot.playerId ~= desiredBotPlayerId
    if botSideChanged then
        bot.playerId = desiredBotPlayerId
    end

    if state.gameMode == "bot" then
        if (previousMode ~= "bot" or botSideChanged) and state.phase == "lobby" then
            Bot.prepare(bot, state)
        end

        if state.phase == "countdown" or state.phase == "battle" then
            if state.phase == "countdown" and previousPhase ~= "countdown" then
                Bot.beginMatch(bot)
            end
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

local function syncMusic()
    if state.phase == "battle" and previousMusicPhase ~= "battle" then
        if not config.MUSIC or config.MUSIC.enabled ~= false then
            Music.start(music)
        end
    elseif state.phase ~= "battle" and previousMusicPhase == "battle" then
        -- Do not hard-stop the only speaker here: on one-speaker setups the
        -- victory/defeat SFX may be playing at the same moment.
        Music.stop(music, false)
    end

    previousMusicPhase = state.phase
end

local function nowSeconds()
    if os.epoch then
        return os.epoch("utc") / 1000
    end
    return os.clock()
end

local function redraw()
    for playerId = 1, 2 do
        local ok = pcall(
            render.draw,
            hw.monitors[playerId],
            state,
            playerId,
            hw.monitorNames[playerId]
        )
        if not ok then return false end
    end
    return true
end

local function refreshHardware()
    local ok, refreshed = pcall(hardware.init)
    if not ok or not refreshed then return false end

    hw = refreshed
    music.speaker = hw.musicSpeaker
    music.speakerName = hw.musicSpeakerName
    Music.refreshAvailability(music)
    return true
end

local function isArenaMonitor(name)
    return name == hw.monitorNames[1] or name == hw.monitorNames[2]
end

local tickTimer = os.startTimer(config.TICK_RATE)
local lastTick = nowSeconds()
local tickAccumulator = 0
local MAX_CATCHUP_STEPS = 5

redraw()

while true do
    local event = { os.pullEventRaw() }
    local name = event[1]

    Music.handleEvent(music, event)

    if name == "terminate" then
        Music.stop(music, true)
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
            if state.exitRequested then
                Music.stop(music, true)
                hardware.clear(hw)
                break
            end
            syncBot()
            redraw()
        end

    elseif name == "monitor_resize" then
        local monitorName = event[2]
        if isArenaMonitor(monitorName) then
            redraw()
        end

    elseif name == "peripheral" or name == "peripheral_detach" then
        -- Wired modem/monitor networks can briefly disappear while chunks
        -- reload. Keep the game loop alive and adopt the new wrappers once
        -- both arena monitors are visible again.
        if refreshHardware() then redraw() end

    elseif name == "timer" and event[2] == tickTimer then
        local current = nowSeconds()
        local elapsed = current - lastTick
        lastTick = current

        if elapsed <= 0 then elapsed = config.TICK_RATE end

        -- Gameplay uses a bounded fixed timestep. A temporary CC/HTTP/audio
        -- stall must not turn into one giant physics/combat jump that can skip
        -- river collision, cooldown cadence or short-lived effects.
        local maxCatchup = config.TICK_RATE * MAX_CATCHUP_STEPS
        tickAccumulator = math.min(
            tickAccumulator + elapsed,
            maxCatchup
        )

        local steps = 0
        while tickAccumulator + 1e-9 >= config.TICK_RATE
            and steps < MAX_CATCHUP_STEPS
        do
            Game.update(state, config.TICK_RATE)
            syncBot()
            Bot.update(bot, state, config.TICK_RATE)

            tickAccumulator = tickAccumulator - config.TICK_RATE
            steps = steps + 1
        end

        -- Drop sub-millisecond floating-point residue after catch-up.
        if tickAccumulator < 1e-9 then tickAccumulator = 0 end

        syncMusic()
        Music.pump(music)

        tickTimer = os.startTimer(config.TICK_RATE)
        redraw()
    end
end

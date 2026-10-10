local config = require("config")

local hardware = {}

local function getMonitorNames()
    local names = {}
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "monitor" then
            table.insert(names, name)
        end
    end
    table.sort(names)
    return names
end

local function getSpeakerNames()
    local names = {}
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "speaker" then
            table.insert(names, name)
        end
    end
    table.sort(names)
    return names
end

function hardware.init()
    local monitorNames = {}

    if config.MONITOR_NAMES[1] and config.MONITOR_NAMES[2] then
        monitorNames[1] = config.MONITOR_NAMES[1]
        monitorNames[2] = config.MONITOR_NAMES[2]
    else
        local found = getMonitorNames()
        if #found < 2 then
            error("CC-Minecraft Royale needs two Advanced Monitors. Found: " .. tostring(#found))
        end
        if #found > 2 then
            error("More than two monitors found. Set config.MONITOR_NAMES to the two arena monitors.")
        end
        monitorNames[1] = found[1]
        monitorNames[2] = found[2]
    end

    if monitorNames[1] == monitorNames[2] then
        error("Player 1 and Player 2 must use two different monitor peripherals.")
    end

    local monitors = {}
    for playerId = 1, 2 do
        local name = monitorNames[playerId]
        if not peripheral.isPresent(name) then
            error("Configured monitor is not present: " .. tostring(name))
        end

        if peripheral.getType(name) ~= "monitor" then
            error("Configured peripheral is not a monitor: " .. tostring(name))
        end

        local monitor = peripheral.wrap(name)
        if not monitor then
            error("Could not wrap monitor: " .. tostring(name))
        end

        if monitor.isColor and not monitor.isColor() then
            error("Monitor " .. tostring(name) .. " is not an Advanced Monitor.")
        end

        monitor.setTextScale(config.TEXT_SCALE)
        monitor.setCursorBlink(false)

        local width, height = monitor.getSize()
        if width < (config.MIN_RECOMMENDED_WIDTH or 1)
            or height < (config.MIN_RECOMMENDED_HEIGHT or 1)
        then
            print((
                "WARNING: monitor %s is %dx%d; recommended minimum is %dx%d."
            ):format(
                tostring(name),
                width,
                height,
                config.MIN_RECOMMENDED_WIDTH or 1,
                config.MIN_RECOMMENDED_HEIGHT or 1
            ))
        end

        monitors[playerId] = monitor
    end

    local speakerNames = getSpeakerNames()
    local speakers = {}
    for i, name in ipairs(speakerNames) do
        speakers[i] = peripheral.wrap(name)
    end

    -- With two speakers, keep SFX and streamed music on separate devices so
    -- result sounds and unit effects do not interrupt the battle soundtrack.
    -- With only one speaker, both gracefully share the same device.
    local sfxSpeaker = speakers[1]
    local musicSpeaker = speakers[#speakers]

    return {
        monitorNames = monitorNames,
        monitors = monitors,
        speakerNames = speakerNames,
        speakers = speakers,
        speaker = sfxSpeaker,
        musicSpeaker = musicSpeaker,
        musicSpeakerName = speakerNames[#speakerNames],
    }
end

local function listContains(list, name)
    for _, value in ipairs(list or {}) do
        if value == name then return true end
    end
    return false
end

function hardware.shouldRefreshForPeripheral(ctx, eventName, peripheralName)
    if not ctx or type(peripheralName) ~= "string" then return false end

    if listContains(ctx.monitorNames, peripheralName)
        or listContains(ctx.speakerNames, peripheralName)
    then
        return true
    end

    -- A detached peripheral which was not part of the active hardware set
    -- cannot affect the arena. For newly attached devices, inspect the type
    -- only after the peripheral exists.
    if eventName ~= "peripheral" then return false end

    local ok, pType = pcall(peripheral.getType, peripheralName)
    if not ok then return false end

    if pType == "speaker" then
        return true
    end

    if pType == "monitor" then
        -- With explicit monitor names, an unrelated extra monitor is
        -- irrelevant. Auto-discovery must re-evaluate the topology.
        local explicit = config.MONITOR_NAMES[1] and config.MONITOR_NAMES[2]
        return not explicit
    end

    return false
end

function hardware.playerForMonitor(ctx, monitorName)
    for playerId = 1, 2 do
        if ctx.monitorNames[playerId] == monitorName then
            return playerId
        end
    end
    return nil
end

function hardware.playSound(ctx, name, volume, pitch)
    if not ctx.speaker then return false end
    local ok, result = pcall(ctx.speaker.playSound, name, volume or 1, pitch or 1)
    return ok and result or false
end

function hardware.clear(ctx)
    for _, monitor in ipairs(ctx.monitors or {}) do
        pcall(function()
            monitor.setBackgroundColor(colors.black)
            monitor.setTextColor(colors.white)
            monitor.clear()
            monitor.setCursorPos(1, 1)
        end)
    end
end

return hardware

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

    local monitors = {}
    for playerId = 1, 2 do
        local name = monitorNames[playerId]
        if not peripheral.isPresent(name) then
            error("Configured monitor is not present: " .. tostring(name))
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
        monitors[playerId] = monitor
    end

    return {
        monitorNames = monitorNames,
        monitors = monitors,
        speaker = peripheral.find("speaker"),
    }
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
    for _, monitor in ipairs(ctx.monitors) do
        monitor.setBackgroundColor(colors.black)
        monitor.setTextColor(colors.white)
        monitor.clear()
        monitor.setCursorPos(1, 1)
    end
end

return hardware

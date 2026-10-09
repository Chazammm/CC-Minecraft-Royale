-- Stubbed platform tests for code paths that normally require CC:Tweaked APIs.

package.path = "./?.lua;./?/init.lua;" .. package.path

colors = colors or {
    white = 1,
    black = 32768,
}

local function assertEq(actual, expected, message)
    if actual ~= expected then
        error((message or "assertEq failed")
            .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual))
    end
end

local function assertTrue(value, message)
    if not value then error(message or "assertTrue failed") end
end

do
    local oldPeripheral = peripheral

    local monitors = {
        monitor_a = {
            isColor = function() return true end,
            setTextScale = function() end,
            setCursorBlink = function() end,
            getSize = function() return 60, 50 end,
            setBackgroundColor = function() end,
            setTextColor = function() end,
            clear = function() end,
            setCursorPos = function() end,
        },
        monitor_b = {
            isColor = function() return true end,
            setTextScale = function() end,
            setCursorBlink = function() end,
            getSize = function() return 60, 50 end,
            setBackgroundColor = function() end,
            setTextColor = function() end,
            clear = function() end,
            setCursorPos = function() end,
        },
    }

    peripheral = {
        getNames = function()
            -- Intentionally reversed: hardware.init must sort deterministically.
            return { "monitor_b", "monitor_a" }
        end,
        getType = function(name)
            return monitors[name] and "monitor" or nil
        end,
        isPresent = function(name)
            return monitors[name] ~= nil
        end,
        wrap = function(name)
            return monitors[name]
        end,
    }

    package.loaded["src.hardware"] = nil
    local hardware = require("src.hardware")
    local hw = hardware.init()

    assertEq(hw.monitorNames[1], "monitor_a", "Monitor ordering must be deterministic")
    assertEq(hw.monitorNames[2], "monitor_b", "Monitor ordering must be deterministic")
    assertEq(
        hardware.playerForMonitor(hw, "monitor_b"),
        2,
        "Monitor-to-player mapping must survive sorted discovery"
    )

    -- clear() must tolerate disappearing/broken monitor methods without
    -- crashing the outer shutdown/reconnect path.
    hw.monitors[1].clear = function() error("detached") end
    hardware.clear(hw)

    peripheral = oldPeripheral
    package.loaded["src.hardware"] = nil
end

do
    local oldHttp = http
    local oldFs = fs
    local oldPreload = package.preload["cc.audio.dfpwm"]
    local oldLoaded = package.loaded["cc.audio.dfpwm"]

    fs = {
        exists = function() return false end,
    }
    http = {
        get = function()
            return nil, "offline"
        end,
    }
    package.loaded["cc.audio.dfpwm"] = nil
    package.preload["cc.audio.dfpwm"] = function()
        return {
            make_decoder = function()
                return function(data) return data end
            end,
        }
    end

    package.loaded["src.music"] = nil
    local Music = require("src.music")
    local controller = Music.new({
        playAudio = function() return true end,
    }, "speaker_test")

    assertTrue(controller.available, "Remote music source should be considered available")
    local started = Music.start(controller)
    assertTrue(not started, "Offline HTTP start should fail gracefully")
    assertTrue(controller.active, "Music controller should remain active for retry")
    assertEq(controller.consecutiveFailures, 1, "Failed source open must increment retry streak")
    assertTrue((controller.retryAt or 0) > 0, "Failed source open must schedule a retry")
    Music.stop(controller, false)
    assertEq(controller.consecutiveFailures, 0, "Stopping music must reset retry streak")

    package.loaded["src.music"] = nil
    package.loaded["cc.audio.dfpwm"] = oldLoaded
    package.preload["cc.audio.dfpwm"] = oldPreload
    http = oldHttp
    fs = oldFs
end

do
    local oldHttp = http
    http = {}

    package.loaded["src.report_sync"] = nil
    local ReportSync = require("src.report_sync")
    assertEq(
        ReportSync.tokenPath(),
        ".cc_royale/github_token.txt",
        "Report token must stay in the local hidden config directory"
    )

    local ok, err = ReportSync.upload("bad/kind", "missing.txt", "dummy-token-value-long-enough")
    assertTrue(not ok, "Invalid report kind must be rejected before file/network work")
    assertTrue(
        tostring(err):find("Invalid report kind", 1, true) ~= nil,
        "Invalid report kind should return a useful error"
    )

    package.loaded["src.report_sync"] = nil
    http = oldHttp
end

do
    package.loaded["src.benchmark_utils"] = nil
    local benchmark = require("src.benchmark_utils")
    local randomInt = benchmark.newRandomInt(1337)

    local expected = { 8, 8, 5, 6, 10 }
    for i = 1, #expected do
        assertEq(
            randomInt(10),
            expected[i],
            "Shared benchmark RNG must preserve the historical sequence"
        )
    end

    local original = { "a", "b", "c", "d" }
    local copied = benchmark.copy(original)
    assertTrue(copied ~= original, "Benchmark copy must allocate a new list")
    assertEq(copied[3], "c", "Benchmark copy must preserve list order")

    assertEq(benchmark.mean({ 2, 4, 6 }), 4, "Benchmark mean must stay stable")
    assertEq(
        benchmark.sampleStdDev({ 2, 4, 6 }, 4),
        2,
        "Benchmark sample standard deviation must stay stable"
    )
    assertEq(
        benchmark.critical95(10),
        2.262,
        "Benchmark 95% critical value must stay stable for ten samples"
    )
end

print("Platform stub tests passed")

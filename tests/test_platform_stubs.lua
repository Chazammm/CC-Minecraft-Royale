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
        request = function()
            return false, "offline"
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
    -- Report sync should update history + latest in one Git commit through the
    -- Git Data API instead of creating two Contents-API commits.
    local oldHttp = http
    local oldFs = fs
    local oldTextutils = textutils

    local getUrls = {}
    local writeCalls = {}
    local blobIndex = 0

    local function response(body, code)
        return {
            getResponseCode = function() return code or 200 end,
            readAll = function() return body end,
            close = function() end,
        }
    end

    fs = {
        exists = function(path) return path == "balance_results.txt" end,
        isDir = function() return false end,
        open = function(path, mode)
            if path == "balance_results.txt" and mode == "r" then
                return {
                    readAll = function() return "REPORT BODY" end,
                    close = function() end,
                }
            end
            return nil
        end,
        getName = function(path)
            return path:match("([^/]+)$")
        end,
    }

    textutils = {
        serializeJSON = function() return "PAYLOAD" end,
        unserializeJSON = function(body)
            if body == "REF" then
                return { object = { sha = "parent-sha" } }
            elseif body == "PARENT" then
                return { tree = { sha = "base-tree" } }
            elseif body == "BLOB1" then
                return { sha = "blob-one" }
            elseif body == "BLOB2" then
                return { sha = "blob-two" }
            elseif body == "TREE" then
                return { sha = "new-tree" }
            elseif body == "COMMIT" then
                return { sha = "new-commit" }
            elseif body == "{}" then
                return {}
            end
            return nil, "unexpected fake JSON"
        end,
    }

    http = {
        get = function(options)
            local url = type(options) == "table" and options.url or options
            getUrls[#getUrls + 1] = url
            if url:find("/git/ref/heads/main", 1, true) then
                return response("REF", 200)
            elseif url:find("/git/commits/parent-sha", 1, true) then
                return response("PARENT", 200)
            end
            return nil, "unexpected GET"
        end,
        post = function(options)
            writeCalls[#writeCalls + 1] = {
                method = options.method,
                url = options.url,
            }

            if options.url:find("/git/blobs", 1, true) then
                blobIndex = blobIndex + 1
                return response(blobIndex == 1 and "BLOB1" or "BLOB2", 201)
            elseif options.url:find("/git/trees", 1, true) then
                return response("TREE", 201)
            elseif options.url:find("/git/commits", 1, true) then
                return response("COMMIT", 201)
            elseif options.url:find("/git/refs/heads/main", 1, true)
                and options.method == "PATCH"
            then
                return response("{}", 200)
            end
            return nil, "unexpected write"
        end,
    }

    package.loaded["src.report_sync"] = nil
    local ReportSync = require("src.report_sync")
    local ok, result = ReportSync.upload(
        "balance",
        "balance_results.txt",
        "dummy-token-value-long-enough",
        "12345"
    )
    assertTrue(ok, "Report sync Git Data transaction must succeed")
    assertEq(result.commitSha, "new-commit", "Report sync must expose commit SHA")
    assertEq(#getUrls, 2, "Report sync needs branch + parent reads")
    assertEq(#writeCalls, 5, "Two blobs + tree + commit + ref update expected")

    local patchCount = 0
    for _, call in ipairs(writeCalls) do
        if call.method == "PATCH" then patchCount = patchCount + 1 end
        assertTrue(
            not call.url:find("/contents/", 1, true),
            "Report sync must not use one-commit-per-file Contents API"
        )
    end
    assertEq(patchCount, 1, "Report sync must advance main exactly once")

    package.loaded["src.report_sync"] = nil
    http = oldHttp
    fs = oldFs
    textutils = oldTextutils
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

do
    -- Remote music must queue HTTP asynchronously. An ignored Range response
    -- is rejected from the http_success event without reading body bytes.
    local oldHttp = http
    local oldFs = fs
    local oldEpoch = os.epoch
    local oldManifest = package.loaded["src.music_manifest"]
    local oldMusic = package.loaded["src.music"]
    local oldPreload = package.preload["cc.audio.dfpwm"]
    local oldDfpwm = package.loaded["cc.audio.dfpwm"]

    local requestedUrl = nil
    local reads = 0
    local closes = 0

    fs = {
        exists = function() return false end,
    }
    http = {
        request = function(options)
            requestedUrl = options.url
            return true
        end,
    }
    os.epoch = function() return 123456789 end

    package.loaded["src.music_manifest"] = {
        packs = {
            [1] = {
                path = "missing.dfpwm",
                remoteUrl = "https://example.invalid/music.dfpwm",
                size = 100000,
                version = "test",
            },
        },
        tracks = {
            { id = 1, pack = 1, offset = 50000, bytes = 1000 },
        },
        chunkBytes = 16384,
        volume = 0.25,
    }
    package.loaded["src.music"] = nil
    package.loaded["cc.audio.dfpwm"] = nil
    package.preload["cc.audio.dfpwm"] = function()
        return {
            make_decoder = function()
                return function(data) return data end
            end,
        }
    end

    local Music = require("src.music")
    local controller = Music.new({
        playAudio = function() return true end,
    }, "speaker_range_test")

    local started = Music.start(controller)
    assertTrue(started, "Remote music start should queue an async HTTP request")
    assertTrue(requestedUrl ~= nil, "Async music start must call http.request")
    assertTrue(Music.status(controller).httpPending, "Queued stream must report pending HTTP")
    assertEq(reads, 0, "Queuing remote music must not read response bytes")

    local response = {
        getResponseCode = function() return 200 end,
        read = function()
            reads = reads + 1
            return string.rep("x", 16)
        end,
        close = function() closes = closes + 1 end,
    }
    Music.handleEvent(controller, { "http_success", requestedUrl, response })

    assertEq(reads, 0, "Ignored Range response must not discard body bytes to seek")
    assertTrue(closes > 0, "Ignored Range response must be closed")
    assertTrue(
        controller.error == "MUSIC HTTP RANGE UNSUPPORTED",
        "Ignored Range response must schedule a clear retry error"
    )

    package.loaded["src.music"] = oldMusic
    package.loaded["src.music_manifest"] = oldManifest
    package.loaded["cc.audio.dfpwm"] = oldDfpwm
    package.preload["cc.audio.dfpwm"] = oldPreload
    os.epoch = oldEpoch
    http = oldHttp
    fs = oldFs
end

do
    -- Successful 206 responses are attached only when their event arrives;
    -- Music.start itself must never perform a blocking body read.
    local oldHttp = http
    local oldFs = fs
    local oldEpoch = os.epoch
    local oldManifest = package.loaded["src.music_manifest"]
    local oldMusic = package.loaded["src.music"]
    local oldPreload = package.preload["cc.audio.dfpwm"]
    local oldDfpwm = package.loaded["cc.audio.dfpwm"]

    local requestedUrl = nil
    local reads = 0
    local plays = 0

    fs = { exists = function() return false end }
    http = {
        request = function(options)
            requestedUrl = options.url
            return true
        end,
    }
    os.epoch = function() return 123456789 end

    package.loaded["src.music_manifest"] = {
        packs = {
            [1] = {
                path = "missing.dfpwm",
                remoteUrl = "https://example.invalid/music.dfpwm",
                size = 1000,
                version = "test",
            },
        },
        tracks = {
            { id = 1, pack = 1, offset = 10, bytes = 4 },
        },
        chunkBytes = 4,
        volume = 0.25,
    }
    package.loaded["src.music"] = nil
    package.loaded["cc.audio.dfpwm"] = nil
    package.preload["cc.audio.dfpwm"] = function()
        return {
            make_decoder = function()
                return function(data) return data end
            end,
        }
    end

    local Music = require("src.music")
    local controller = Music.new({
        playAudio = function(_, data)
            plays = plays + 1
            return data ~= nil
        end,
    }, "speaker_async_test")

    assertTrue(Music.start(controller), "Async 206 test must queue successfully")
    assertEq(reads, 0, "Music.start must not synchronously read remote audio")

    local returned = false
    local response = {
        getResponseCode = function() return 206 end,
        read = function()
            reads = reads + 1
            if returned then return nil end
            returned = true
            return "DATA"
        end,
        close = function() end,
    }
    Music.handleEvent(controller, { "http_success", requestedUrl, response })
    assertEq(reads, 1, "HTTP success event should feed one audio chunk")
    assertEq(plays, 1, "HTTP success event should queue decoded audio")

    Music.stop(controller, false)
    package.loaded["src.music"] = oldMusic
    package.loaded["src.music_manifest"] = oldManifest
    package.loaded["cc.audio.dfpwm"] = oldDfpwm
    package.preload["cc.audio.dfpwm"] = oldPreload
    os.epoch = oldEpoch
    http = oldHttp
    fs = oldFs
end

do
    -- Setup must reject a token which authenticates but lacks repository push
    -- permission, instead of failing only after a long benchmark.
    local oldHttp = http
    local oldTextutils = textutils

    local function response(body, code)
        return {
            getResponseCode = function() return code or 200 end,
            readAll = function() return body end,
            close = function() end,
        }
    end

    http = {
        get = function()
            return response('{"permissions":{"pull":true,"push":false}}', 200)
        end,
    }
    textutils = {
        unserializeJSON = function()
            return { permissions = { pull = true, push = false } }
        end,
    }

    package.loaded["src.report_sync"] = nil
    local ReportSync = require("src.report_sync")
    local ok, message = ReportSync.verifyToken("dummy-token-value-long-enough")
    assertTrue(not ok, "Read-only report token must be rejected during setup")
    assertTrue(
        tostring(message):find("cannot write", 1, true) ~= nil,
        "Read-only token error must explain missing write access"
    )

    package.loaded["src.report_sync"] = nil
    http = oldHttp
    textutils = oldTextutils
end

print("Platform stub tests passed")

-- Reproductions for the third audit's actual failure paths.
package.path = "./?.lua;./?/init.lua;" .. package.path
colors = colors or {
    white=1,orange=2,magenta=4,lightBlue=8,yellow=16,lime=32,
    pink=64,gray=128,lightGray=256,cyan=512,purple=1024,
    blue=2048,brown=4096,green=8192,red=16384,black=32768,
}
local passed = 0
local function check(ok, message)
    if not ok then error(message or "audit fix assertion failed", 2) end
    passed = passed + 1
end
local function eq(actual, expected, message)
    check(actual == expected, (message or "different")
        .. ": expected " .. tostring(expected)
        .. ", got " .. tostring(actual))
end
local function filesystem(initial, opts)
    local stored, deleted = {}, {}
    for k, v in pairs(initial or {}) do stored[k] = v end
    opts = opts or {}
    local fake = {
        exists = function(path) return stored[path] ~= nil end,
        isDir = function(path) return opts.directory == path end,
        getDir = function(path) return path:match("^(.*)/[^/]+$") or "" end,
        makeDir = function() end,
        open = function(path, mode)
            if mode == "r" and stored[path] ~= nil then
                return { readAll = function() return stored[path] end,
                    close = function() end }
            end
            if mode == "w" then
                local buffer = ""
                return {
                    write = function(value) buffer = buffer .. tostring(value) end,
                    flush = function() end,
                    close = function() stored[path] = buffer end,
                }
            end
        end,
        delete = function(path)
            deleted[#deleted + 1] = path
            if opts.directory == path then error("directory must not be deleted") end
            stored[path] = nil
        end,
        move = function(from, to)
            if opts.failMoveFrom == from then error("injected move failure") end
            if stored[from] == nil then error("no source " .. from) end
            stored[to] = stored[from]
            stored[from] = nil
        end,
    }
    return fake, stored, deleted
end

do
    local oldFs = fs
    local output = require("src.report_output")
    local mock, saved = filesystem({["balance_results.txt"] = "COMPLETE OLD"})
    fs = mock
    local writer = assert(output.start("balance_results.txt"))
    writer.write("PARTIAL")
    eq(saved["balance_results.txt"], "COMPLETE OLD",
        "In-progress run must preserve the previous complete report")
    writer.close() -- emulate an interrupted run with a completed temp file
    eq(saved["balance_results.txt"], "COMPLETE OLD", "Crash must not publish partial report")
    writer = assert(output.start("balance_results.txt"))
    writer.write("NEW COMPLETE")
    local ok = output.commit("balance_results.txt", writer)
    check(ok, "Complete report must publish atomically")
    eq(saved["balance_results.txt"], "NEW COMPLETE", "New report content")
    eq(saved["balance_results.txt.tmp"], nil, "Temp must be promoted")
    eq(saved["balance_results.txt.bak"], nil, "Backup must be cleared")

    local opts = { failMoveFrom = "balance_results.txt.tmp" }
    mock, saved = filesystem({["balance_results.txt"] = "SAFE PRIOR"}, opts)
    fs = mock
    writer = assert(output.start("balance_results.txt"))
    writer.write("UNSAFE NEW")
    ok = output.commit("balance_results.txt", writer)
    check(not ok, "Failed report promote must return error")
    eq(saved["balance_results.txt"], "SAFE PRIOR", "Failed promote must restore prior report")

    mock, saved = filesystem({
        ["balance_results.txt.bak"] = "CRASHED PRIOR",
        ["balance_results.txt.tmp"] = "CRASHED PARTIAL",
    })
    fs = mock
    writer = assert(output.start("balance_results.txt"))
    eq(saved["balance_results.txt"], "CRASHED PRIOR",
        "Next invocation must restore backup after power loss")
    writer.close()
    fs = oldFs
end

do
    local oldFs, oldHttp, oldTextutils, oldPrint, oldWrite =
        fs, http, textutils, print, write
    local mock, saved, deleted = filesystem({
        [".cc_royale_managed"] =
            "deck_presets.db\n.cc_royale/github_token.txt\nsrc/my_custom.lua\n",
        ["deck_presets.db"] = "VALUABLE DECK DATA",
        [".cc_royale/github_token.txt"] = "SECRET MUST STAY",
        ["src/my_custom.lua"] = "OWNED BY PLAYER",
    })
    fs = mock
    http = {
        get = function(options)
            if options.url:find("/commits/main", 1, true) then
                return {getResponseCode=function() return 200 end,
                    readAll=function() return '{"sha":"abcdefghij12345"}' end,
                    close=function() end}
            end
            return {getResponseCode=function() return 200 end,
                readAll=function() return "return {}\n" end,
                close=function() end}
        end,
    }
    textutils = {unserializeJSON=function() return {sha="abcdefghij12345"} end}
    print, write = function() end, function() end

    local ok, err = pcall(dofile, "install.lua")
    check(ok, "Stub installer should succeed: " .. tostring(err))
    eq(saved["deck_presets.db"], "VALUABLE DECK DATA",
        "Corrupt managed manifest must never delete player preset")
    eq(saved[".cc_royale/github_token.txt"], "SECRET MUST STAY",
        "Corrupt managed manifest must never delete GitHub credentials")
    eq(saved["src/my_custom.lua"], "OWNED BY PLAYER",
        "Corrupt managed manifest must never delete arbitrary player files")
    for _, path in ipairs(deleted) do
        check(path ~= "deck_presets.db"
            and path ~= ".cc_royale/github_token.txt"
            and path ~= "src/my_custom.lua", "Unsafe stale deletion: " .. path)
    end

    local failedClosed = 0
    fs, saved = filesystem({})
    http = {
        get = function()
            return nil, "503", {close=function() failedClosed=failedClosed+1 end}
        end,
    }
    ok = pcall(dofile, "install.lua")
    check(not ok, "Installer must reject an unavailable commit API")
    eq(failedClosed, 1, "Failed GitHub response handle must be closed")
    eq(saved[".cc_royale_installing"], nil,
        "Download failure must not write recovery marker")
    fs, http, textutils, print, write =
        oldFs, oldHttp, oldTextutils, oldPrint, oldWrite
end

do
    local arena = require("src.arena")
    local attacker = { x=50, y=105, attackRange=10 }
    local x, y = arena.groundReachPoint(attacker, {x=50, y=80})
    check(y > 86, "Attacker south of river should select reachable south bank")
    eq(x, 50, "South bank must align with target x")
    check(arena.isWalkable(attacker, x, y), "Chosen attack point must be walkable")
end

do
    local oldHttp, oldFs, oldEpoch = http, fs, os.epoch
    local oldManifest = package.loaded["src.music_manifest"]
    local oldMusic = package.loaded["src.music"]
    local oldPreload = package.preload["cc.audio.dfpwm"]
    local oldDfpwm = package.loaded["cc.audio.dfpwm"]
    local clock, url, reads, closes, plays = 0, nil, 0, 0, 0
    fs = {exists=function() return false end}
    http = {request=function(options) url=options.url return true end}
    os.epoch = function() return clock end
    package.loaded["src.music_manifest"] = {
        packs = {{remoteUrl="https://example.invalid/music.dfpwm",
            path="absent.dfpwm", size=1000}},
        tracks = {{id=1, pack=1, offset=10, bytes=4}},
        chunkBytes=4, volume=0.3,
    }
    package.loaded["src.music"] = nil
    package.loaded["cc.audio.dfpwm"] = nil
    package.preload["cc.audio.dfpwm"] = function()
        return {make_decoder=function() return function(data) return data end end}
    end
    local Music = require("src.music")
    local controller = Music.new({playAudio=function() plays=plays+1 return true end}, "speaker_test")
    check(Music.start(controller), "HTTP music should queue request")
    local staleUrl = url
    clock = 15000
    Music.pump(controller)
    eq(controller.error, "MUSIC HTTP TIMEOUT", "Lost async event must time out")
    check(not controller.httpPending, "Timed-out request must be abandoned")

    local orphan = {close=function() closes=closes+1 end}
    Music.handleEvent(controller, {"http_success", staleUrl, orphan})
    eq(closes, 1, "Late stream handle must be closed even after timeout")
    local unrelated = {close=function() closes=closes+1 end}
    Music.handleEvent(controller, {"http_success", "https://unrelated.invalid/other", unrelated})
    eq(closes, 1, "Music must not close other software's HTTP handles")

    controller.retryAt = 0
    Music.pump(controller)
    check(controller.httpPending, "Music must retry after timeout")

    local bad = {
        getResponseCode=function() return 206 end,
        getResponseHeaders=function() return {} end,
        read=function() reads=reads+1 return "BAD!" end,
        close=function() closes=closes+1 end,
    }
    Music.handleEvent(controller, {"http_success", url, bad})
    eq(controller.error, "MUSIC HTTP RANGE MISMATCH",
        "206 without Content-Range must not be trusted")
    eq(reads, 0, "Unverified audio must never be decoded")

    controller.retryAt = 0
    Music.pump(controller)
    local good = {
        getResponseCode=function() return 206 end,
        getResponseHeaders=function()
            return {["CoNtEnT-RaNgE"]="bytes 10-13/1000"}
        end,
        read=function()
            reads=reads+1
            return "GOOD"
        end,
        close=function() closes=closes+1 end,
    }
    Music.handleEvent(controller, {"http_success", url, good})
    eq(plays, 1, "Case-insensitive valid byte range must play")
    Music.stop(controller, false)
    package.loaded["src.music_manifest"] = oldManifest
    package.loaded["src.music"] = oldMusic
    package.loaded["cc.audio.dfpwm"] = oldDfpwm
    package.preload["cc.audio.dfpwm"] = oldPreload
    os.epoch, http, fs = oldEpoch, oldHttp, oldFs
end
print("Third-audit fix regressions passed (" .. passed .. " assertions)")

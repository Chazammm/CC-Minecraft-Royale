-- Lightweight CLI and manifest checks split out of test_v1.lua to keep the
-- legacy smoke chunk comfortably below Lua's active-local limit.

colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768,
}

package.path = "./?.lua;./?/init.lua;" .. package.path

local musicManifest = require("src.music_manifest")

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

local packOffsets = { [1] = 0, [2] = 0 }
local totalMusicBytes = 0
for i, track in ipairs(musicManifest.tracks) do
    assertEq(track.id, i, "Music track IDs must be sequential")
    assertTrue(
        track.pack == 1 or track.pack == 2,
        "Music track must reference a valid pack"
    )
    assertEq(
        track.offset,
        packOffsets[track.pack],
        "Music track offsets must be contiguous inside each pack"
    )
    assertTrue(track.bytes > 0, "Music track must contain audio bytes")
    packOffsets[track.pack] = packOffsets[track.pack] + track.bytes
    totalMusicBytes = totalMusicBytes + track.bytes
end

assertEq(
    packOffsets[1],
    musicManifest.packs[1].size,
    "Music pack 1 manifest size mismatch"
)
assertEq(
    packOffsets[2],
    musicManifest.packs[2].size,
    "Music pack 2 manifest size mismatch"
)
assertEq(
    totalMusicBytes,
    musicManifest.totalSize,
    "Music manifest must cover the whole HQ playlist"
)

for _, pack in pairs(musicManifest.packs) do
    assertTrue(
        not pack.remoteUrl:find("/main/", 1, true),
        "Music pack URLs must be immutable and never follow moving main"
    )
end

-- CLI help/validation must not erase a previous simulation report.
local oldFs = fs
local simulateOpenCalls = 0
fs = {
    open = function()
        simulateOpenCalls = simulateOpenCalls + 1
        return nil
    end,
}

assert(loadfile("mechanics_test.lua"), "mechanics_test.lua must compile")
assert(loadfile("compare.lua"), "compare.lua must compile")
assert(loadfile("evo_compare.lua"), "evo_compare.lua must compile")
assert(loadfile("report_sync.lua"), "report_sync.lua must compile")
assert(loadfile("src/report_sync.lua"), "src/report_sync.lua must compile")
assert(loadfile("src/headless_match.lua"), "src/headless_match.lua must compile")

local simulateChunk = assert(loadfile("simulate.lua"))
simulateChunk("help")
simulateChunk("99")
assertEq(
    simulateOpenCalls,
    0,
    "simulate help/invalid input must not open or truncate balance_results.txt"
)
fs = oldFs

print("CLI and manifest tests passed")

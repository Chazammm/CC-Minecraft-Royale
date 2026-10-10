-- Run the actual in-game mechanics suite as a required GitHub CI test.
-- A passing headless smoke suite alone cannot detect stale in-game assertions.
-- Use a minimal CC:Tweaked filesystem shim; no mock game/combat functions.
colors = {
    white=1, orange=2, magenta=4, lightBlue=8,
    yellow=16, lime=32, pink=64, gray=128,
    lightGray=256, cyan=512, purple=1024, blue=2048,
    brown=4096, green=8192, red=16384, black=32768,
}
package.path = "./?.lua;./?/init.lua;" .. package.path

local reportPath = "mechanics_report.txt"
local reportBody = nil
local fileStore = {}
local oldFs, oldWrite = fs, write

fs = {
    exists = function(path) return fileStore[path] ~= nil end,
    isDir = function() return false end,
    open = function(path, mode)
        if mode == "r" and fileStore[path] then
            return {
                readAll = function() return fileStore[path] end,
                close = function() end,
            }
        end
        if mode == "w" and path == reportPath then
            local buffer = ""
            return {
                write = function(bytes) buffer = buffer .. tostring(bytes) end,
                close = function()
                    fileStore[path] = buffer
                    reportBody = buffer
                end,
            }
        end
        return nil
    end,
}

write = function(message) io.write(tostring(message)) end

local ok, err = pcall(dofile, "mechanics_test.lua")

fs, write = oldFs, oldWrite
assert(ok, "In-game mechanics suite raised an error: " .. tostring(err))
assert(type(reportBody) == "string", "Suite did not save its results")
assert(reportBody:find("END_OF_REPORT", 1, true),
    "Mechanics report was not completed")

local pass, fail, errors, total = reportBody:match(
    "SUMMARY|pass=(%d+)|fail=(%d+)|error=(%d+)|total=(%d+)"
)
assert(total, "Mechanics report omitted summary")
pass, fail, errors, total =
    tonumber(pass), tonumber(fail), tonumber(errors), tonumber(total)
assert(total >= 24, "Mechanics suite unexpectedly lost test cases")
assert(pass == total and fail == 0 and errors == 0,
    ("In-game mechanics check: %d PASS / %d FAIL / %d ERROR of %d")
        :format(pass, fail, errors, total))
assert(reportBody:find("RESULT|evo_charged_creeper|PASS|", 1, true),
    "Charged Creeper test must pass after high-HP dummy fixture")
assert(reportBody:find("DATA|evo_charged_creeper|near_target_damage=580.0000", 1, true),
    "Charged Creeper must deal its entire 580 blast damage")
assert(reportBody:find("DATA|evo_charged_creeper|far_target_damage=580.0000", 1, true),
    "Charged Creeper should hit at radius 10, outside base radius 8")
assert(reportBody:find("RESULT|evoker_fangs_vex|PASS|", 1, true),
    "Evoker Fangs/Vex test must pass")
assert(reportBody:find("DATA|evoker_fangs_vex|zombie_line_damage=85.0000", 1, true)
    and reportBody:find("DATA|evoker_fangs_vex|skeleton_line_damage=85.0000", 1, true),
    "Telegraphed Fang line must hit both grounded victims")

print(("Full in-game mechanics suite passed in Lua CI: %d/%d")
    :format(pass, total))

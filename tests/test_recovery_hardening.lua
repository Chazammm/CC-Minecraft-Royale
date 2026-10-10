-- Recovery/crash-state regressions for installer and preset persistence.
colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768,
}

package.path = "./?.lua;./?/init.lua;" .. package.path

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

local cards = require("src.cards")

local function validPreset()
    return {
        [1] = { [1] = cards.defaultDeck() },
        [2] = {},
    }
end

local function loadGameWithPresetFiles(initial, decodedByBody)
    local oldFs = fs
    local oldTextutils = textutils
    local oldGameLoaded = package.loaded["src.game"]
    local stored = {}

    for path, body in pairs(initial or {}) do stored[path] = body end

    fs = {
        exists = function(path) return stored[path] ~= nil end,
        isDir = function() return false end,
        open = function(path, mode)
            if mode == "r" and stored[path] ~= nil then
                return {
                    readAll = function() return stored[path] end,
                    close = function() end,
                }
            end
            if mode == "w" then
                local buffer = ""
                return {
                    write = function(value) buffer = buffer .. tostring(value) end,
                    close = function() stored[path] = buffer end,
                }
            end
            return nil
        end,
        move = function(from, to)
            assert(stored[from] ~= nil, "fake move source missing: " .. tostring(from))
            stored[to] = stored[from]
            stored[from] = nil
        end,
        delete = function(path) stored[path] = nil end,
    }

    textutils = {
        unserialize = function(raw)
            local value = decodedByBody[raw]
            if type(value) == "function" then return value() end
            return value
        end,
        serialize = function() return "SERIALIZED" end,
    }

    package.loaded["src.game"] = nil
    local ReloadedGame = require("src.game")
    local state = ReloadedGame.new()

    package.loaded["src.game"] = oldGameLoaded
    fs = oldFs
    textutils = oldTextutils
    return state, stored
end

-- Final is authoritative when valid; stale temp/backup debris is discarded.
do
    local state, stored = loadGameWithPresetFiles({
        ["deck_presets.db"] = "FINAL",
        ["deck_presets.db.tmp"] = "TMP",
        ["deck_presets.db.bak"] = "BAK",
    }, {
        FINAL = validPreset,
        TMP = validPreset,
        BAK = validPreset,
    })

    assertTrue(cards.isValidDeck(state.deckPresets[1][1]), "Valid final preset must load")
    assertEq(stored["deck_presets.db"], "FINAL", "Valid final preset must win")
    assertEq(stored["deck_presets.db.tmp"], nil, "Stale temp must be removed")
    assertEq(stored["deck_presets.db.bak"], nil, "Stale backup must be removed")
end

-- If final rename never happened, a complete temp is newer than the backup.
do
    local state, stored = loadGameWithPresetFiles({
        ["deck_presets.db.tmp"] = "TMP",
        ["deck_presets.db.bak"] = "BAK",
    }, {
        TMP = validPreset,
        BAK = function()
            local p = validPreset()
            p[1][1] = nil
            return p
        end,
    })

    assertTrue(cards.isValidDeck(state.deckPresets[1][1]), "Valid temp preset must recover")
    assertEq(stored["deck_presets.db"], "TMP", "Temp must be promoted before backup")
    assertEq(stored["deck_presets.db.tmp"], nil, "Promoted temp must be removed")
    assertEq(stored["deck_presets.db.bak"], nil, "Older backup must be removed")
end

-- A syntactically valid table is not enough: missing player structure must not
-- suppress a valid backup.
do
    local state, stored = loadGameWithPresetFiles({
        ["deck_presets.db"] = "BROKEN_FINAL",
        ["deck_presets.db.bak"] = "BAK",
    }, {
        BROKEN_FINAL = function() return {} end,
        BAK = validPreset,
    })

    assertTrue(cards.isValidDeck(state.deckPresets[1][1]), "Backup must beat structural corruption")
    assertEq(stored["deck_presets.db"], "BAK", "Valid backup must replace broken final")
end

-- Likewise, a non-nil invalid deck slot invalidates that recovery candidate.
do
    local state, stored = loadGameWithPresetFiles({
        ["deck_presets.db"] = "BAD_SLOT",
        ["deck_presets.db.bak"] = "BAK",
    }, {
        BAD_SLOT = function()
            return {
                [1] = { [1] = { "zombie" } },
                [2] = {},
            }
        end,
        BAK = validPreset,
    })

    assertTrue(cards.isValidDeck(state.deckPresets[1][1]), "Backup must beat invalid deck slot")
    assertEq(stored["deck_presets.db"], "BAK", "Invalid-slot final must be replaced")
end

-- Preset persistence must never recursively delete a directory occupying one
-- of its transaction-file paths.
do
    local oldFs = fs
    local oldTextutils = textutils
    local oldPresets = package.loaded["src.presets"]
    local deleted = {}

    fs = {
        exists = function(path)
            return path == "deck_presets.db.bak"
        end,
        isDir = function(path)
            return path == "deck_presets.db.bak"
        end,
        delete = function(path)
            deleted[#deleted + 1] = path
        end,
        open = function()
            error("Preset save must fail before opening when backup path is a directory")
        end,
        move = function()
            error("Preset save must fail before moving when backup path is a directory")
        end,
    }
    textutils = {
        serialize = function() return "SERIALIZED" end,
    }

    package.loaded["src.presets"] = nil
    local Presets = require("src.presets")
    local ok = Presets.save(validPreset())
    assertEq(ok, false, "Directory transaction path must make preset save fail closed")
    assertEq(#deleted, 0, "Preset directory path must never call recursive fs.delete")

    package.loaded["src.presets"] = oldPresets
    fs = oldFs
    textutils = oldTextutils
end

-- An interrupted install which fails again must keep the recovery marker even
-- if rollback succeeds. This simulates a mixed pre-existing installation and a
-- one-time write failure during the second Apply.
do
    local oldFs = fs
    local oldHttp = http
    local oldTextutils = textutils
    local oldWrite = write

    local stored = {
        [".cc_royale_installing"] = "previous-interrupted-sha",
        [".cc_royale_managed"] = "config.lua\n",
        ["config.lua"] = "OLD_MIXED_CONFIG",
        ["startup.lua"] = 'shell.run("main.lua")',
    }
    local failConfigWriteOnce = true

    local function response(body, code)
        return {
            getResponseCode = function() return code or 200 end,
            readAll = function() return body end,
            close = function() end,
        }
    end

    fs = {
        exists = function(path) return stored[path] ~= nil end,
        isDir = function() return false end,
        getDir = function(path)
            return path:match("^(.*)/[^/]+$") or ""
        end,
        makeDir = function() end,
        delete = function(path) stored[path] = nil end,
        open = function(path, mode)
            if mode == "r" and stored[path] ~= nil then
                return {
                    readAll = function() return stored[path] end,
                    close = function() end,
                }
            end
            if mode == "w" then
                if path == "config.lua" and failConfigWriteOnce then
                    failConfigWriteOnce = false
                    return nil
                end
                local buffer = ""
                return {
                    write = function(value) buffer = buffer .. tostring(value) end,
                    close = function() stored[path] = buffer end,
                }
            end
            return nil
        end,
    }

    http = {
        get = function(url)
            if tostring(url):find("/commits/main", 1, true) then
                return response('{"sha":"abcdef1234567890"}')
            end
            return response("return {}\n")
        end,
    }
    textutils = {
        unserializeJSON = function()
            return { sha = "abcdef1234567890" }
        end,
    }
    write = function() end

    local ok, err = pcall(dofile, "install.lua")
    assertTrue(not ok, "Injected second installer Apply must fail")
    assertTrue(
        tostring(err):find("Recovery marker retained", 1, true) ~= nil,
        "Failed recovery must explicitly report retained marker"
    )
    assertTrue(
        stored[".cc_royale_installing"] ~= nil,
        "Failed recovery must retain install marker"
    )
    assertEq(
        stored["config.lua"],
        "OLD_MIXED_CONFIG",
        "Successful rollback must restore the pre-recovery snapshot"
    )

    fs = oldFs
    http = oldHttp
    textutils = oldTextutils
    write = oldWrite
end

do
    -- A corrupted managed manifest must never make the installer recursively
    -- delete a directory during stale cleanup or rollback.
    local installer = assert(io.open("install.lua", "r")):read("*a")
    assertTrue(
        installer:find("safeDeleteManagedFile(path)", 1, true) ~= nil,
        "Installer must route managed-file deletes through directory-safe helper"
    )
    assertTrue(
        installer:find("Refusing to delete managed directory", 1, true) ~= nil,
        "Managed directory deletion must fail closed"
    )

    local restoreStart = assert(
        installer:find("local function restoreSnapshot", 1, true),
        "restoreSnapshot must exist"
    )
    local restoreEnd = assert(
        installer:find("local function preflightLua", restoreStart, true),
        "restoreSnapshot boundary must exist"
    )
    local restoreBody = installer:sub(restoreStart, restoreEnd - 1)
    assertTrue(
        restoreBody:find("safeDeleteManagedFile(path)", 1, true) ~= nil,
        "Rollback must not recursively delete managed directory entries"
    )
end

print("Recovery hardening tests passed")

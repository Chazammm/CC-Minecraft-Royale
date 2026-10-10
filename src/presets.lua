local util = require("src.util")
local cards = require("src.cards")

local presets = {}

local PRESET_FILE = "deck_presets.db"
local PRESET_TEMP_FILE = PRESET_FILE .. ".tmp"
local PRESET_BACKUP_FILE = PRESET_FILE .. ".bak"

function presets.empty()
    return {
        [1] = { nil, nil, nil },
        [2] = { nil, nil, nil },
    }
end

local function pathExists(path)
    if not fs or not fs.exists then return false end
    local ok, exists = pcall(fs.exists, path)
    return ok and exists == true
end

local function safeDelete(path)
    if not pathExists(path) then return true end
    if fs.isDir then
        local okDir, isDir = pcall(fs.isDir, path)
        if not okDir or isDir then return false end
    end
    local ok, result = pcall(fs.delete, path)
    return ok and result ~= false
end

-- CraftOS native fs.move returns nil on success; custom/peripheral wrappers
-- may explicitly return false on failure instead of raising an exception.
-- pcall alone only proves that the operation did not throw.
local function safeMove(from, to)
    local ok, result = pcall(fs.move, from, to)
    return ok and result ~= false
end

local function readBody(path)
    if not pathExists(path) then return nil end

    if fs.isDir then
        local okDir, isDir = pcall(fs.isDir, path)
        if not okDir or isDir then return nil end
    end

    local okOpen, handle = pcall(fs.open, path, "r")
    if not okOpen or not handle then return nil end

    local okRead, raw = pcall(handle.readAll)
    pcall(handle.close)
    if not okRead then return nil end
    return raw
end

local function decode(raw)
    if type(raw) ~= "string"
        or not textutils
        or not textutils.unserialize
    then
        return nil
    end

    local ok, decoded = pcall(textutils.unserialize, raw)
    if not ok or type(decoded) ~= "table" then return nil end
    if type(decoded[1]) ~= "table" or type(decoded[2]) ~= "table" then
        return nil
    end

    local out = presets.empty()
    for playerId = 1, 2 do
        for slot = 1, 3 do
            local deck = decoded[playerId][slot]
            if deck ~= nil then
                if not cards.isValidDeck(deck) then return nil end
                out[playerId][slot] = util.deepcopy(deck)
            end
        end
    end
    return out
end

function presets.load()
    if not fs or not fs.open or not fs.exists then
        return presets.empty()
    end

    local candidates = {
        PRESET_FILE,
        PRESET_TEMP_FILE,
        PRESET_BACKUP_FILE,
    }

    for index, path in ipairs(candidates) do
        local loaded = decode(readBody(path))
        if loaded then
            if index > 1 and fs.move and fs.delete then
                -- Recover a fully serialized transaction left behind by a
                -- reboot/power loss between old->backup and temp->final.
                -- If invalid/partial final cannot be removed, do not
                -- destroy any other complete recovery candidate.
                local cleared = safeDelete(PRESET_FILE)
                local promoted = cleared and safeMove(path, PRESET_FILE)
                if promoted then
                    safeDelete(PRESET_BACKUP_FILE)
                    safeDelete(PRESET_TEMP_FILE)
                end
            elseif index == 1 then
                -- A valid final file wins; stale transaction debris can be
                -- discarded without risking the recovered presets.
                safeDelete(PRESET_BACKUP_FILE)
                safeDelete(PRESET_TEMP_FILE)
            end
            return loaded
        end
    end

    return presets.empty()
end

function presets.save(value)
    if not fs or not fs.open or not textutils or not textutils.serialize then
        return nil
    end

    -- A partially available filesystem API is a real persistence failure, not
    -- the plain-Lua/no-filesystem case where presets remain memory-only.
    if not fs.exists or not fs.delete or not fs.move then
        return false
    end

    -- The .bak may be the only complete copy after an interrupted
    -- previous save. Keep it until load() can recover it, rather than
    -- deleting it at the beginning of a new transaction.
    if not pathExists(PRESET_FILE) and pathExists(PRESET_BACKUP_FILE) then
        return false
    end

    if not safeDelete(PRESET_TEMP_FILE)
        or not safeDelete(PRESET_BACKUP_FILE)
    then
        return false
    end

    local okOpen, handle = pcall(fs.open, PRESET_TEMP_FILE, "w")
    if not okOpen or not handle then return false end

    local ok, serialized = pcall(textutils.serialize, value)
    local writeResult = nil
    if ok then
        ok, writeResult = pcall(handle.write, serialized)
        ok = ok and writeResult ~= false
    end
    local closed, closeResult = pcall(handle.close)

    if not ok or not closed or closeResult == false then
        safeDelete(PRESET_TEMP_FILE)
        return false
    end

    if pathExists(PRESET_FILE) then
        local movedOld = safeMove(PRESET_FILE, PRESET_BACKUP_FILE)
        if not movedOld then
            safeDelete(PRESET_TEMP_FILE)
            return false
        end
    end

    local movedNew = safeMove(PRESET_TEMP_FILE, PRESET_FILE)
    if not movedNew then
        safeDelete(PRESET_FILE)
        if pathExists(PRESET_BACKUP_FILE) then
            safeMove(PRESET_BACKUP_FILE, PRESET_FILE)
        end
        safeDelete(PRESET_TEMP_FILE)
        return false
    end

    safeDelete(PRESET_BACKUP_FILE)
    return true
end

return presets

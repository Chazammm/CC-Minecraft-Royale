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
    local closed, closeResult = pcall(handle.close)
    -- False or non-string read results are I/O failures, NOT evidence that
    -- the existing data is corrupt and can safely be overwritten.
    if not okRead or type(raw) ~= "string"
        or not closed or closeResult == false
    then
        return nil
    end
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

-- An unreadable transaction artifact could still contain a valid saved
-- deck. Only clean recovery debris after confirming that it is readable.
local function safeDeleteReadable(path)
    if pathExists(path) and readBody(path) == nil then
        return false
    end
    return safeDelete(path)
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
        local originalBody = readBody(path)
        local loaded = decode(originalBody)
        if loaded then
            if index > 1 and fs.move and fs.delete then
                -- Recover a fully serialized transaction left behind by a
                -- reboot/power loss between old->backup and temp->final.
                -- If invalid/partial final cannot be removed, do not
                -- destroy any other complete recovery candidate.
                -- Do not classify a transiently unreadable active file
                -- as corrupt. Return the readable recovery candidate in
                -- memory but leave BOTH files untouched for a later retry.
                local finalReadable = not pathExists(PRESET_FILE)
                    or readBody(PRESET_FILE) ~= nil
                local cleared = finalReadable
                    and safeDelete(PRESET_FILE)
                local promoted = cleared and safeMove(path, PRESET_FILE)
                -- Some storage wrappers return success without actually
                -- renaming; never delete the recovery backup in that case.
                if promoted and readBody(PRESET_FILE) == originalBody
                    and not pathExists(path)
                then
                    safeDeleteReadable(PRESET_BACKUP_FILE)
                    safeDeleteReadable(PRESET_TEMP_FILE)
                end
            elseif index == 1 then
                -- A valid final file wins; stale transaction debris can be
                -- discarded without risking the recovered presets.
                safeDeleteReadable(PRESET_BACKUP_FILE)
                safeDeleteReadable(PRESET_TEMP_FILE)
            end
            return loaded
        end
    end

    return presets.empty()
end

-- Return true for a valid recoverable preset OR a copy whose contents
-- cannot be read safely. Never discard potentially important unreadable
-- transaction files automatically. Invalid but readable files can be
-- replaced by a fresh valid save if there is no other recovery candidate.
local function needsRecovery(path)
    if not pathExists(path) then return false end
    local raw = readBody(path)
    if raw == nil then return true end
    return decode(raw) ~= nil
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

    -- On an interrupted previous save, the newest valid copy might be
    -- the .tmp or .bak. Block overwriting those recoverable files while the
    -- main file is absent/corrupt: load() must restore them first. However,
    -- an explicitly invalid, readable orphan backup must NOT permanently
    -- lock users out of saving fresh valid decks.
    local finalBody = readBody(PRESET_FILE)
    -- Never reinterpret a *read failure* of an existing final as a
    -- definitely invalid file. It may be the only intact deck data.
    if pathExists(PRESET_FILE) and finalBody == nil then
        return false
    end
    if not decode(finalBody)
        and (needsRecovery(PRESET_TEMP_FILE)
            or needsRecovery(PRESET_BACKUP_FILE))
    then
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
    ok = ok and type(serialized) == "string"
    local writeResult = nil
    if ok then
        ok, writeResult = pcall(handle.write, serialized)
        ok = ok and writeResult ~= false
    end
    local closed, closeResult = pcall(handle.close)

    if not ok or not closed or closeResult == false
        or readBody(PRESET_TEMP_FILE) ~= serialized
    then
        -- Write/close can succeed yet leave a truncated or empty file.
        -- Detect that before touching the user's existing saved decks.
        safeDelete(PRESET_TEMP_FILE)
        return false
    end

    if pathExists(PRESET_FILE) then
        local movedOld = safeMove(PRESET_FILE, PRESET_BACKUP_FILE)
        if not movedOld
            or pathExists(PRESET_FILE)
            or readBody(PRESET_BACKUP_FILE) ~= finalBody
        then
            -- No-op/partial old->backup move: do not attempt promotion.
            -- Keep any resulting good backup if the original disappeared.
            safeDelete(PRESET_TEMP_FILE)
            return false
        end
    end

    local movedNew = safeMove(PRESET_TEMP_FILE, PRESET_FILE)
    local finalSavedBody = readBody(PRESET_FILE)
    if not movedNew or finalSavedBody ~= serialized
        or pathExists(PRESET_TEMP_FILE)
    then
        -- An unreadable destination may still hold good data: never
        -- destroy it blindly. Preserve .bak as a recovery candidate.
        if not pathExists(PRESET_FILE) or finalSavedBody ~= nil then
            safeDelete(PRESET_FILE)
        end
        if not pathExists(PRESET_FILE)
            and pathExists(PRESET_BACKUP_FILE)
        then
            safeMove(PRESET_BACKUP_FILE, PRESET_FILE)
        end
        -- No deletion of a still-needed .bak if rollback did not succeed.
        safeDelete(PRESET_TEMP_FILE)
        return false
    end

    safeDelete(PRESET_BACKUP_FILE)
    return true
end

return presets

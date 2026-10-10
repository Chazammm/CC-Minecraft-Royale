-- Atomic benchmark report output. Previous complete reports survive crashes,
-- aborted runs, disk errors and interrupted final rename operations.
local reportOutput = {}

local function exists(path)
    return fs.exists(path)
end

local function isFile(path)
    return exists(path) and (not fs.isDir or not fs.isDir(path))
end

local function removeFile(path)
    if not exists(path) then return true end
    if not isFile(path) then return false, "Refusing to delete directory: " .. path end
    local ok, result = pcall(fs.delete, path)
    if not ok or result == false then
        return false, "Could not remove " .. path
    end
    return true
end

local function moveFile(from, to)
    local ok, result = pcall(fs.move, from, to)
    if not ok or result == false then
        return false, "Could not move " .. from .. " to " .. to
    end
    return true
end

local function readExact(path)
    if not isFile(path) then return nil end
    local okOpen, reader = pcall(fs.open, path, "r")
    if not okOpen or not reader then return nil end
    local okRead, body = pcall(reader.readAll)
    local okClose, closeResult = pcall(reader.close)
    if not okRead or type(body) ~= "string"
        or not okClose or closeResult == false
    then return nil end
    return body
end

local function paths(path)
    return path .. ".tmp", path .. ".bak"
end

function reportOutput.start(path)
    if not fs or not fs.open or not fs.exists
        or not fs.delete or not fs.move
    then
        return nil, "Report filesystem is unavailable"
    end

    local temporary, backup = paths(path)
    if exists(path) and not isFile(path) then
        return nil, "Report destination is a directory"
    end

    -- Previous power loss after old->backup: restore the completed old report.
    if exists(backup) and not exists(path) then
        if not isFile(backup) then return nil, "Report backup is a directory" end
        local restored, err = moveFile(backup, path)
        if not restored then return nil, err end
    end

    -- If the destination exists, a lingering backup is no longer needed.
    local ok, err = removeFile(backup)
    if not ok then return nil, err end
    ok, err = removeFile(temporary)
    if not ok then return nil, err end

    local opened, handle = pcall(fs.open, temporary, "w")
    if not opened or not handle then
        return nil, "Could not open temporary report " .. temporary
    end
    -- Capture the exact bytes intended for publication (reports are small).
    -- fs.write/close can report success even if a wrapper/disk silently drops
    -- bytes; the commit must compare actual staged bytes before renaming.
    local chunks = {}
    return {
        _expectedChunks = chunks,
        write = function(value)
            local ok, result = pcall(handle.write, value)
            if not ok or result == false then
                error("Could not write temporary report " .. temporary, 0)
            end
            chunks[#chunks + 1] = tostring(value)
            return result
        end,
        close = function()
            return handle.close()
        end,
    }
end

function reportOutput.commit(path, handle)
    if not handle then return false, "No report handle" end
    local temporary, backup = paths(path)
    local closed, closeResult = pcall(handle.close)
    if not closed or closeResult == false then
        return false, "Could not close temporary report " .. temporary
    end

    if not isFile(temporary) then
        return false, "Temporary report is missing"
    end

    local expected = handle._expectedChunks
        and table.concat(handle._expectedChunks)
    if expected == nil or readExact(temporary) ~= expected then
        return false, "Temporary report contents are truncated or unreadable"
    end

    local hadOriginal = exists(path)
    if hadOriginal and not isFile(path) then
        return false, "Report destination is a directory"
    end

    local previousContents = hadOriginal and readExact(path) or nil
    if hadOriginal and previousContents == nil then
        return false, "Existing complete report is unreadable"
    end
    if hadOriginal then
        local backedUp, backupErr = moveFile(path, backup)
        if not backedUp or exists(path)
            or readExact(backup) ~= previousContents
        then
            return false, backupErr or "Report backup was not verified"
        end
    end

    local promoted, promoteErr = moveFile(temporary, path)
    local publishedContents = readExact(path)
    if not promoted or publishedContents ~= expected or exists(temporary) then
        -- Never delete an unreadable destination (it might be intact).
        if not exists(path) or publishedContents ~= nil then
            removeFile(path)
        end
        if hadOriginal and not exists(path) then
            local restored, restoreErr = moveFile(backup, path)
            if not restored or readExact(path) ~= previousContents then
                return false, (promoteErr or "Report promotion failed")
                    .. "; rollback failed: "
                    .. tostring(restoreErr or "mismatched old report")
            end
        end
        return false, promoteErr or "Report publication was not verified"
    end

    -- Only delete the old complete report once the new report was read back
    -- exactly. A failed cleanup is noncritical because the new report exists.
    removeFile(backup)
    return true
end

return reportOutput

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
    return handle
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

    local hadOriginal = exists(path)
    if hadOriginal and not isFile(path) then
        return false, "Report destination is a directory"
    end

    if hadOriginal then
        local backedUp, backupErr = moveFile(path, backup)
        if not backedUp then return false, backupErr end
    end

    local promoted, promoteErr = moveFile(temporary, path)
    if not promoted then
        if hadOriginal then
            local restored, restoreErr = moveFile(backup, path)
            if not restored then
                return false, promoteErr .. "; rollback failed: " .. restoreErr
            end
        end
        return false, promoteErr
    end

    -- A leftover backup is harmless and recovered on the next run if removal
    -- fails. Only publish a report after the replacement is safely in place.
    removeFile(backup)
    return true
end

return reportOutput

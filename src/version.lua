local version = {}

local VERSION_FILE = ".cc_royale_version"

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

function version.path()
    return VERSION_FILE
end

function version.read()
    if not fs or not fs.exists or not fs.open then
        return "unknown"
    end

    local okExists, exists = pcall(fs.exists, VERSION_FILE)
    if not okExists or not exists then return "unknown" end

    if fs.isDir then
        local okDir, isDir = pcall(fs.isDir, VERSION_FILE)
        if not okDir or isDir then return "unknown" end
    end

    local okOpen, handle = pcall(fs.open, VERSION_FILE, "r")
    if not okOpen or not handle then return "unknown" end
    local okRead, body = pcall(handle.readAll)
    pcall(handle.close)
    if not okRead then return "unknown" end

    local value = trim(body)
    if value == "" then return "unknown" end
    return value
end

return version

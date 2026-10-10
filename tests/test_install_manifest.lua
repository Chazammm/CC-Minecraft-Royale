-- Ensure the low-space installer actually ships every Lua module required by
-- the installed runtime/benchmark entry points.

local function read(path)
    local handle = assert(io.open(path, "r"), "Missing file: " .. path)
    local body = handle:read("*a")
    handle:close()
    return body
end

local installer = read("install.lua")
local listBody = installer:match("local files%s*=%s*{(.-)\n}")
assert(listBody, "Could not parse installer file list")

assert(
    installer:find("resolveCommitSha", 1, true) ~= nil
        and installer:find("targetSha", 1, true) ~= nil,
    "Installer must pin one repository commit before downloading files"
)
assert(
    installer:find("INSTALL_MARKER", 1, true) ~= nil
        and installer:find(".cc_royale_installing", 1, true) ~= nil,
    "Installer must keep an interrupted-update recovery marker"
)
assert(
    installer:find('REPO,\n  targetSha', 1, true) ~= nil,
    "Installer raw-file base must use the resolved commit SHA"
)
assert(
    installer:find("preflightLua", 1, true) ~= nil,
    "Installer must syntax-check downloaded Lua before applying it"
)
assert(
    installer:find("MANAGED_FILE", 1, true) ~= nil
        and installer:find(".cc_royale_managed", 1, true) ~= nil,
    "Installer must track managed files so removed runtime files can be cleaned"
)
assert(
    installer:find("restoreSnapshot(snapshot, rollbackPaths)", 1, true) ~= nil,
    "Installer must rollback the complete touched-file set after apply errors"
)

local managed = {}
for path in listBody:gmatch('"([^"]+)"') do
    managed[path] = true
    local handle = io.open(path, "r")
    assert(handle, "Installer references missing file: " .. path)
    handle:close()
end

local entrypoints = {
    "main.lua",
    "admin.lua",
    "startup.lua",
    "diagnose.lua",
    "simulate.lua",
    "compare.lua",
    "evo_compare.lua",
    "mechanics_test.lua",
    "report_sync.lua",
}

local visited = {}

local function modulePath(name)
    return (name:gsub("%.", "/")) .. ".lua"
end

local function scan(path)
    if visited[path] then return end
    visited[path] = true

    local body = read(path)
    for quote, moduleName in body:gmatch([=[require%s*%(%s*(["'])(.-)%1%s*%)]=]) do
        local requiredPath = modulePath(moduleName)
        local handle = io.open(requiredPath, "r")
        if handle then
            handle:close()
            assert(
                managed[requiredPath],
                path .. " requires " .. requiredPath
                    .. " but install.lua does not ship it"
            )
            scan(requiredPath)
        end
    end
end

for _, path in ipairs(entrypoints) do
    assert(managed[path], "Installer is missing runtime entry point: " .. path)
    scan(path)
end

assert(
    managed["src/version.lua"],
    "Installed revision helper must be shipped"
)
assert(
    installer:find(".cc_royale_version", 1, true) ~= nil,
    "Installer must persist the pinned commit revision"
)
assert(
    managed["src/spatial.lua"],
    "Spatial index module must be installed"
)
assert(
    managed["src/ui_buffer.lua"],
    "Shared UI buffer module must be installed"
)
assert(
    managed["src/presets.lua"],
    "Preset persistence module must be installed"
)
assert(
    managed["src/headless_match.lua"],
    "Shared headless runner must be installed"
)
assert(
    managed["src/benchmark_utils.lua"],
    "Shared benchmark utilities must be installed"
)

print("Installer manifest tests passed")

local ReportSync = require("src.report_sync")

local args = { ... }
local command = string.lower(tostring(args[1] or "sync"))

local function usage()
    print("Usage:")
    print("  report_sync setup       Store/verify GitHub token locally")
    print("  report_sync             Upload all existing reports")
    print("  report_sync sync        Same as above")
    print("  report_sync status      Show configuration/report status")
    print("  report_sync logout      Remove the local token")
end

if command == "help" or command == "--help" or command == "-h" then
    usage()
    return
end

if command == "setup" then
    local ok, message = ReportSync.setupInteractive()
    if ok then
        print("")
        print("OK: " .. tostring(message))
        print("Run: report_sync")
    else
        print("")
        print("FAILED: " .. tostring(message))
    end
    return
end

if command == "logout" or command == "clear" or command == "remove-token" then
    local ok, err = ReportSync.clearToken()
    if ok then
        print("Local GitHub token removed.")
    else
        print("FAILED: " .. tostring(err))
    end
    return
end

if command == "status" then
    print("CC-Minecraft Royale report sync")
    print("--------------------------------")
    print("Token configured: " .. tostring(ReportSync.isConfigured()))
    print("Token file: " .. ReportSync.tokenPath())
    print("")
    for _, report in ipairs(ReportSync.reportDefinitions()) do
        local present = fs.exists(report.path) and not fs.isDir(report.path)
        print(("%-12s %-24s %s"):format(
            report.kind,
            report.path,
            present and "READY" or "MISSING"
        ))
    end
    return
end

if command ~= "sync" then
    print("Unknown command: " .. command)
    usage()
    return
end

if not ReportSync.isConfigured() then
    print("Report sync is not configured.")
    print("Run once: report_sync setup")
    return
end

print("Uploading reports to GitHub...")
local ok, result = ReportSync.syncAll()

if type(result) ~= "table" then
    print((ok and "OK: " or "FAILED: ") .. tostring(result))
    return
end

for _, uploaded in ipairs(result.uploaded or {}) do
    print(("OK %-11s -> %s"):format(uploaded.kind, uploaded.latestPath))
    print(("   archived -> %s"):format(uploaded.historyPath))
end

for _, skipped in ipairs(result.skipped or {}) do
    print(("UNCHANGED %-8s -> %s"):format(skipped.kind, skipped.latestPath))
end

for _, failure in ipairs(result.failures or {}) do
    print("FAILED " .. tostring(failure))
end

if ok then
    print("")
    print("All available reports synced.")
else
    print("")
    print("Sync finished with one or more failures.")
end

local OWNER = "Chazammm"
local REPO = "CC-Minecraft-Royale"
local BRANCH = "main"

local files = {
  -- Install the recovery-aware startup entry first: even an interruption
  -- before main/admin were updated will stop normal reboot into mixed files.
  "startup.lua",
  "main.lua",
  "admin.lua",
  "config.lua",
  "src/util.lua",
  "src/version.lua",
  "src/cards.lua",
  "lib/pixelbox_lite.lua",
  "src/pixel_arena.lua",
  "src/arena.lua",
  "src/spatial.lua",
  "src/presets.lua",
  "src/hardware.lua",
  "src/game.lua",
  "src/bot.lua",
  "src/benchmark_utils.lua",
  "src/report_output.lua",
  "src/headless_match.lua",
  "src/music.lua",
  "src/music_manifest.lua",
  "src/ui_buffer.lua",
  "src/render.lua",
  "src/admin_render.lua",
  "src/report_sync.lua",
  "diagnose.lua",
  "simulate.lua",
  "compare.lua",
  "evo_compare.lua",
  "mechanics_test.lua",
  "report_sync.lua",
}

-- Older installers staged a complete second copy on disk. Clean up leftovers
-- before doing anything else so a previous "Out of space" failure immediately
-- gives its temporary storage back.
local LEGACY_STAGE_DIR = ".cc_royale_update"
local LEGACY_BACKUP_DIR = ".cc_royale_backup"
local INSTALL_MARKER = ".cc_royale_installing"
local MANAGED_FILE = ".cc_royale_managed"
local VERSION_FILE = ".cc_royale_version"
-- Only explicitly retired project-owned paths may ever be deleted as stale.
-- Manifest entries are not authoritative ownership: a corrupt/edited manifest
-- must never permit deletion of player saves, credentials or arbitrary files.
-- When removing a shipped file in a future release, add its exact old path here.
local RETIRED_MANAGED_FILES = {}

local HTTP_TIMEOUT = 15
local STARTUP_MARKER = "-- CC-MINECRAFT-ROYALE-MANAGED-STARTUP"

local function safeExists(path)
  local ok, exists = pcall(fs.exists, path)
  return ok and exists == true
end

local function safeDelete(path)
  if not safeExists(path) then return true end
  local ok = pcall(fs.delete, path)
  return ok
end

local function safeIsDir(path)
  if not fs.isDir then return false end
  local ok, isDir = pcall(fs.isDir, path)
  return ok and isDir == true
end

local function safeDeleteManagedFile(path)
  if not safeExists(path) then return true end
  if safeIsDir(path) then
    return false, "Refusing to delete managed directory: " .. tostring(path)
  end
  return safeDelete(path)
end

local function ensureDir(path)
  local dir = fs.getDir(path)
  if dir ~= "" and not safeExists(dir) then
    local ok, err = pcall(fs.makeDir, dir)
    if not ok then return false, err end
  end
  return true
end

local function readFile(path)
  if not safeExists(path) then return nil end

  if fs.isDir then
    local okDir, isDir = pcall(fs.isDir, path)
    if not okDir or isDir then return nil end
  end

  local okOpen, handle = pcall(fs.open, path, "r")
  if not okOpen or not handle then return nil end
  local okRead, body = pcall(handle.readAll)
  pcall(handle.close)
  if not okRead then return nil end
  return body
end

local function writeFile(path, body)
  local dirOk, dirErr = ensureDir(path)
  if not dirOk then return false, dirErr end

  local okOpen, handle = pcall(fs.open, path, "w")
  if not okOpen or not handle then
    return false, "Could not open " .. path .. " for writing"
  end

  local ok, err = pcall(handle.write, body)
  pcall(handle.close)

  if not ok then
    return false, err
  end

  return true
end

local function isSafeManagedPath(path)
  if type(path) ~= "string" or path == "" then return false end
  if path:sub(1, 1) == "/" or path:find("\\", 1, true) then return false end
  if path:find(":", 1, true) then return false end
  for part in path:gmatch("[^/]+") do
    if part == "." or part == ".." then return false end
    if not part:match("^[%w%._%-]+$") then return false end
  end
  return true
end

local function safeStalePath(path, currentManagedSet)
  return isSafeManagedPath(path)
    and RETIRED_MANAGED_FILES[path] == true
    and not currentManagedSet[path]
end

local function readManagedFiles()
  local out = {}
  local raw = readFile(MANAGED_FILE)
  if not raw then
    if safeExists(MANAGED_FILE) then
      error("Cannot read existing managed-file manifest; refusing unsafe update", 0)
    end
    return out
  end

  for path in raw:gmatch("[^\r\n]+") do
    if isSafeManagedPath(path) then
      out[#out + 1] = path
    elseif path ~= "" then
      print("Ignoring unsafe managed-file entry: " .. tostring(path))
    end
  end
  return out
end

local function managedBody(paths)
  return table.concat(paths, "\n") .. (#paths > 0 and "\n" or "")
end

local existingStartup = readFile("startup.lua")
local legacyManagedStartup = table.concat({
  "-- Optional startup entry point for a dedicated arena computer.",
  "-- Remove/rename this file if you do not want the game to auto-start on reboot.",
  'shell.run("main.lua")',
}, "\n")
local managedStartup = existingStartup ~= nil
  and (
    existingStartup:find(STARTUP_MARKER, 1, true)
    or existingStartup == legacyManagedStartup
    or existingStartup == legacyManagedStartup .. "\n"
  )
local preserveCustomStartup = existingStartup ~= nil and not managedStartup

local function shouldApply(path)
  return path ~= "startup.lua" or not preserveCustomStartup
end

local function resolveCommitSha()
  local url = ("https://api.github.com/repos/%s/%s/commits/%s"):format(
    OWNER,
    REPO,
    BRANCH
  )

  local response, err, failedResponse = http.get({
    url = url,
    headers = {
      ["Accept"] = "application/vnd.github+json",
      ["User-Agent"] = "CC-Minecraft-Royale",
    },
    timeout = HTTP_TIMEOUT,
  })
  if not response then
    if failedResponse and failedResponse.close then
      pcall(failedResponse.close)
    end
    return nil, "Could not resolve repository HEAD: " .. tostring(err)
  end

  if response.getResponseCode and response.getResponseCode() ~= 200 then
    local code = response.getResponseCode()
    response.close()
    return nil, "GitHub commit lookup returned HTTP " .. tostring(code)
  end

  local body = response.readAll()
  response.close()

  if not textutils or not textutils.unserializeJSON then
    return nil, "JSON support is unavailable; cannot pin installer commit."
  end

  local ok, decoded = pcall(textutils.unserializeJSON, body)
  local sha = ok and type(decoded) == "table" and decoded.sha or nil
  if type(sha) ~= "string" or #sha < 7 then
    return nil, "GitHub commit lookup returned no usable SHA."
  end

  return sha
end

local function downloadBody(base, path)
  local url = base .. path
  write(("Downloading %-24s ... "):format(path))

  local response, err, failedResponse = http.get({
    url = url,
    timeout = HTTP_TIMEOUT,
  })
  if not response then
    if failedResponse and failedResponse.close then
      pcall(failedResponse.close)
    end
    print("FAILED")
    return nil, (
      "Could not download %s\n%s\n"
      .. "If the GitHub repo is private, raw.githubusercontent.com "
      .. "will reject the request."
    ):format(url, tostring(err))
  end

  if response.getResponseCode then
    local code = response.getResponseCode()
    if code ~= 200 then
      response.close()
      print("FAILED")
      return nil, ("GitHub returned HTTP %s while downloading %s")
        :format(tostring(code), path)
    end
  end

  local body = response.readAll()
  response.close()
  print("OK")
  return body
end

local function restoreSnapshot(snapshot, rollbackPaths)
  -- Delete updated files first. This guarantees that the old installation,
  -- which demonstrably fit before the update, has enough disk space to return.
  for _, path in ipairs(rollbackPaths) do
    local deleted, deleteErr = safeDeleteManagedFile(path)
    if not deleted then
      return false, "Could not clear " .. path .. " during rollback: "
        .. tostring(deleteErr or "delete failed")
    end
  end

  for _, path in ipairs(rollbackPaths) do
    local oldBody = snapshot[path]
    if oldBody ~= false then
      local ok, err = writeFile(path, oldBody)
      if not ok then
        return false, ("Could not restore %s: %s")
          :format(path, tostring(err))
      end
    end
  end

  return true
end

local function preflightLua(path, body)
  if path:sub(-4) ~= ".lua" then return true end

  local chunk, err
  if load then
    chunk, err = load(body, "@" .. path, "t", {})
  elseif loadstring then
    chunk, err = loadstring(body, "@" .. path)
  else
    return false, "Lua compiler is unavailable for syntax preflight"
  end

  if not chunk then
    return false, ("Syntax error in %s: %s"):format(path, tostring(err))
  end
  return true
end

print("CC-Minecraft Royale installer")
print("--------------------------------")

if not http then
  error("HTTP API is disabled on this server/client.", 0)
end

-- Reclaim any disk space left behind by the old full-disk staging installer.
if not safeDelete(LEGACY_STAGE_DIR) then
  error("Could not remove legacy update directory: " .. LEGACY_STAGE_DIR, 0)
end
if not safeDelete(LEGACY_BACKUP_DIR) then
  error("Could not remove legacy backup directory: " .. LEGACY_BACKUP_DIR, 0)
end

local recoveringInterruptedInstall = safeExists(INSTALL_MARKER)
if recoveringInterruptedInstall then
  local interruptedSha = readFile(INSTALL_MARKER) or "unknown"
  print("Interrupted previous update detected (" .. interruptedSha .. ").")
  print("Reinstalling every managed file from one pinned commit.")
end

if preserveCustomStartup then
  print("Custom startup.lua detected - leaving it untouched.")
end

-- Resolve main once, then fetch every file from that immutable commit. A push
-- which happens halfway through an update can therefore never create a mixed
-- installation assembled from two repository versions.
local targetSha, shaErr = resolveCommitSha()
if not targetSha then error(shaErr, 0) end

local base = ("https://raw.githubusercontent.com/%s/%s/%s/"):format(
  OWNER,
  REPO,
  targetSha
)
print("Pinned repository commit: " .. targetSha:sub(1, 12))

-- Download everything into RAM first. No live file changes until every network
-- request has succeeded, and no second copy of the project is written to disk.
local downloaded = {}
for _, path in ipairs(files) do
  if shouldApply(path) then
    local body, err = downloadBody(base, path)
    if not body then error(err, 0) end

    local syntaxOk, syntaxErr = preflightLua(path, body)
    if not syntaxOk then error(syntaxErr, 0) end
    downloaded[path] = body
  end
end

print("")
print("All files downloaded and Lua syntax preflight passed.")
print("Applying low-space atomic update...")

-- Snapshot first, and create the recovery marker only after every previous
-- managed file has been read successfully. A permission/read error must never
-- masquerade as a missing file during rollback.
-- Keep previous managed text files in RAM during the write phase. This provides
-- rollback without storing a second on-disk project copy.
local previousManaged = readManagedFiles()
local currentManagedSet = {}
local appliedFiles = {}
for _, path in ipairs(files) do
  if shouldApply(path) then
    currentManagedSet[path] = true
    appliedFiles[#appliedFiles + 1] = path
  end
end

-- Files removed/renamed by newer releases should not live forever on existing
-- arena computers. Never treat a user-customized startup.lua as stale.
local staleFiles = {}
for _, path in ipairs(previousManaged) do
  if not currentManagedSet[path]
      and not (path == "startup.lua" and preserveCustomStartup)
  then
    if safeStalePath(path, currentManagedSet) then
      staleFiles[#staleFiles + 1] = path
    else
      print("Preserving unrecognized old manifest path: " .. tostring(path))
    end
  end
end

local rollbackPaths = {}
local rollbackSeen = {}
local function addRollbackPath(path)
  if not rollbackSeen[path] then
    rollbackSeen[path] = true
    rollbackPaths[#rollbackPaths + 1] = path
  end
end
for _, path in ipairs(appliedFiles) do addRollbackPath(path) end
for _, path in ipairs(staleFiles) do addRollbackPath(path) end

local snapshot = {}
for _, path in ipairs(rollbackPaths) do
  if safeExists(path) then
    if safeIsDir(path) then
      error("Cannot snapshot managed directory " .. path, 0)
    end
    local oldBody = readFile(path)
    if oldBody == nil then
      error("Cannot snapshot managed file " .. path .. "; refusing update", 0)
    end
    snapshot[path] = oldBody
  else
    snapshot[path] = false
  end
end

local oldManagedBody = readFile(MANAGED_FILE)
if safeExists(MANAGED_FILE) and oldManagedBody == nil then
  error("Cannot snapshot managed-file manifest; refusing update", 0)
end
local oldVersionBody = readFile(VERSION_FILE)
if safeExists(VERSION_FILE) and oldVersionBody == nil then
  error("Cannot snapshot install version; refusing update", 0)
end

-- All rollback inputs are now verified. Only now permit destructive writes.
local markerOk, markerErr = writeFile(INSTALL_MARKER, targetSha)
if not markerOk then
  error("Could not create install recovery marker: " .. tostring(markerErr), 0)
end

local appliedCount = 0
local applyOk, applyErr = pcall(function()
  for _, path in ipairs(appliedFiles) do
    -- Delete just this old file before writing its replacement. Peak disk usage
    -- is therefore approximately the installed project size, not 2x the size.
    local deleted, deleteErr = safeDeleteManagedFile(path)
    if not deleted then
      error(
        "Could not remove old file before update: "
          .. path .. " (" .. tostring(deleteErr or "delete failed") .. ")",
        0
      )
    end

    local ok, err = writeFile(path, downloaded[path])
    if not ok then
      error(("Could not write %s: %s"):format(path, tostring(err)), 0)
    end
    appliedCount = appliedCount + 1
  end

  for _, path in ipairs(staleFiles) do
    local deleted, deleteErr = safeDeleteManagedFile(path)
    if not deleted then
      error(
        "Could not remove obsolete managed file: "
          .. path .. " (" .. tostring(deleteErr or "delete failed") .. ")",
        0
      )
    end
  end

  local manifestOk, manifestErr = writeFile(
    MANAGED_FILE,
    managedBody(appliedFiles)
  )
  if not manifestOk then
    error("Could not update managed-file manifest: " .. tostring(manifestErr), 0)
  end

  local versionDeleted, versionDeleteErr = safeDeleteManagedFile(VERSION_FILE)
  if not versionDeleted then
    error(
      "Could not replace install-version metadata: "
        .. tostring(versionDeleteErr or "delete failed"),
      0
    )
  end
  local versionOk, versionErr = writeFile(VERSION_FILE, targetSha .. "\n")
  if not versionOk then
    error("Could not write install-version metadata: " .. tostring(versionErr), 0)
  end
end)

if not applyOk then
  print("")
  print("APPLY FAILED - restoring previous installation...")

  local restored, restoreErr = restoreSnapshot(snapshot, rollbackPaths)

  local managedRestored = select(1, safeDeleteManagedFile(MANAGED_FILE))
  if managedRestored and oldManagedBody ~= nil then
    managedRestored = select(1, writeFile(MANAGED_FILE, oldManagedBody))
  end

  local versionRestored = select(1, safeDeleteManagedFile(VERSION_FILE))
  if versionRestored and oldVersionBody ~= nil then
    versionRestored = select(1, writeFile(VERSION_FILE, oldVersionBody))
  end

  local metadataRestored = managedRestored and versionRestored

  if not restored or not metadataRestored then
    error(
      "Update failed: " .. tostring(applyErr)
      .. "\nRollback also failed: " .. tostring(restoreErr or "managed metadata")
      .. "\nRecovery marker retained at " .. INSTALL_MARKER,
      0
    )
  end

  if not recoveringInterruptedInstall then
    safeDelete(INSTALL_MARKER)
  end
  error(
    "Update failed and was rolled back: " .. tostring(applyErr)
      .. (recoveringInterruptedInstall
        and ("\nRecovery marker retained at " .. INSTALL_MARKER)
        or ""),
    0
  )
end

if not safeDelete(INSTALL_MARKER) then
  error(
    "Install completed but recovery marker could not be removed: "
      .. INSTALL_MARKER,
    0
  )
end

print("")
print(("Install complete. Updated %d files."):format(appliedCount))
print("Installed commit: " .. targetSha:sub(1, 12))

local mechanicsVersion = "unknown"
if safeExists("mechanics_test.lua") then
  local handle = fs.open("mechanics_test.lua", "r")
  if handle then
    local body = handle.readAll()
    handle.close()
    mechanicsVersion = body:match(
      "local%s+SUITE_VERSION%s*=%s*(%d+)"
    ) or "unknown"
  end
end

print("Installed mechanics suite: FORMAT_VERSION " .. mechanicsVersion)
print("Run: diagnose")
print("Then: main")
print("Admin sandbox: admin")
print("Mechanics diagnostics: mechanics_test")
print("Balance benchmark: simulate <100-1000> [mixed|fixed]")
print("Controlled replacements: compare <10-100> [all|cardA cardB] [seed]")
print("Evolution impact: evo_compare <10-100> [all|card_id] [seed]")
print("GitHub reports: report_sync setup   (one-time)")
print("Battle music: streamed + shuffled from GitHub during matches")

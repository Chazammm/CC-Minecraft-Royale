local OWNER = "Chazammm"
local REPO = "CC-Minecraft-Royale"
local BRANCH = "main"

local files = {
  "config.lua",
  "main.lua",
  "admin.lua",
  "startup.lua",
  "src/util.lua",
  "src/cards.lua",
  "lib/pixelbox_lite.lua",
  "src/pixel_arena.lua",
  "src/arena.lua",
  "src/hardware.lua",
  "src/game.lua",
  "src/bot.lua",
  "src/music.lua",
  "src/music_manifest.lua",
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

local base = ("https://raw.githubusercontent.com/%s/%s/%s/"):format(
  OWNER,
  REPO,
  BRANCH
)

-- Older installers staged a complete second copy on disk. Clean up leftovers
-- before doing anything else so a previous "Out of space" failure immediately
-- gives its temporary storage back.
local LEGACY_STAGE_DIR = ".cc_royale_update"
local LEGACY_BACKUP_DIR = ".cc_royale_backup"

local function ensureDir(path)
  local dir = fs.getDir(path)
  if dir ~= "" and not fs.exists(dir) then
    fs.makeDir(dir)
  end
end

local function readFile(path)
  if not fs.exists(path) or fs.isDir(path) then return nil end
  local handle = fs.open(path, "r")
  if not handle then return nil end
  local body = handle.readAll()
  handle.close()
  return body
end

local function writeFile(path, body)
  ensureDir(path)

  local handle = fs.open(path, "w")
  if not handle then
    return false, "Could not open " .. path .. " for writing"
  end

  local ok, err = pcall(handle.write, body)
  pcall(handle.close)

  if not ok then
    return false, err
  end

  return true
end

local existingStartup = readFile("startup.lua")
local managedStartup = existingStartup ~= nil
  and (
    existingStartup:find('shell.run("main.lua")', 1, true)
    or existingStartup:find("shell.run('main.lua')", 1, true)
  )
local preserveCustomStartup = existingStartup ~= nil and not managedStartup

local function shouldApply(path)
  return path ~= "startup.lua" or not preserveCustomStartup
end

local function downloadBody(path, cacheBust)
  local url = base .. path .. "?v=" .. cacheBust
  write(("Downloading %-24s ... "):format(path))

  local response, err = http.get(url)
  if not response then
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

local function restoreSnapshot(snapshot, appliedFiles)
  -- Delete updated files first. This guarantees that the old installation,
  -- which demonstrably fit before the update, has enough disk space to return.
  for _, path in ipairs(appliedFiles) do
    if fs.exists(path) then
      fs.delete(path)
    end
  end

  for _, path in ipairs(appliedFiles) do
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

print("CC-Minecraft Royale installer")
print("--------------------------------")

if not http then
  error("HTTP API is disabled on this server/client.", 0)
end

-- Reclaim any disk space left behind by the old full-disk staging installer.
if fs.exists(LEGACY_STAGE_DIR) then
  fs.delete(LEGACY_STAGE_DIR)
end
if fs.exists(LEGACY_BACKUP_DIR) then
  fs.delete(LEGACY_BACKUP_DIR)
end

if preserveCustomStartup then
  print("Custom startup.lua detected - leaving it untouched.")
end

-- Download everything into RAM first. No live file changes until every network
-- request has succeeded, and no second copy of the project is written to disk.
local cacheBust
if os.epoch then
  cacheBust = tostring(os.epoch("utc"))
else
  cacheBust = tostring(math.floor(os.clock() * 1000))
end

local downloaded = {}
for _, path in ipairs(files) do
  if shouldApply(path) then
    local body, err = downloadBody(path, cacheBust)
    if not body then error(err, 0) end
    downloaded[path] = body
  end
end

print("")
print("All files downloaded. Applying low-space atomic update...")

-- Keep the previous text files in RAM during the write phase. This provides a
-- full rollback without ever storing an on-disk backup copy.
local snapshot = {}
local appliedFiles = {}
for _, path in ipairs(files) do
  if shouldApply(path) then
    local oldBody = readFile(path)
    snapshot[path] = oldBody ~= nil and oldBody or false
    appliedFiles[#appliedFiles + 1] = path
  end
end

local appliedCount = 0
for _, path in ipairs(appliedFiles) do
  -- Delete just this old file before writing its replacement. Peak disk usage
  -- is therefore approximately the installed project size, not 2x the size.
  if fs.exists(path) then
    fs.delete(path)
  end

  local ok, err = writeFile(path, downloaded[path])
  if not ok then
    print("")
    print(("APPLY FAILED at %s - restoring previous installation...")
      :format(path))

    -- Include the current path in rollback even if the failed write left a
    -- partial file behind.
    local restored, restoreErr = restoreSnapshot(snapshot, appliedFiles)
    if not restored then
      error(
        "Update failed: " .. tostring(err)
        .. "\nRollback also failed: " .. tostring(restoreErr),
        0
      )
    end

    error("Update failed and was rolled back: " .. tostring(err), 0)
  end

  appliedCount = appliedCount + 1
end

print("")
print(("Install complete. Updated %d files."):format(appliedCount))

local mechanicsVersion = "unknown"
if fs.exists("mechanics_test.lua") then
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

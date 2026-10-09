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

local base = ("https://raw.githubusercontent.com/%s/%s/%s/"):format(OWNER, REPO, BRANCH)
local STAGE_DIR = ".cc_royale_update"
local BACKUP_DIR = ".cc_royale_backup"

local function ensureDir(path)
  local dir = fs.getDir(path)
  if dir ~= "" and not fs.exists(dir) then
    fs.makeDir(dir)
  end
end

local function stagedPath(path)
  return fs.combine(STAGE_DIR, path)
end

local function download(path)
  local target = stagedPath(path)
  ensureDir(target)

  -- raw.githubusercontent.com/CDN caches can briefly serve an older file
  -- immediately after a push. A unique query string forces a fresh fetch.
  local cacheBust
  if os.epoch then
    cacheBust = tostring(os.epoch("utc"))
  else
    cacheBust = tostring(math.floor(os.clock() * 1000))
  end

  local url = base .. path .. "?v=" .. cacheBust
  write(("Downloading %-24s ... "):format(path))
  local response, err = http.get(url)
  if not response then
    print("FAILED")
    error(("Could not download %s\n%s\nIf the GitHub repo is private, raw.githubusercontent.com will reject the request."):format(url, tostring(err)), 0)
  end

  if response.getResponseCode then
    local code = response.getResponseCode()
    if code ~= 200 then
      response.close()
      print("FAILED")
      error(("GitHub returned HTTP %s while downloading %s"):format(tostring(code), path), 0)
    end
  end

  local body = response.readAll()
  response.close()

  local handle = fs.open(target, "w")
  if not handle then
    error("Could not stage " .. path, 0)
  end
  handle.write(body)
  handle.close()
  print("OK")
end

local function applyStaged(path)
  local staged = stagedPath(path)
  if not fs.exists(staged) or fs.isDir(staged) then
    error("Staged update is missing " .. path, 0)
  end

  ensureDir(path)

  if fs.exists(path) then
    fs.delete(path)
  end

  fs.move(staged, path)
end

local function readFile(path)
  if not fs.exists(path) or fs.isDir(path) then return nil end
  local handle = fs.open(path, "r")
  if not handle then return nil end
  local body = handle.readAll()
  handle.close()
  return body
end

-- Do not destroy an unrelated startup script on a shared CC computer. The
-- installer still updates the simple startup file it previously installed.
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

local function backupPath(path)
  return fs.combine(BACKUP_DIR, path)
end

local function makeBackup()
  if fs.exists(BACKUP_DIR) then fs.delete(BACKUP_DIR) end
  fs.makeDir(BACKUP_DIR)

  for _, path in ipairs(files) do
    if shouldApply(path) and fs.exists(path) and not fs.isDir(path) then
      local target = backupPath(path)
      ensureDir(target)
      fs.copy(path, target)
    end
  end
end

local function restoreBackup()
  for _, path in ipairs(files) do
    if shouldApply(path) then
      if fs.exists(path) then fs.delete(path) end
      local backup = backupPath(path)
      if fs.exists(backup) and not fs.isDir(backup) then
        ensureDir(path)
        fs.move(backup, path)
      end
    end
  end
end

print("CC-Minecraft Royale installer")
print("--------------------------------")
if preserveCustomStartup then
  print("Custom startup.lua detected - leaving it untouched.")
end
if not http then
  error("HTTP API is disabled on this server/client.", 0)
end

-- Download the complete update before replacing any live program files.
-- A network failure can therefore no longer leave half the repo on the old
-- version and half on the new one.
if fs.exists(STAGE_DIR) then
  fs.delete(STAGE_DIR)
end
fs.makeDir(STAGE_DIR)

for _, path in ipairs(files) do
  download(path)
end

print("")
print("All files downloaded. Applying update...")

makeBackup()
local applied, applyErr = pcall(function()
  for _, path in ipairs(files) do
    if shouldApply(path) then
      applyStaged(path)
    end
  end
end)

if not applied then
  print("APPLY FAILED - restoring previous installation...")
  local restored, restoreErr = pcall(restoreBackup)

  if fs.exists(STAGE_DIR) then fs.delete(STAGE_DIR) end
  if fs.exists(BACKUP_DIR) then fs.delete(BACKUP_DIR) end

  if not restored then
    error(
      "Update failed: " .. tostring(applyErr)
      .. "\nRollback also failed: " .. tostring(restoreErr),
      0
    )
  end

  error("Update failed and was rolled back: " .. tostring(applyErr), 0)
end

if fs.exists(STAGE_DIR) then fs.delete(STAGE_DIR) end
if fs.exists(BACKUP_DIR) then fs.delete(BACKUP_DIR) end

print("")
print("Install complete.")

local mechanicsVersion = "unknown"
if fs.exists("mechanics_test.lua") then
  local handle = fs.open("mechanics_test.lua", "r")
  if handle then
    local body = handle.readAll()
    handle.close()
    mechanicsVersion = body:match("local%s+SUITE_VERSION%s*=%s*(%d+)") or "unknown"
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

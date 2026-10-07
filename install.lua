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
  "src/render.lua",
  "src/admin_render.lua",
  "diagnose.lua",
}

local base = ("https://raw.githubusercontent.com/%s/%s/%s/"):format(OWNER, REPO, BRANCH)

local function ensureDir(path)
  local dir = fs.getDir(path)
  if dir ~= "" and not fs.exists(dir) then
    fs.makeDir(dir)
  end
end

local function download(path)
  ensureDir(path)

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

  local body = response.readAll()
  response.close()

  local handle = fs.open(path, "w")
  if not handle then
    error("Could not write " .. path, 0)
  end
  handle.write(body)
  handle.close()
  print("OK")
end

print("CC-Minecraft Royale installer")
print("--------------------------------")
if not http then
  error("HTTP API is disabled on this server/client.", 0)
end

for _, path in ipairs(files) do
  download(path)
end

print("")
print("Install complete.")
print("Run: diagnose")
print("Then: main")
print("Admin sandbox: admin")

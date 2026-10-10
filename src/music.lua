local config = require("config")
local manifest = require("src.music_manifest")

local Music = {}

local MODULUS = 2147483647
local MULTIPLIER = 48271

local function seedNow()
    local seed
    if os.epoch then
        seed = os.epoch("utc")
    else
        seed = math.floor((os.clock() or 1) * 100000)
    end
    seed = math.floor(math.abs(seed or 1)) % MODULUS
    if seed == 0 then seed = 1 end
    return seed
end

local function rand(controller, max)
    controller.rng = (controller.rng * MULTIPLIER) % MODULUS
    return (controller.rng % max) + 1
end

local function closeHandle(controller)
    if controller.handle then
        pcall(controller.handle.close)
        controller.handle = nil
    end
end

local function makeShuffleBag(controller)
    controller.bag = {}
    for i = 1, #manifest.tracks do
        controller.bag[i] = i
    end

    for i = #controller.bag, 2, -1 do
        local j = rand(controller, i)
        controller.bag[i], controller.bag[j] = controller.bag[j], controller.bag[i]
    end

    -- We pop from the end. Avoid immediately repeating the last song when a
    -- fresh shuffle bag is created.
    if #controller.bag > 1
        and controller.lastTrackId
        and manifest.tracks[controller.bag[#controller.bag]].id == controller.lastTrackId
    then
        controller.bag[#controller.bag], controller.bag[#controller.bag - 1]
            = controller.bag[#controller.bag - 1], controller.bag[#controller.bag]
    end
end

local function seekTo(handle, offset)
    if offset <= 0 then return true end

    if handle.seek then
        local ok, position = pcall(handle.seek, "set", offset)
        if ok and position ~= nil then return true end
    end

    -- Compatibility fallback for older ComputerCraft file handles.
    local left = offset
    while left > 0 do
        local chunk = handle.read(math.min(left, 16384))
        if not chunk then return false end
        left = left - #chunk
    end
    return true
end

local function packForTrack(track)
    return manifest.packs and manifest.packs[track.pack or 1] or nil
end

local function localPackAvailable(pack)
    return pack
        and fs
        and fs.exists
        and fs.exists(pack.path)
        and (not fs.getSize or not pack.size or fs.getSize(pack.path) == pack.size)
end

local function allLocalPacksAvailable()
    if not manifest.packs then return false end
    for _, pack in pairs(manifest.packs) do
        if not localPackAvailable(pack) then return false end
    end
    return true
end

local function remotePacksAvailable()
    if not http or not http.get or not manifest.packs then return false end
    for _, pack in pairs(manifest.packs) do
        if not pack.remoteUrl then return false end
    end
    return true
end

local function openRemoteRange(track, relativeOffset)
    local pack = packForTrack(track)
    if not pack or not http or not http.get or not pack.remoteUrl then
        return nil, "HTTP MUSIC UNAVAILABLE"
    end

    relativeOffset = relativeOffset or 0
    local startByte = track.offset + relativeOffset
    local lastByte = track.offset + track.bytes - 1
    local headers = {
        ["Range"] = ("bytes=%d-%d"):format(startByte, lastByte),
        ["Accept"] = "application/octet-stream",
    }
    local url = pack.remoteUrl .. "?v=" .. tostring(pack.version or pack.size or "1")
    local response, err = http.get({
        url = url,
        headers = headers,
        binary = true,
        timeout = (config.MUSIC and config.MUSIC.httpTimeout) or 6,
    })
    if not response then return nil, tostring(err or "MUSIC HTTP FAILED") end

    if response.getResponseCode then
        local code = response.getResponseCode()

        if code ~= 200 and code ~= 206 then
            response.close()
            return nil, "MUSIC HTTP " .. tostring(code)
        end

        if startByte > 0 and code == 200 then
            if not seekTo(response, startByte) then
                response.close()
                return nil, "MUSIC STREAM SKIP FAILED"
            end
        end
    end

    return response
end

local function openSource(controller, track, relativeOffset)
    closeHandle(controller)
    relativeOffset = relativeOffset or 0

    local pack = packForTrack(track)
    if not pack then return false, "MUSIC PACK NOT FOUND" end

    local handle
    if localPackAvailable(pack) then
        handle = fs.open(pack.path, "rb")
        if not handle then return false, "MUSIC PACK OPEN FAILED" end
        if not seekTo(handle, track.offset + relativeOffset) then
            handle.close()
            return false, "MUSIC SEEK FAILED"
        end
        controller.source = "local"
    else
        local err
        handle, err = openRemoteRange(track, relativeOffset)
        if not handle then return false, err end
        controller.source = "stream"
    end

    controller.handle = handle
    return true
end

local function openTrack(controller, trackIndex)
    local track = manifest.tracks[trackIndex]
    if not track then return false, "TRACK NOT FOUND" end

    controller.currentTrackIndex = trackIndex
    controller.currentTrackId = track.id
    controller.lastTrackId = track.id
    controller.bytesRead = 0
    controller.remaining = track.bytes
    controller.decoder = controller.dfpwm.make_decoder()
    controller.reconnectAttempts = 0

    return openSource(controller, track, 0)
end

local function reopenCurrentTrack(controller)
    local trackIndex = controller.currentTrackIndex
    local track = trackIndex and manifest.tracks[trackIndex] or nil
    if not track then return false, "TRACK NOT FOUND" end

    controller.reconnectAttempts = (controller.reconnectAttempts or 0) + 1
    return openSource(controller, track, controller.bytesRead or 0)
end

local function nextTrack(controller)
    if #controller.bag == 0 then makeShuffleBag(controller) end
    local trackIndex = table.remove(controller.bag)
    return openTrack(controller, trackIndex)
end

function Music.new(speaker, speakerName)
    local ok, dfpwm = pcall(require, "cc.audio.dfpwm")

    return {
        speaker = speaker,
        speakerName = speakerName,
        dfpwm = ok and dfpwm or nil,
        active = false,
        available = speaker ~= nil
            and ok
            and (allLocalPacksAvailable() or remotePacksAvailable()),
        handle = nil,
        remaining = 0,
        bytesRead = 0,
        decoder = nil,
        pending = nil,
        currentTrackIndex = nil,
        currentTrackId = nil,
        lastTrackId = nil,
        reconnectAttempts = 0,
        retryAt = 0,
        consecutiveFailures = 0,
        bag = {},
        rng = seedNow(),
        volume = manifest.volume or 0.28,
        error = nil,
    }
end

function Music.refreshAvailability(controller)
    local localReady = allLocalPacksAvailable()
    local remoteReady = remotePacksAvailable()

    controller.available = controller.speaker ~= nil
        and controller.dfpwm ~= nil
        and (localReady or remoteReady)

    if not controller.available then
        controller.error = "BATTLE MUSIC SOURCE UNAVAILABLE"
    end

    return controller.available
end

function Music.start(controller)
    if controller.active then return true end
    if not Music.refreshAvailability(controller) then
        controller.error = controller.error or "BATTLE MUSIC NOT INSTALLED"
        return false
    end

    controller.error = nil
    controller.active = true
    controller.pending = nil
    controller.currentTrackId = nil

    local ok, err = nextTrack(controller)
    if not ok then
        -- Keep the controller active so the regular timer-driven pump can
        -- retry transient GitHub/HTTP failures instead of losing music for
        -- the entire match after one failed request at battle start.
        controller.consecutiveFailures = (controller.consecutiveFailures or 0) + 1
        controller.error = tostring(err or "BATTLE MUSIC SOURCE UNAVAILABLE")
        local now = os.epoch and os.epoch("utc") / 1000 or os.clock()
        local delay = math.min(12, 1.5 * (2 ^ math.min(3, controller.consecutiveFailures - 1)))
        controller.retryAt = now + delay
        closeHandle(controller)
        return false
    end

    Music.pump(controller)
    return true
end

function Music.stop(controller, hardStop)
    controller.active = false
    controller.pending = nil
    controller.currentTrackIndex = nil
    controller.currentTrackId = nil
    controller.retryAt = 0
    controller.reconnectAttempts = 0
    controller.consecutiveFailures = 0
    closeHandle(controller)

    if hardStop and controller.speaker and controller.speaker.stop then
        pcall(controller.speaker.stop)
    end
end

local function nowSeconds()
    if os.epoch then return os.epoch("utc") / 1000 end
    return os.clock()
end

local function scheduleRetry(controller, err, delay)
    controller.consecutiveFailures = (controller.consecutiveFailures or 0) + 1
    controller.error = tostring(err or "MUSIC STREAM INTERRUPTED")

    -- Persistent GitHub/network failures should not cause a new HTTP request
    -- every 0.5-1.5 seconds for the entire match. Back off exponentially while
    -- still retrying automatically when the connection returns.
    local base = delay or 0.75
    local multiplier = 2 ^ math.min(4, controller.consecutiveFailures - 1)
    controller.retryAt = nowSeconds() + math.min(20, base * multiplier)
    closeHandle(controller)
end

local function ensureSource(controller)
    if controller.handle then return true end
    if controller.retryAt and nowSeconds() < controller.retryAt then return false end

    local ok, err
    if controller.currentTrackIndex
        and controller.remaining > 0
        and (controller.reconnectAttempts or 0) < 3
    then
        ok, err = reopenCurrentTrack(controller)
    else
        controller.currentTrackIndex = nil
        controller.currentTrackId = nil
        controller.remaining = 0
        controller.bytesRead = 0
        ok, err = nextTrack(controller)
    end

    if not ok then
        scheduleRetry(controller, err, 1.5)
        return false
    end

    controller.error = nil
    controller.retryAt = 0
    return true
end

function Music.pump(controller)
    if not controller.active or not controller.available then return false end

    -- CC:Tweaked speakers buffer one playAudio call at a time. Keep at most
    -- one decoded chunk pending and wait for speaker_audio_empty before adding
    -- another. Large chunks are substantially less prone to stutter.
    if controller.pending then
        local ok, queued = pcall(
            controller.speaker.playAudio,
            controller.pending,
            controller.volume
        )
        if not ok then
            scheduleRetry(controller, queued, 0.75)
            return false
        end
        if not queued then return false end

        controller.pending = nil
        controller.error = nil
        controller.consecutiveFailures = 0
        return true
    end

    if controller.remaining <= 0 then
        controller.currentTrackIndex = nil
        controller.currentTrackId = nil
        controller.bytesRead = 0
        controller.reconnectAttempts = 0
        closeHandle(controller)
    end

    if not ensureSource(controller) then return false end

    local amount = math.min(manifest.chunkBytes or 16384, controller.remaining)
    local okRead, data = pcall(controller.handle.read, amount)

    if not okRead or not data or #data == 0 then
        if controller.remaining > 0 then
            if (controller.reconnectAttempts or 0) >= 3 then
                -- Skip a persistently broken track instead of killing music
                -- for the rest of the match.
                controller.currentTrackIndex = nil
                controller.currentTrackId = nil
                controller.remaining = 0
                controller.bytesRead = 0
                controller.reconnectAttempts = 0
                scheduleRetry(controller, "SKIPPING INTERRUPTED TRACK", 0.5)
            else
                scheduleRetry(controller, okRead and "MUSIC STREAM ENDED EARLY" or data, 0.5)
            end
        end
        return false
    end

    controller.remaining = controller.remaining - #data
    controller.bytesRead = (controller.bytesRead or 0) + #data
    controller.reconnectAttempts = 0

    local decoded = controller.decoder(data)
    local okPlay, queued = pcall(
        controller.speaker.playAudio,
        decoded,
        controller.volume
    )

    if not okPlay then
        controller.pending = decoded
        scheduleRetry(controller, queued, 0.75)
        return false
    end

    if not queued then
        controller.pending = decoded
        return false
    end

    controller.error = nil
    controller.consecutiveFailures = 0
    return true
end

function Music.handleEvent(controller, event)
    if not controller.active then return end
    if not event or event[1] ~= "speaker_audio_empty" then return end

    if controller.speakerName
        and event[2]
        and event[2] ~= controller.speakerName
    then
        return
    end

    Music.pump(controller)
end

function Music.status(controller)
    return {
        available = controller.available,
        active = controller.active,
        track = controller.currentTrackId,
        tracks = #manifest.tracks,
        source = controller.source,
        reconnects = controller.reconnectAttempts or 0,
        failures = controller.consecutiveFailures or 0,
        retryAt = controller.retryAt or 0,
        error = controller.error,
    }
end

return Music

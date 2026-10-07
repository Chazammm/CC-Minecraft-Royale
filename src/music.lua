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

local function localPackAvailable()
    return fs
        and fs.exists
        and fs.exists(manifest.path)
        and (not fs.getSize or not manifest.packSize or fs.getSize(manifest.path) == manifest.packSize)
end

local function openRemoteRange(track)
    if not http or not http.get or not manifest.remoteUrl then
        return nil, "HTTP MUSIC UNAVAILABLE"
    end

    local lastByte = track.offset + track.bytes - 1
    local headers = {
        ["Range"] = ("bytes=%d-%d"):format(track.offset, lastByte),
        ["Accept"] = "application/octet-stream",
    }
    local url = manifest.remoteUrl .. "?v=" .. tostring(manifest.packVersion or manifest.packSize or "1")
    local response, err = http.get(url, headers, true)
    if not response then return nil, tostring(err or "MUSIC HTTP FAILED") end

    if response.getResponseCode then
        local code = response.getResponseCode()

        if track.offset > 0 and code ~= 206 then
            -- Most GitHub Raw responses support byte ranges. If a proxy strips
            -- the Range header and returns 200, keep the feature functional by
            -- streaming/discarding bytes until this song's offset. Nothing is
            -- stored in the computer's tiny filesystem.
            if code == 200 then
                if not seekTo(response, track.offset) then
                    response.close()
                    return nil, "MUSIC STREAM SKIP FAILED"
                end
            else
                response.close()
                return nil, "MUSIC HTTP " .. tostring(code)
            end
        end
    end

    return response
end

local function openTrack(controller, trackIndex)
    closeHandle(controller)

    local track = manifest.tracks[trackIndex]
    if not track then return false, "TRACK NOT FOUND" end

    local handle
    if localPackAvailable() then
        handle = fs.open(manifest.path, "rb")
        if not handle then return false, "MUSIC PACK OPEN FAILED" end
        if not seekTo(handle, track.offset) then
            handle.close()
            return false, "MUSIC SEEK FAILED"
        end
        controller.source = "local"
    else
        local err
        handle, err = openRemoteRange(track)
        if not handle then return false, err end
        controller.source = "stream"
    end

    controller.handle = handle
    controller.remaining = track.bytes
    controller.currentTrackId = track.id
    controller.lastTrackId = track.id
    controller.decoder = controller.dfpwm.make_decoder()
    return true
end

local function nextTrack(controller)
    if #controller.bag == 0 then makeShuffleBag(controller) end
    local trackIndex = table.remove(controller.bag)
    return openTrack(controller, trackIndex)
end

local function upsample(samples, repeatFactor)
    if repeatFactor <= 1 then return samples end

    local output = {}
    local n = 0
    for i = 1, #samples do
        local sample = samples[i]
        for _ = 1, repeatFactor do
            n = n + 1
            output[n] = sample
        end
    end
    return output
end

local function tryPending(controller)
    if not controller.pending then return true end
    local ok, queued = pcall(
        controller.speaker.playAudio,
        controller.pending,
        controller.volume
    )
    if not ok or not queued then return false end
    controller.pending = nil
    return true
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
            and (localPackAvailable() or (http and http.get and manifest.remoteUrl ~= nil)),
        handle = nil,
        remaining = 0,
        decoder = nil,
        pending = nil,
        currentTrackId = nil,
        lastTrackId = nil,
        bag = {},
        rng = seedNow(),
        volume = manifest.volume or 0.32,
        error = nil,
    }
end

function Music.refreshAvailability(controller)
    local localReady = localPackAvailable()
    local remoteReady = http and http.get and manifest.remoteUrl ~= nil

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
        controller.active = false
        controller.error = err
        closeHandle(controller)
        return false
    end

    Music.pump(controller)
    return true
end

function Music.stop(controller, hardStop)
    controller.active = false
    controller.pending = nil
    controller.currentTrackId = nil
    closeHandle(controller)

    if hardStop and controller.speaker and controller.speaker.stop then
        pcall(controller.speaker.stop)
    end
end

function Music.pump(controller)
    if not controller.active or not controller.available then return false end
    if not tryPending(controller) then return false end

    -- Queue a few short buffers. At 24 kHz DFPWM with x2 sample duplication,
    -- each 2048-byte chunk is about 0.68 s of 48 kHz speaker audio.
    for _ = 1, 3 do
        if controller.remaining <= 0 then
            local ok, err = nextTrack(controller)
            if not ok then
                controller.error = err
                controller.active = false
                closeHandle(controller)
                return false
            end
        end

        local amount = math.min(manifest.chunkBytes or 2048, controller.remaining)
        local data = controller.handle and controller.handle.read(amount) or nil

        if not data or #data == 0 then
            controller.remaining = 0
        else
            controller.remaining = controller.remaining - #data
            local decoded = controller.decoder(data)
            local samples = upsample(decoded, manifest.repeatFactor or 2)

            local ok, queued = pcall(
                controller.speaker.playAudio,
                samples,
                controller.volume
            )

            if not ok then
                controller.error = tostring(queued)
                controller.active = false
                closeHandle(controller)
                return false
            end

            if not queued then
                controller.pending = samples
                return false
            end
        end
    end

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
        error = controller.error,
    }
end

return Music

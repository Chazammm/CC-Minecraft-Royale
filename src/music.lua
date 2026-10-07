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

local function openTrack(controller, trackIndex)
    closeHandle(controller)

    local track = manifest.tracks[trackIndex]
    if not track then return false, "TRACK NOT FOUND" end

    local handle = fs.open(manifest.path, "rb")
    if not handle then return false, "MUSIC PACK MISSING" end
    if not seekTo(handle, track.offset) then
        handle.close()
        return false, "MUSIC SEEK FAILED"
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
            and fs
            and fs.exists
            and fs.exists(manifest.path),
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
    controller.available = controller.speaker ~= nil
        and controller.dfpwm ~= nil
        and fs
        and fs.exists
        and fs.exists(manifest.path)

    if controller.available and fs.getSize then
        local size = fs.getSize(manifest.path)
        if manifest.packSize and size ~= manifest.packSize then
            controller.available = false
            controller.error = "MUSIC PACK SIZE MISMATCH"
        end
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
        error = controller.error,
    }
end

return Music

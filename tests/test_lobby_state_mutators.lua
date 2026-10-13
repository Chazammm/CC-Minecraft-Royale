-- Lock down public deck/preset mutations to lobby-only state.
-- These APIs are reachable outside Game.handleTouch through scripts/dev tools.
colors = {
    white=1, orange=2, magenta=4, lightBlue=8,
    yellow=16, lime=32, pink=64, gray=128,
    lightGray=256, cyan=512, purple=1024, blue=2048,
    brown=4096, green=8192, red=16384, black=32768,
}
package.path = "./?.lua;./?/init.lua;" .. package.path

local Game = require("src.game")
local Cards = require("src.cards")
local Presets = require("src.presets")

local oldSave = Presets.save
local saveCalls = 0
Presets.save = function()
    saveCalls = saveCalls + 1
    return true
end

local function newFixture(phase)
    local state = Game.new(nil, { headlessSimulation = true })
    local player = state.players[1]
    player.deck = Cards.defaultDeck()
    player.hand = { "zombie", "skeleton", "iron_golem", "bat_swarm" }
    player.queue = { "cannon", "arrows", "creeper", "slime" }
    player.evolutionCardId = "creeper"
    player.evolutionProgress = 1
    player.ready = true

    local alternate = Cards.defaultDeck()
    alternate[8] = "wolf"
    assert(Cards.isValidDeck(alternate), "Fixture preset must be valid")
    state.deckPresets[1][1] = alternate
    state.phase = phase
    return state, player
end

local function snapshot(player)
    return table.concat(player.deck, ",")
        .. "|" .. table.concat(player.hand, ",")
        .. "|" .. table.concat(player.queue, ",")
        .. "|" .. tostring(player.evolutionCardId)
        .. "|" .. tostring(player.evolutionProgress)
        .. "|" .. tostring(player.ready)
end

for _, phase in ipairs({ "countdown", "battle", "result", "admin" }) do
    for _, command in ipairs({
        function(state) return Game.toggleDeckCard(state, 1, "creeper") end,
        function(state) return Game.randomizeDeck(state, 1) end,
        function(state) return Game.loadDeckPreset(state, 1, 1) end,
        function(state) return Game.saveDeckPreset(state, 1, 1) end,
    }) do
        local state, player = newFixture(phase)
        local before = snapshot(player)
        local savesBefore = saveCalls
        local ok, result = pcall(command, state)
        assert(ok, "Non-lobby deck operation must fail safely (" .. phase .. ")")
        assert(result == false, "Non-lobby deck operation must return false (" .. phase .. ")")
        assert(snapshot(player) == before, "Non-lobby deck operation changed player state (" .. phase .. ")")
        assert(saveCalls == savesBefore, "Non-lobby operation persisted presets (" .. phase .. ")")
    end
end

do
    local state = newFixture("battle")
    math.randomseed(777)
    local expectedNext = math.random()
    math.randomseed(777)
    assert(Game.randomizeDeck(state, 1) == false, "Battle randomize must reject")
    assert(math.random() == expectedNext, "Rejected randomize must not disturb gameplay RNG")
end

do
    local state, player = newFixture("lobby")
    local before = snapshot(player)
    for _, slot in ipairs({ -1, 0, 1.5, 4, "1", math.huge }) do
        for _, fn in ipairs({ Game.saveDeckPreset, Game.loadDeckPreset }) do
            local ok, result = pcall(fn, state, 1, slot)
            assert(ok and result == false, "Malformed slot must be rejected without an error: " .. tostring(slot))
            assert(snapshot(player) == before, "Malformed preset slot changed player")
        end
    end
    for _, fn in ipairs({ Game.saveDeckPreset, Game.loadDeckPreset }) do
        local ok, result = pcall(fn, state, 1, nil)
        assert(ok and result == false, "Nil preset slot must fail safely")
    end

    assert(Game.loadDeckPreset(state, 1, 1) == true, "Valid lobby preset load must work")
    assert(player.deck[8] == "wolf", "Valid preset load must update the deck")
    assert(Game.saveDeckPreset(state, 1, 1) == true, "Valid lobby preset save must work")
    assert(saveCalls == 1, "Only the valid lobby save may call persistence")
    assert(Game.toggleDeckCard(state, 1, "wolf") == true, "Lobby deck editing must work")
    assert(Game.randomizeDeck(state, 1) == true, "Lobby random deck must work")
end

Presets.save = oldSave
print("Lobby state mutation guards passed")

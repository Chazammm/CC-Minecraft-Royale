local Game = require("src.game")
local Bot = require("src.bot")
local cards = require("src.cards")

local args = { ... }
local matchCount = math.floor(tonumber(args[1]) or 100)
matchCount = math.max(1, math.min(500, matchCount))

local DECK_A = Bot.defaultDeck()
local DECK_B = {
    "skeleton",
    "iron_golem",
    "bat_swarm",
    "creeper",
    "slime",
    "witch",
    "spider",
    "wolf",
}

local report = {
    aWins = 0,
    bWins = 0,
    draws = 0,
    totalTime = 0,
    aTowerDamage = 0,
    bTowerDamage = 0,
    cards = {},
}

local function addCardStats(label, source)
    for cardId, stat in pairs(source or {}) do
        local key = label .. ":" .. cardId
        local out = report.cards[key]
        if not out then
            out = {
                label = label,
                cardId = cardId,
                plays = 0,
                emeraldSpent = 0,
                unitDamage = 0,
                towerDamage = 0,
                kills = 0,
                towersKilled = 0,
            }
            report.cards[key] = out
        end

        out.plays = out.plays + (stat.plays or 0)
        out.emeraldSpent = out.emeraldSpent + (stat.emeraldSpent or 0)
        out.unitDamage = out.unitDamage + (stat.unitDamage or 0)
        out.towerDamage = out.towerDamage + (stat.towerDamage or 0)
        out.kills = out.kills + (stat.kills or 0)
        out.towersKilled = out.towersKilled + (stat.towersKilled or 0)
    end
end

local function runMatch(index)
    local state = Game.new()

    -- Swap sides every match so P1/P2 geometry does not bias the report.
    local aOwner = index % 2 == 1 and 1 or 2
    local bOwner = aOwner == 1 and 2 or 1

    local botA = Bot.new(aOwner, DECK_A)
    local botB = Bot.new(bOwner, DECK_B)

    Bot.prepare(botA, state)
    Bot.prepare(botB, state)

    state.players[1].ready = true
    state.players[2].ready = true
    Game.startCountdown(state)

    Bot.beginMatch(botA)
    Bot.beginMatch(botB)
    botA.enabled = true
    botB.enabled = true

    local ticks = 0
    while state.phase ~= "result" and ticks < 1400 do
        Game.update(state, 0.25)
        Bot.update(botA, state, 0.25)
        Bot.update(botB, state, 0.25)
        ticks = ticks + 1
    end

    if state.phase ~= "result" then
        Game.finish(state, nil, "SIMULATION TIMEOUT")
    end

    if state.winner == aOwner then
        report.aWins = report.aWins + 1
    elseif state.winner == bOwner then
        report.bWins = report.bWins + 1
    else
        report.draws = report.draws + 1
    end

    report.totalTime = report.totalTime + (state.stats.elapsed or 0)

    local aStats = state.stats.players[aOwner]
    local bStats = state.stats.players[bOwner]
    report.aTowerDamage = report.aTowerDamage + (aStats.towerDamage or 0)
    report.bTowerDamage = report.bTowerDamage + (bStats.towerDamage or 0)

    addCardStats("A", aStats.cards)
    addCardStats("B", bStats.cards)
end

print("CC-Minecraft Royale balance simulation")
print(("Running %d bot-vs-bot matches..."):format(matchCount))
print("")

for i = 1, matchCount do
    runMatch(i)
    if i % 10 == 0 or i == matchCount then
        print(("  %d / %d"):format(i, matchCount))
        if sleep then sleep(0) end
    end
end

print("")
print("RESULT")
print(("Deck A wins: %d (%.1f%%)"):format(report.aWins, report.aWins / matchCount * 100))
print(("Deck B wins: %d (%.1f%%)"):format(report.bWins, report.bWins / matchCount * 100))
print(("Draws:       %d (%.1f%%)"):format(report.draws, report.draws / matchCount * 100))
print(("Avg match:   %.1fs"):format(report.totalTime / matchCount))
print(("Avg tower damage A/B: %.0f / %.0f"):format(
    report.aTowerDamage / matchCount,
    report.bTowerDamage / matchCount
))

local rows = {}
for _, stat in pairs(report.cards) do
    if stat.plays > 0 then
        local card = cards.get(stat.cardId)
        local value = stat.unitDamage + stat.towerDamage * 1.5
        local perEmerald = stat.emeraldSpent > 0 and value / stat.emeraldSpent or 0
        table.insert(rows, {
            label = stat.label,
            name = card and card.name or stat.cardId,
            plays = stat.plays,
            spent = stat.emeraldSpent,
            unitDamage = stat.unitDamage,
            towerDamage = stat.towerDamage,
            kills = stat.kills,
            valuePerEmerald = perEmerald,
        })
    end
end

table.sort(rows, function(a, b)
    return a.valuePerEmerald > b.valuePerEmerald
end)

print("")
print("CARD VALUE (damage-weighted per Emerald)")
print("Deck Card             Plays  Dmg/E  TowerDmg")
for _, row in ipairs(rows) do
    print(("%-4s %-16s %5d %6.1f %8.0f"):format(
        row.label,
        row.name,
        row.plays,
        row.valuePerEmerald,
        row.towerDamage
    ))
end

print("")
print("Deck A:")
print("  " .. table.concat(DECK_A, ", "))
print("Deck B:")
print("  " .. table.concat(DECK_B, ", "))

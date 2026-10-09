local Bot = require("src.bot")
local cards = require("src.cards")
local config = require("config")
local benchmark = require("src.benchmark_utils")
local Runner = require("src.headless_match")

local args = { ... }

local resultPath = "balance_results.txt"
local SIM_DT = config.TICK_RATE or 0.10
local YIELD_CHECK_TICKS = 50
local YIELD_AFTER_MS = 500
local lastYieldMs = os.epoch and os.epoch("utc") or 0

local function cooperativeYield(force)
    local due = force == true

    if not due and os.epoch then
        due = os.epoch("utc") - lastYieldMs >= YIELD_AFTER_MS
    elseif not due and not os.epoch then
        due = true
    end

    if not due then return end

    if os.queueEvent and os.pullEvent then
        os.queueEvent("__cc_royale_benchmark_yield")
        os.pullEvent("__cc_royale_benchmark_yield")
    elseif sleep then
        sleep(0)
    end

    if os.epoch then
        lastYieldMs = os.epoch("utc")
    end
end
local nativePrint = print
local liveHandle = nil

local function reportPrint(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring(select(i, ...))
    end

    local line = table.concat(parts, "\t")
    nativePrint(line)

    if liveHandle then
        liveHandle.write(line)
        liveHandle.write("\n")
        if liveHandle.flush then liveHandle.flush() end
    end
end

local function printUsage()
    nativePrint("Usage: simulate <100-1000> [mixed|fixed] [seed]")
    nativePrint("Examples:")
    nativePrint("  simulate 100")
    nativePrint("  simulate 137 mixed")
    nativePrint("  simulate 500 mixed")
    nativePrint("  simulate 1000 fixed")
end

local rawCount = args[1]
if rawCount == nil or rawCount == "help" or rawCount == "--help" or rawCount == "-h" then
    printUsage()
    return
end

local parsedCount = tonumber(rawCount)
if not parsedCount
    or parsedCount ~= math.floor(parsedCount)
    or parsedCount < 100
    or parsedCount > 1000
then
    nativePrint("ERROR: Match count must be a whole number from 100 to 1000.")
    printUsage()
    return
end

local matchCount = parsedCount

local mode = string.lower(tostring(args[2] or "mixed"))
if mode ~= "mixed" and mode ~= "fixed" then
    nativePrint("ERROR: Mode must be 'mixed' or 'fixed'.")
    printUsage()
    return
end

local seed = math.floor(tonumber(args[3]) or 1337)

-- Only replace the previous report after all command-line arguments have
-- passed validation. "simulate help" and invalid commands must preserve it.
liveHandle = fs and fs.open(resultPath, "w") or nil

local randomInt = benchmark.newRandomInt(seed)
local copy = benchmark.copy

local function shuffle(list)
    return benchmark.shuffle(list, randomInt)
end

local ALL_CARDS = {}
for _, card in ipairs(cards.list) do
    table.insert(ALL_CARDS, card.id)
end

local FIXED_A = Bot.defaultDeck()
local FIXED_B = {
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
    matches = 0,
    p1Wins = 0,
    p2Wins = 0,
    draws = 0,
    totalTime = 0,
    cards = {},
}

local function cardReport(cardId)
    local out = report.cards[cardId]
    if not out then
        out = {
            cardId = cardId,
            deckMatches = 0,
            wins = 0,
            draws = 0,
            plays = 0,
            emeraldSpent = 0,
            unitDamage = 0,
            towerDamage = 0,
            kills = 0,
            towersKilled = 0,
            emeraldBonus = 0,
            slowSeconds = 0,
            targetsHit = 0,
            evolutionPlays = 0,
            evolutionSlotMatches = 0,
            evolutionSelectedPlays = 0,
        }
        report.cards[cardId] = out
    end
    return out
end

local function addDeckResult(deck, owner, state)
    local won = state.winner == owner
    local drew = state.winner == nil
    local playerStats = state.stats.players[owner]

    for _, cardId in ipairs(deck) do
        local out = cardReport(cardId)
        out.deckMatches = out.deckMatches + 1
        if won then out.wins = out.wins + 1 end
        if drew then out.draws = out.draws + 1 end

        local selectedForEvolution = state.players[owner].evolutionCardId == cardId
        if selectedForEvolution then
            out.evolutionSlotMatches = out.evolutionSlotMatches + 1
        end

        local stat = playerStats.cards[cardId]
        if stat then
            out.plays = out.plays + (stat.plays or 0)
            if selectedForEvolution then
                out.evolutionSelectedPlays = out.evolutionSelectedPlays + (stat.plays or 0)
            end
            out.emeraldSpent = out.emeraldSpent + (stat.emeraldSpent or 0)
            out.unitDamage = out.unitDamage + (stat.unitDamage or 0)
            out.towerDamage = out.towerDamage + (stat.towerDamage or 0)
            out.kills = out.kills + (stat.kills or 0)
            out.towersKilled = out.towersKilled + (stat.towersKilled or 0)
            out.emeraldBonus = out.emeraldBonus + (stat.emeraldBonus or 0)
            out.slowSeconds = out.slowSeconds + (stat.slowSeconds or 0)
            out.targetsHit = out.targetsHit + (stat.targetsHit or 0)
            out.evolutionPlays = out.evolutionPlays + (stat.evolutionPlays or 0)
        end
    end
end

local function runMatch(deck1, deck2, botOrderOffset, gameplaySeed)
    local state = Runner.run(deck1, deck2, {
        dt = SIM_DT,
        gameplaySeed = gameplaySeed,
        botOrderOffset = botOrderOffset or 0,
        yieldFn = cooperativeYield,
        yieldCheckTicks = YIELD_CHECK_TICKS,
        timeoutReason = "SIMULATION TIMEOUT",
    })

    report.matches = report.matches + 1
    report.totalTime = report.totalTime + (state.stats.elapsed or 0)

    if state.winner == 1 then
        report.p1Wins = report.p1Wins + 1
    elseif state.winner == 2 then
        report.p2Wins = report.p2Wins + 1
    else
        report.draws = report.draws + 1
    end

    addDeckResult(deck1, 1, state)
    addDeckResult(deck2, 2, state)
end

local function mixedDeckPair()
    local pool = shuffle(ALL_CARDS)
    local a, b = {}, {}

    for i = 1, 8 do a[i] = pool[i] end
    for i = 9, 16 do b[i - 8] = pool[i] end

    -- Randomize hand/cycle order inside both decks too.
    return shuffle(a), shuffle(b)
end

reportPrint("CC-Minecraft Royale balance benchmark")
reportPrint(("Mode: %s   Matches: %d   Seed: %d   Tick: %.2fs"):format(
    string.upper(mode),
    matchCount,
    seed,
    SIM_DT
))
if mode == "mixed" then
    reportPrint(("%d-card pool: 16 are sampled into two disjoint 8-card decks each pair."):format(#ALL_CARDS))
    reportPrint("The unused cards change every shuffle; pairs are replayed with sides swapped.")
else
    reportPrint("Using the original fixed Deck A vs Deck B comparison.")
end
reportPrint("")
reportPrint("Side-swapped pairs reuse one gameplay RNG seed; deck sampling RNG stays independent.")

local function gameplaySeedForPair(pairIndex)
    local value = (seed + pairIndex * 1000003) % 2147483646
    return value + 1
end

local benchmarkStartedMs = os.epoch and os.epoch("utc") or nil
local completed = 0
while completed < matchCount do
    local deckA, deckB

    if mode == "fixed" then
        deckA, deckB = copy(FIXED_A), copy(FIXED_B)
    else
        deckA, deckB = mixedDeckPair()
    end

    local pairIndex = math.floor(completed / 2) + 1
    local gameplaySeed = gameplaySeedForPair(pairIndex)

    if completed + 1 == matchCount then
        -- Odd match counts cannot form a complete side-swapped pair. Randomize
        -- the final orientation so the leftover game is not always A=P1.
        local orderOffset = randomInt(2) - 1
        if randomInt(2) == 1 then
            runMatch(deckA, deckB, orderOffset, gameplaySeed)
        else
            runMatch(deckB, deckA, orderOffset, gameplaySeed)
        end
        completed = completed + 1
    else
        runMatch(deckA, deckB, 0, gameplaySeed)
        completed = completed + 1

        runMatch(deckB, deckA, 1, gameplaySeed)
        completed = completed + 1
    end

    if completed % 20 == 0 or completed >= matchCount then
        reportPrint(("  %d / %d"):format(completed, matchCount))
        if sleep then sleep(0) end
    end
end

reportPrint("")
reportPrint("GLOBAL")
reportPrint(("P1 wins: %d (%.1f%%)"):format(report.p1Wins, report.p1Wins / report.matches * 100))
reportPrint(("P2 wins: %d (%.1f%%)"):format(report.p2Wins, report.p2Wins / report.matches * 100))
reportPrint(("Draws:   %d (%.1f%%)"):format(report.draws, report.draws / report.matches * 100))
reportPrint(("Avg match: %.1fs"):format(report.totalTime / report.matches))
if benchmarkStartedMs and os.epoch then
    local runtimeSeconds = math.max(
        0.001,
        (os.epoch("utc") - benchmarkStartedMs) / 1000
    )
    reportPrint(("Real runtime: %.1fs   Throughput: %.2f matches/s"):format(
        runtimeSeconds,
        report.matches / runtimeSeconds
    ))
end

local rows = {}
for _, card in ipairs(cards.list) do
    local stat = cardReport(card.id)
    local scoreRate = stat.deckMatches > 0
        and (stat.wins + stat.draws * 0.5) / stat.deckMatches * 100
        or 0
    local playsPerMatch = stat.deckMatches > 0 and stat.plays / stat.deckMatches or 0
    local unitPerE = stat.emeraldSpent > 0 and stat.unitDamage / stat.emeraldSpent or 0
    local towerPerE = stat.emeraldSpent > 0 and stat.towerDamage / stat.emeraldSpent or 0

    local flag = "OK"
    if stat.deckMatches >= 20 then
        if scoreRate >= 56 then
            flag = "WATCH+"
        elseif scoreRate <= 44 then
            flag = "WATCH-"
        end
    end

    table.insert(rows, {
        id = card.id,
        name = card.name,
        scoreRate = scoreRate,
        playsPerMatch = playsPerMatch,
        unitPerE = unitPerE,
        towerPerE = towerPerE,
        kills = stat.kills,
        emeraldBonus = stat.emeraldBonus,
        slowSeconds = stat.slowSeconds,
        targetsHit = stat.targetsHit,
        totalPlays = stat.plays,
        evolutionPlays = stat.evolutionPlays,
        evolutionSlotMatches = stat.evolutionSlotMatches,
        evolutionSelectedPlays = stat.evolutionSelectedPlays,
        flag = flag,
    })
end

table.sort(rows, function(a, b)
    if a.scoreRate == b.scoreRate then return a.name < b.name end
    return a.scoreRate > b.scoreRate
end)

reportPrint("")
reportPrint("CARD BALANCE")
reportPrint("Card             Score  P/M   U/E   T/E   Flag")
for _, row in ipairs(rows) do
    reportPrint(("%-16s %5.1f %4.1f %5.1f %5.1f %-6s"):format(
        row.name,
        row.scoreRate,
        row.playsPerMatch,
        row.unitPerE,
        row.towerPerE,
        row.flag
    ))
end

reportPrint("")
reportPrint("UTILITY")
reportPrint("Card             BonusE  Slow/s  Hits/Play")
for _, row in ipairs(rows) do
    local bonusPerMatch = report.cards[row.id].deckMatches > 0
        and row.emeraldBonus / report.cards[row.id].deckMatches
        or 0
    local slowPerPlay = row.totalPlays > 0 and row.slowSeconds / row.totalPlays or 0
    local hitsPerPlay = row.totalPlays > 0 and row.targetsHit / row.totalPlays or 0

    if bonusPerMatch > 0 or slowPerPlay > 0 or hitsPerPlay > 0 then
        reportPrint(("%-16s %6.2f %7.2f %9.2f"):format(
            row.name,
            bonusPerMatch,
            slowPerPlay,
            hitsPerPlay
        ))
    end
end

reportPrint("")
reportPrint("EVOLUTIONS")
reportPrint("Card             Slot% Evo/SM  Evo% Cycles EvoCost")
for _, row in ipairs(rows) do
    if cards.hasEvolution(row.id) then
        local stat = report.cards[row.id]
        local slotMatches = row.evolutionSlotMatches or 0
        local slotShare = stat.deckMatches > 0
            and slotMatches / stat.deckMatches * 100
            or 0
        local evoPerSlotMatch = slotMatches > 0
            and (row.evolutionPlays or 0) / slotMatches
            or 0
        local evoShare = (row.evolutionSelectedPlays or 0) > 0
            and (row.evolutionPlays or 0) / row.evolutionSelectedPlays * 100
            or 0
        local cycles = cards.evolutionCycles(row.id) or 0
        local evoCost = cards.evolutionCost(row.id) or cards.get(row.id).cost

        reportPrint(("%-16s %5.1f %6.2f %5.1f %6d %7.1f"):format(
            row.name,
            slotShare,
            evoPerSlotMatch,
            evoShare,
            cycles,
            evoCost
        ))
    end
end

reportPrint("")
reportPrint("HOW TO READ")
reportPrint("Score = deck win rate with draws worth half a win.")
reportPrint("P/M   = times played per match while the card is in deck.")
reportPrint("U/E   = unit damage per Emerald spent.")
reportPrint("T/E   = tower damage per Emerald spent.")
reportPrint("WATCH+/- means investigate, not automatic nerf/buff.")
reportPrint("")
reportPrint("Recommended benchmark: simulate 500 mixed")

if liveHandle then
    liveHandle.close()
    nativePrint("")
    nativePrint("Saved full report to: " .. resultPath)
    nativePrint("View it with: type " .. resultPath)

    local syncLoaded, ReportSync = pcall(require, "src.report_sync")
    if syncLoaded and ReportSync.isConfigured() then
        nativePrint("Syncing balance report to GitHub...")
        local synced, syncResult = ReportSync.autoUpload("balance", resultPath)
        if synced then
            nativePrint("GitHub sync OK: " .. syncResult.latestPath)
        else
            nativePrint("GitHub sync FAILED: " .. tostring(syncResult))
            nativePrint("Local report is still safe at: " .. resultPath)
        end
    elseif syncLoaded then
        nativePrint("GitHub auto-sync not configured. Run once: report_sync setup")
    else
        nativePrint("GitHub auto-sync unavailable: " .. tostring(ReportSync))
    end
else
    nativePrint("")
    nativePrint("WARNING: Could not create " .. resultPath)
end

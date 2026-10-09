local Game = require("src.game")
local Bot = require("src.bot")
local cards = require("src.cards")
local config = require("config")

local args = { ... }

local RESULT_PATH = "evolution_results.txt"
local DEFAULT_SEED = 2608
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
    nativePrint("Usage:")
    nativePrint("  evo_compare <10-100> [all] [seed]")
    nativePrint("  evo_compare <10-100> <evolution_card_id> [seed]")
    nativePrint("")
    nativePrint("Examples:")
    nativePrint("  evo_compare 30")
    nativePrint("  evo_compare 50 all 2608")
    nativePrint("  evo_compare 100 creeper 1337")
    nativePrint("  evo_compare 100 nether_portal 2026")
    nativePrint("")
    nativePrint("Each context runs 4 matches:")
    nativePrint("  BASE/P1, BASE/P2, EVO/P1, EVO/P2")
    nativePrint("BASE has no Evolution Slot. EVO forces the tested card into the slot.")
    nativePrint("Both variants use the exact same deck shell/opponent and paired gameplay seeds.")
end

local rawCount = args[1]
if rawCount == nil or rawCount == "help" or rawCount == "--help" or rawCount == "-h" then
    printUsage()
    return
end

local contextCount = tonumber(rawCount)
if not contextCount
    or contextCount ~= math.floor(contextCount)
    or contextCount < 10
    or contextCount > 100
then
    nativePrint("ERROR: Context count must be a whole number from 10 to 100.")
    printUsage()
    return
end

local requested = args[2]
local seedArg = args[3]
local evolutionCards = {}

if requested == nil or string.lower(tostring(requested)) == "all" then
    for _, card in ipairs(cards.evolutionCards()) do
        evolutionCards[#evolutionCards + 1] = card.id
    end
else
    local cardId = tostring(requested)
    if not cards.get(cardId) then
        nativePrint("ERROR: Unknown selectable card ID: " .. cardId)
        return
    end
    if not cards.isSelectable(cardId) then
        nativePrint("ERROR: " .. cardId .. " is currently DEV ONLY.")
        return
    end
    if not cards.hasEvolution(cardId) then
        nativePrint("ERROR: " .. cardId .. " has no Evolution definition.")
        return
    end
    evolutionCards[1] = cardId
    seedArg = args[3]
end

if #evolutionCards == 0 then
    nativePrint("ERROR: No Evolution cards are currently defined.")
    return
end

local seed = math.floor(tonumber(seedArg) or DEFAULT_SEED)
local rngState = seed % 2147483647
if rngState <= 0 then rngState = 1 end

local function randomInt(maximum)
    rngState = (rngState * 48271) % 2147483647
    return (rngState % maximum) + 1
end

local function copy(list)
    local out = {}
    for i, value in ipairs(list) do out[i] = value end
    return out
end

local function shuffle(list)
    local out = copy(list)
    for i = #out, 2, -1 do
        local j = randomInt(i)
        out[i], out[j] = out[j], out[i]
    end
    return out
end

local function buildContext(subjectCardId)
    local pool = {}
    for _, card in ipairs(cards.list) do
        if card.id ~= subjectCardId then
            pool[#pool + 1] = card.id
        end
    end

    pool = shuffle(pool)

    local support = {}
    local opponent = {}
    for i = 1, 7 do support[i] = pool[i] end
    for i = 1, 8 do opponent[i] = pool[i + 7] end

    local subjectSlot = randomInt(8)
    local subjectDeck = {}
    local supportIndex = 1

    for slot = 1, 8 do
        if slot == subjectSlot then
            subjectDeck[slot] = subjectCardId
        else
            subjectDeck[slot] = support[supportIndex]
            supportIndex = supportIndex + 1
        end
    end

    return subjectDeck, shuffle(opponent), subjectSlot
end

local function newAggregate()
    return {
        matches = 0,
        wins = 0,
        draws = 0,
        losses = 0,
        score = 0,
        totalTime = 0,
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
        matchesWithEvolution = 0,
    }
end

local function addResult(agg, result)
    agg.matches = agg.matches + 1
    agg.totalTime = agg.totalTime + result.elapsed
    agg.score = agg.score + result.score

    if result.score == 1 then
        agg.wins = agg.wins + 1
    elseif result.score == 0.5 then
        agg.draws = agg.draws + 1
    else
        agg.losses = agg.losses + 1
    end

    local stat = result.cardStat or {}
    agg.plays = agg.plays + (stat.plays or 0)
    agg.emeraldSpent = agg.emeraldSpent + (stat.emeraldSpent or 0)
    agg.unitDamage = agg.unitDamage + (stat.unitDamage or 0)
    agg.towerDamage = agg.towerDamage + (stat.towerDamage or 0)
    agg.kills = agg.kills + (stat.kills or 0)
    agg.towersKilled = agg.towersKilled + (stat.towersKilled or 0)
    agg.emeraldBonus = agg.emeraldBonus + (stat.emeraldBonus or 0)
    agg.slowSeconds = agg.slowSeconds + (stat.slowSeconds or 0)
    agg.targetsHit = agg.targetsHit + (stat.targetsHit or 0)
    agg.evolutionPlays = agg.evolutionPlays + (stat.evolutionPlays or 0)

    if (stat.evolutionPlays or 0) > 0 then
        agg.matchesWithEvolution = agg.matchesWithEvolution + 1
    end
end

local function normalizeSeed(value)
    value = math.floor(tonumber(value) or 1) % 2147483647
    if value <= 0 then value = value + 2147483646 end
    return value
end

local function runMatch(subjectDeck, opponentDeck, subjectCardId, subjectOwner, useEvolution, gameplaySeed)
    local deck1 = subjectOwner == 1 and subjectDeck or opponentDeck
    local deck2 = subjectOwner == 1 and opponentDeck or subjectDeck

    local state = Game.new(nil, {
        headlessSimulation = true,
    })
    local bot1 = Bot.new(1, deck1)
    local bot2 = Bot.new(2, deck2)

    Bot.prepare(bot1, state)
    Bot.prepare(bot2, state)

    -- The benchmark isolates exactly one variable: whether the tested subject
    -- card owns the Evolution Slot. Any other Evo-capable cards in either deck
    -- are deliberately prevented from evolving in both variants.
    state.players[1].evolutionCardId = nil
    state.players[1].evolutionProgress = 0
    state.players[2].evolutionCardId = nil
    state.players[2].evolutionProgress = 0

    if useEvolution then
        state.players[subjectOwner].evolutionCardId = subjectCardId
    end

    -- Use the same gameplay seed for corresponding BASE/EVO matches. Context
    -- generation uses the private Park-Miller RNG above, so reseeding Lua's
    -- global RNG here cannot change the decks being compared.
    math.randomseed(normalizeSeed(gameplaySeed))

    state.players[1].ready = true
    state.players[2].ready = true
    local started, skippedTicks = Game.startHeadlessBattle(state, SIM_DT)
    if not started then error(skippedTicks or "Could not start headless battle", 0) end

    Bot.beginMatch(bot1)
    Bot.beginMatch(bot2)
    bot1.enabled = true
    bot2.enabled = true

    local transitionTick = math.max(0, skippedTicks - 1)
    if transitionTick % 2 == 0 then
        Bot.update(bot1, state, SIM_DT)
        Bot.update(bot2, state, SIM_DT)
    else
        Bot.update(bot2, state, SIM_DT)
        Bot.update(bot1, state, SIM_DT)
    end

    local ticks = skippedTicks
    local maxSimulationSeconds = config.MATCH.countdown
        + config.MATCH.normalTime
        + config.MATCH.overtimeTime
        + 30
    local maxTicks = math.ceil(maxSimulationSeconds / SIM_DT)

    while state.phase ~= "result" and ticks < maxTicks do
        Game.update(state, SIM_DT)

        if ticks % 2 == 0 then
            Bot.update(bot1, state, SIM_DT)
            Bot.update(bot2, state, SIM_DT)
        else
            Bot.update(bot2, state, SIM_DT)
            Bot.update(bot1, state, SIM_DT)
        end

        ticks = ticks + 1

        if ticks % YIELD_CHECK_TICKS == 0 then
            cooperativeYield(false)
        end
    end

    cooperativeYield(false)

    if state.phase ~= "result" then
        Game.finish(state, nil, "EVOLUTION COMPARISON TIMEOUT")
    end

    local score
    if state.winner == subjectOwner then
        score = 1
    elseif state.winner == nil then
        score = 0.5
    else
        score = 0
    end

    local playerStats = state.stats.players[subjectOwner]
    local cardStat = playerStats.cards[subjectCardId] or {}

    return {
        score = score,
        elapsed = state.stats.elapsed or 0,
        cardStat = cardStat,
    }
end

local function mean(values)
    if #values == 0 then return 0 end
    local total = 0
    for _, value in ipairs(values) do total = total + value end
    return total / #values
end

local function sampleStdDev(values, avg)
    if #values < 2 then return 0 end

    local total = 0
    for _, value in ipairs(values) do
        local delta = value - avg
        total = total + delta * delta
    end

    return math.sqrt(total / (#values - 1))
end

local function summarize(agg)
    local matches = math.max(1, agg.matches)
    local emeralds = math.max(0, agg.emeraldSpent)

    return {
        scoreRate = agg.score / matches * 100,
        playsPerMatch = agg.plays / matches,
        unitPerE = emeralds > 0 and agg.unitDamage / emeralds or 0,
        towerPerE = emeralds > 0 and agg.towerDamage / emeralds or 0,
        killsPerMatch = agg.kills / matches,
        towerKillsPerMatch = agg.towersKilled / matches,
        bonusPerMatch = agg.emeraldBonus / matches,
        slowPerPlay = agg.plays > 0 and agg.slowSeconds / agg.plays or 0,
        hitsPerPlay = agg.plays > 0 and agg.targetsHit / agg.plays or 0,
        evoPerMatch = agg.evolutionPlays / matches,
        evoShare = agg.plays > 0 and agg.evolutionPlays / agg.plays * 100 or 0,
        reachedPct = agg.matchesWithEvolution / matches * 100,
        avgTime = agg.totalTime / matches,
    }
end

local function signalFor(delta, ciLow, ciHigh)
    if ciLow > 0 then
        return delta >= 10 and "CLEAR LARGE BOOST" or "CLEAR BOOST"
    end
    if ciHigh < 0 then
        return delta <= -10 and "CLEAR LARGE PENALTY" or "CLEAR PENALTY"
    end
    if math.abs(delta) < 3 then
        return "NO CLEAR IMPACT"
    end
    return delta > 0 and "LEAN BOOST" or "LEAN PENALTY"
end

local totalMatches = #evolutionCards * contextCount * 4
liveHandle = fs and fs.open(RESULT_PATH, "w") or nil

reportPrint("CC-Minecraft Royale controlled Evolution impact analysis")
reportPrint(("Tick: %.2fs"):format(SIM_DT))
reportPrint(("Contexts/evolution: %d   Evolutions: %d   Total matches: %d   Seed: %d"):format(
    contextCount,
    #evolutionCards,
    totalMatches,
    seed
))
reportPrint("Each context compares the exact same subject deck and opponent deck with side swapping.")
reportPrint("BASE disables all Evolution Slots. EVO enables only the tested card's Evolution Slot.")
reportPrint("Corresponding BASE/EVO matches are reseeded with the same gameplay RNG seed.")
reportPrint("This measures the raw contribution of that Evolution Slot, not its opportunity cost versus another Evolution.")
reportPrint("")

local completedMatches = 0

for evolutionIndex, cardId in ipairs(evolutionCards) do
    local card = cards.get(cardId)
    local evolved = cards.evolvedCopy(cardId)
    local aggBase = newAggregate()
    local aggEvo = newAggregate()
    local pairedDeltas = {}
    local baseEdges = 0
    local evoEdges = 0
    local ties = 0
    local slotCounts = {}

    reportPrint(("RUN %d/%d: %s -> %s"):format(
        evolutionIndex,
        #evolutionCards,
        card.name,
        evolved and evolved.name or "Evolution"
    ))

    for contextIndex = 1, contextCount do
        local subjectDeck, opponentDeck, subjectSlot = buildContext(cardId)
        slotCounts[subjectSlot] = (slotCounts[subjectSlot] or 0) + 1

        local seedP1 = randomInt(2147483000)
        local seedP2 = randomInt(2147483000)

        local baseP1 = runMatch(subjectDeck, opponentDeck, cardId, 1, false, seedP1)
        local evoP1 = runMatch(subjectDeck, opponentDeck, cardId, 1, true, seedP1)
        local baseP2 = runMatch(subjectDeck, opponentDeck, cardId, 2, false, seedP2)
        local evoP2 = runMatch(subjectDeck, opponentDeck, cardId, 2, true, seedP2)

        addResult(aggBase, baseP1)
        addResult(aggBase, baseP2)
        addResult(aggEvo, evoP1)
        addResult(aggEvo, evoP2)

        local contextBase = baseP1.score + baseP2.score
        local contextEvo = evoP1.score + evoP2.score
        local delta = (contextEvo - contextBase) / 2 * 100

        pairedDeltas[#pairedDeltas + 1] = delta

        if contextBase > contextEvo then
            baseEdges = baseEdges + 1
        elseif contextEvo > contextBase then
            evoEdges = evoEdges + 1
        else
            ties = ties + 1
        end

        completedMatches = completedMatches + 4

        if contextIndex % 10 == 0 or contextIndex == contextCount then
            reportPrint(("  %d/%d contexts  (%d/%d total matches)"):format(
                contextIndex,
                contextCount,
                completedMatches,
                totalMatches
            ))
            if sleep then sleep(0) end
        end
    end

    local baseSummary = summarize(aggBase)
    local evoSummary = summarize(aggEvo)
    local delta = evoSummary.scoreRate - baseSummary.scoreRate

    local pairedMean = mean(pairedDeltas)
    local pairedSd = sampleStdDev(pairedDeltas, pairedMean)
    local pairedSe = pairedSd / math.sqrt(math.max(1, #pairedDeltas))
    local half = 1.96 * pairedSe
    local ciLow = pairedMean - half
    local ciHigh = pairedMean + half
    local signal = signalFor(delta, ciLow, ciHigh)

    reportPrint("")
    reportPrint(("EVOLUTION|%s|base=%s|evolved=%s"):format(
        cardId,
        card.name,
        evolved and evolved.name or "Evolution"
    ))
    reportPrint(("RULE|cycles=%d|evolves_on_play=%d|base_cost=%.1f|evo_cost=%.1f"):format(
        cards.evolutionCycles(cardId) or 0,
        cards.evolutionPlayNumber(cardId) or 1,
        card.cost,
        cards.evolutionCost(cardId) or card.cost
    ))
    reportPrint(("SCORE|BASE=%.2f%%|EVO=%.2f%%|DELTA_EVO_MINUS_BASE=%+.2fpp"):format(
        baseSummary.scoreRate,
        evoSummary.scoreRate,
        delta
    ))
    reportPrint(("PAIRED_95CI|mean=%+.2fpp|low=%+.2fpp|high=%+.2fpp|signal=%s"):format(
        pairedMean,
        ciLow,
        ciHigh,
        signal
    ))
    reportPrint(("CONTEXT_EDGE|BASE=%d|EVO=%d|TIE=%d"):format(
        baseEdges,
        evoEdges,
        ties
    ))
    reportPrint(("BASE_CARD|plays/match=%.2f|unit/E=%.2f|tower/E=%.2f|kills/match=%.2f|avg_match=%.1fs"):format(
        baseSummary.playsPerMatch,
        baseSummary.unitPerE,
        baseSummary.towerPerE,
        baseSummary.killsPerMatch,
        baseSummary.avgTime
    ))
    reportPrint(("EVO_CARD|plays/match=%.2f|evo/match=%.2f|evo_share=%.1f%%|reached=%.1f%%|unit/E=%.2f|tower/E=%.2f|kills/match=%.2f|avg_match=%.1fs"):format(
        evoSummary.playsPerMatch,
        evoSummary.evoPerMatch,
        evoSummary.evoShare,
        evoSummary.reachedPct,
        evoSummary.unitPerE,
        evoSummary.towerPerE,
        evoSummary.killsPerMatch,
        evoSummary.avgTime
    ))

    if baseSummary.bonusPerMatch > 0
        or evoSummary.bonusPerMatch > 0
        or baseSummary.slowPerPlay > 0
        or evoSummary.slowPerPlay > 0
        or baseSummary.hitsPerPlay > 0
        or evoSummary.hitsPerPlay > 0
    then
        reportPrint(("UTILITY_BASE|bonus/match=%.2f|slow/play=%.2f|hits/play=%.2f"):format(
            baseSummary.bonusPerMatch,
            baseSummary.slowPerPlay,
            baseSummary.hitsPerPlay
        ))
        reportPrint(("UTILITY_EVO|bonus/match=%.2f|slow/play=%.2f|hits/play=%.2f"):format(
            evoSummary.bonusPerMatch,
            evoSummary.slowPerPlay,
            evoSummary.hitsPerPlay
        ))
    end

    local slotParts = {}
    for slot = 1, 8 do
        slotParts[#slotParts + 1] = tostring(slot) .. ":" .. tostring(slotCounts[slot] or 0)
    end
    reportPrint("SUBJECT_SLOTS|" .. table.concat(slotParts, ","))
    reportPrint("")
end

reportPrint("HOW TO READ")
reportPrint("DELTA_EVO_MINUS_BASE isolates the tested Evolution against the same card/deck with no Evolution Slot.")
reportPrint("PAIRED_95CI uses context-by-context BASE/EVO differences after swapping P1/P2.")
reportPrint("reached = percent of EVO matches where the card actually cycled far enough to deploy at least one Evolution.")
reportPrint("evo_share = percent of that card's actual plays that were evolved in the EVO variant.")
reportPrint("CLEAR BOOST means the paired interval is entirely above zero; CLEAR LARGE BOOST also exceeds +10pp.")
reportPrint("A large boost is not automatically overpowered: Evolution Slots are supposed to add power and have cycle/opportunity costs.")
reportPrint("Use mixed simulation afterward to judge the resulting card/deck meta.")
reportPrint("")
reportPrint("Recommended:")
reportPrint(string.format(
    "  evo_compare 30 all             -- %d-match first pass with %d current Evolutions",
    #cards.evolutionCards() * 30 * 4,
    #cards.evolutionCards()
))
reportPrint("  evo_compare 100 <card_id>      -- confirm one Evolution")
reportPrint("  simulate 1000 mixed            -- overall meta after Evolutions")
reportPrint("")
reportPrint("Saved report: " .. RESULT_PATH)

if liveHandle then
    liveHandle.close()
    nativePrint("")
    nativePrint("View it with: type " .. RESULT_PATH)

    local syncLoaded, ReportSync = pcall(require, "src.report_sync")
    if syncLoaded and ReportSync.isConfigured() then
        nativePrint("Syncing Evolution report to GitHub...")
        local synced, syncResult = ReportSync.autoUpload("evolution", RESULT_PATH)
        if synced then
            nativePrint("GitHub sync OK: " .. syncResult.latestPath)
        else
            nativePrint("GitHub sync FAILED: " .. tostring(syncResult))
            nativePrint("Local report is still safe at: " .. RESULT_PATH)
        end
    elseif syncLoaded then
        nativePrint("GitHub auto-sync not configured. Run once: report_sync setup")
    else
        nativePrint("GitHub auto-sync unavailable: " .. tostring(ReportSync))
    end
else
    nativePrint("")
    nativePrint("WARNING: Could not create " .. RESULT_PATH)
end

local Game = require("src.game")
local Bot = require("src.bot")
local cards = require("src.cards")
local config = require("config")

local args = { ... }

local RESULT_PATH = "comparison_results.txt"
local DEFAULT_SEED = 1337
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

local DEFAULT_COMPARISONS = {
    {
        id = "zombie_vs_wither",
        a = "zombie",
        b = "wither_skeleton",
        note = "Direct 3E melee sidegrade",
    },
    {
        id = "slime_vs_magma",
        a = "slime",
        b = "magma_cube",
        note = "Direct 3E split-melee sidegrade",
    },
    {
        id = "cannon_vs_outpost",
        a = "cannon",
        b = "pillager_outpost",
        note = "Direct 4E defensive-building sidegrade",
    },
    {
        id = "golem_vs_enderman",
        a = "iron_golem",
        b = "enderman",
        note = "Diagnostic: same-cost 5E control, not a direct role replacement",
    },
    {
        id = "skeleton_vs_snow",
        a = "skeleton",
        b = "snow_golem",
        note = "Diagnostic: 3E ranged air/ground support comparison",
    },
    {
        id = "bats_vs_spider",
        a = "bat_swarm",
        b = "spider",
        note = "Diagnostic: 2E fast-pressure comparison",
    },
}

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
    nativePrint("  compare <10-100> [all] [seed]")
    nativePrint("  compare <10-100> <cardA_id> <cardB_id> [seed]")
    nativePrint("")
    nativePrint("Examples:")
    nativePrint("  compare 30")
    nativePrint("  compare 50 all 1337")
    nativePrint("  compare 100 zombie wither_skeleton 1337")
    nativePrint("  compare 100 iron_golem enderman 2026")
    nativePrint("")
    nativePrint("Count = paired deck contexts per comparison.")
    nativePrint("Each context runs 4 matches: A/P1, A/P2, B/P1, B/P2.")
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

local comparisons = {}
local seed

if args[2] == nil or string.lower(tostring(args[2])) == "all" then
    for _, spec in ipairs(DEFAULT_COMPARISONS) do
        comparisons[#comparisons + 1] = spec
    end
    seed = math.floor(tonumber(args[3]) or DEFAULT_SEED)
else
    local a = tostring(args[2])
    local b = tostring(args[3] or "")
    if not cards.get(a) or not cards.get(b) or a == b then
        nativePrint("ERROR: Custom comparison needs two different selectable card IDs.")
        printUsage()
        return
    end

    comparisons[1] = {
        id = a .. "_vs_" .. b,
        a = a,
        b = b,
        note = "Custom controlled replacement comparison",
    }
    seed = math.floor(tonumber(args[4]) or DEFAULT_SEED)
end

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

local function buildContext(cardA, cardB)
    local pool = {}
    for _, card in ipairs(cards.list) do
        if card.id ~= cardA and card.id ~= cardB then
            pool[#pool + 1] = card.id
        end
    end

    pool = shuffle(pool)

    local support = {}
    local opponent = {}
    for i = 1, 7 do support[i] = pool[i] end
    for i = 1, 8 do opponent[i] = pool[i + 7] end

    local replacementSlot = randomInt(8)
    local deckA = {}
    local deckB = {}
    local supportIndex = 1

    for slot = 1, 8 do
        if slot == replacementSlot then
            deckA[slot] = cardA
            deckB[slot] = cardB
        else
            deckA[slot] = support[supportIndex]
            deckB[slot] = support[supportIndex]
            supportIndex = supportIndex + 1
        end
    end

    return deckA, deckB, shuffle(opponent), replacementSlot
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

    local stat = result.cardStat
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
end

local function runMatch(subjectDeck, opponentDeck, subjectCardId, subjectOwner)
    local deck1 = subjectOwner == 1 and subjectDeck or opponentDeck
    local deck2 = subjectOwner == 1 and opponentDeck or subjectDeck

    local state = Game.new(nil, {
        headlessSimulation = true,
    })
    local bot1 = Bot.new(1, deck1)
    local bot2 = Bot.new(2, deck2)

    Bot.prepare(bot1, state)
    Bot.prepare(bot2, state)

    -- This benchmark isolates base-card replacement impact. Evolutions are
    -- deliberately disabled here; Evolution power has its own paired
    -- evo_compare benchmark.
    state.ruleset.evolutions = false
    state.players[1].evolutionCardId = nil
    state.players[1].evolutionProgress = 0
    state.players[2].evolutionCardId = nil
    state.players[2].evolutionProgress = 0

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
        Game.finish(state, nil, "COMPARISON TIMEOUT")
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
    local sum = 0
    for _, value in ipairs(values) do sum = sum + value end
    return sum / #values
end

local function sampleStdDev(values, avg)
    if #values < 2 then return 0 end
    local sum = 0
    for _, value in ipairs(values) do
        local d = value - avg
        sum = sum + d * d
    end
    return math.sqrt(sum / (#values - 1))
end

local T95 = {
    [9] = 2.262, [10] = 2.228, [11] = 2.201, [12] = 2.179,
    [13] = 2.160, [14] = 2.145, [15] = 2.131, [16] = 2.120,
    [17] = 2.110, [18] = 2.101, [19] = 2.093, [20] = 2.086,
    [21] = 2.080, [22] = 2.074, [23] = 2.069, [24] = 2.064,
    [25] = 2.060, [26] = 2.056, [27] = 2.052, [28] = 2.048,
    [29] = 2.045, [30] = 2.042,
}

local function critical95(sampleCount)
    local df = math.max(1, sampleCount - 1)
    if df <= 30 then
        return T95[math.max(9, df)] or 2.262
    elseif df <= 40 then
        return 2.021
    elseif df <= 60 then
        return 2.000
    elseif df <= 80 then
        return 1.990
    elseif df <= 100 then
        return 1.984
    end
    return 1.960
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
        avgTime = agg.totalTime / matches,
    }
end

local function classify(delta, ciLow, ciHigh)
    if ciLow > 0 then
        return delta >= 8 and "CLEAR B++" or "CLEAR B"
    elseif ciHigh < 0 then
        return delta <= -8 and "CLEAR A++" or "CLEAR A"
    elseif math.abs(delta) < 3 then
        return "NEAR-EVEN"
    elseif delta > 0 then
        return "LEAN B"
    else
        return "LEAN A"
    end
end

local totalMatches = #comparisons * contextCount * 4

-- Only replace the prior report after all arguments have been validated.
liveHandle = fs and fs.open(RESULT_PATH, "w") or nil

reportPrint("CC-Minecraft Royale controlled replacement analysis")
reportPrint(("Tick: %.2fs"):format(SIM_DT))
reportPrint(("Contexts/comparison: %d   Comparisons: %d   Total matches: %d   Seed: %d"):format(
    contextCount,
    #comparisons,
    totalMatches,
    seed
))
reportPrint("Each context uses the same 7-card shell, same opponent deck and same replacement slot.")
reportPrint("Evolutions are disabled so this remains a pure BASE-card replacement benchmark.")
reportPrint("A and B each play once as P1 and once as P2. Compared cards are excluded from all other slots.")
reportPrint("")

local completedMatches = 0

for comparisonIndex, spec in ipairs(comparisons) do
    local cardA = cards.get(spec.a)
    local cardB = cards.get(spec.b)
    local aggA = newAggregate()
    local aggB = newAggregate()
    local pairedDeltas = {}
    local contextsA = 0
    local contextsB = 0
    local contextsTie = 0
    local slotCounts = {}

    reportPrint(("RUN %d/%d: %s vs %s"):format(
        comparisonIndex,
        #comparisons,
        cardA.name,
        cardB.name
    ))

    for contextIndex = 1, contextCount do
        local deckA, deckB, opponentDeck, replacementSlot = buildContext(spec.a, spec.b)
        slotCounts[replacementSlot] = (slotCounts[replacementSlot] or 0) + 1

        local aP1 = runMatch(deckA, opponentDeck, spec.a, 1)
        local aP2 = runMatch(deckA, opponentDeck, spec.a, 2)
        local bP1 = runMatch(deckB, opponentDeck, spec.b, 1)
        local bP2 = runMatch(deckB, opponentDeck, spec.b, 2)

        addResult(aggA, aP1)
        addResult(aggA, aP2)
        addResult(aggB, bP1)
        addResult(aggB, bP2)

        local contextScoreA = aP1.score + aP2.score
        local contextScoreB = bP1.score + bP2.score

        -- Difference in percentage-point contribution for this matched
        -- two-orientation context. Range is -100 to +100.
        local delta = (contextScoreB - contextScoreA) / 2 * 100
        pairedDeltas[#pairedDeltas + 1] = delta

        if contextScoreA > contextScoreB then
            contextsA = contextsA + 1
        elseif contextScoreB > contextScoreA then
            contextsB = contextsB + 1
        else
            contextsTie = contextsTie + 1
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

    local summaryA = summarize(aggA)
    local summaryB = summarize(aggB)
    local delta = summaryB.scoreRate - summaryA.scoreRate

    local pairedMean = mean(pairedDeltas)
    local pairedSd = sampleStdDev(pairedDeltas, pairedMean)
    local pairedSe = pairedSd / math.sqrt(math.max(1, #pairedDeltas))
    local ciHalf = critical95(#pairedDeltas) * pairedSe
    local ciLow = pairedMean - ciHalf
    local ciHigh = pairedMean + ciHalf
    local signal = classify(delta, ciLow, ciHigh)

    reportPrint("")
    reportPrint(("COMPARISON|%s|%s|%s"):format(spec.id, cardA.name, cardB.name))
    reportPrint("NOTE|" .. spec.note)
    reportPrint(("COST|A=%d|B=%d"):format(cardA.cost, cardB.cost))
    reportPrint(("SCORE|A=%.2f%%|B=%.2f%%|DELTA_B_MINUS_A=%+.2fpp"):format(
        summaryA.scoreRate,
        summaryB.scoreRate,
        delta
    ))
    reportPrint(("PAIRED_95CI|mean=%+.2fpp|low=%+.2fpp|high=%+.2fpp|signal=%s"):format(
        pairedMean,
        ciLow,
        ciHigh,
        signal
    ))
    reportPrint(("CONTEXT_EDGE|A=%d|B=%d|TIE=%d"):format(
        contextsA,
        contextsB,
        contextsTie
    ))
    reportPrint(("A_CARD|plays/match=%.2f|evo/match=%.2f|evo_share=%.1f%%|unit/E=%.2f|tower/E=%.2f|kills/match=%.2f|avg_match=%.1fs"):format(
        summaryA.playsPerMatch,
        summaryA.evoPerMatch,
        summaryA.evoShare,
        summaryA.unitPerE,
        summaryA.towerPerE,
        summaryA.killsPerMatch,
        summaryA.avgTime
    ))
    reportPrint(("B_CARD|plays/match=%.2f|evo/match=%.2f|evo_share=%.1f%%|unit/E=%.2f|tower/E=%.2f|kills/match=%.2f|avg_match=%.1fs"):format(
        summaryB.playsPerMatch,
        summaryB.evoPerMatch,
        summaryB.evoShare,
        summaryB.unitPerE,
        summaryB.towerPerE,
        summaryB.killsPerMatch,
        summaryB.avgTime
    ))

    if summaryA.bonusPerMatch > 0
        or summaryB.bonusPerMatch > 0
        or summaryA.slowPerPlay > 0
        or summaryB.slowPerPlay > 0
        or summaryA.hitsPerPlay > 0
        or summaryB.hitsPerPlay > 0
    then
        reportPrint(("UTILITY_A|bonus/match=%.2f|slow/play=%.2f|hits/play=%.2f"):format(
            summaryA.bonusPerMatch,
            summaryA.slowPerPlay,
            summaryA.hitsPerPlay
        ))
        reportPrint(("UTILITY_B|bonus/match=%.2f|slow/play=%.2f|hits/play=%.2f"):format(
            summaryB.bonusPerMatch,
            summaryB.slowPerPlay,
            summaryB.hitsPerPlay
        ))
    end

    local slotParts = {}
    for slot = 1, 8 do
        slotParts[#slotParts + 1] = tostring(slot) .. ":" .. tostring(slotCounts[slot] or 0)
    end
    reportPrint("REPLACEMENT_SLOTS|" .. table.concat(slotParts, ","))
    reportPrint("")
end

reportPrint("HOW TO READ")
reportPrint("DELTA_B_MINUS_A: positive means B won more often in otherwise identical deck contexts.")
reportPrint("PAIRED_95CI: Student-t interval from context-by-context A/B differences after side swapping.")
reportPrint("If the entire interval is above/below zero, the edge is much more convincing than a raw mixed win rate.")
reportPrint("NEAR-EVEN means the measured delta is under 3 percentage points and the interval crosses zero.")
reportPrint("LEAN means an observed edge whose interval still crosses zero; collect more contexts before balancing.")
reportPrint("CLEAR means the paired interval excludes zero. CLEAR ++ also has at least an 8pp measured edge.")
reportPrint("Diagnostic comparisons (Golem/Enderman etc.) compare impact, not identical tactical roles.")
reportPrint("evo/match and evo_share show how often the compared card actually reached its Evolution.")
reportPrint("")
reportPrint("Recommended:")
reportPrint("  compare 30 all        -- broad first pass")
reportPrint("  compare 100 A B       -- confirm one suspicious pair")
reportPrint("")
reportPrint("Saved report: " .. RESULT_PATH)

if liveHandle then
    liveHandle.close()
    nativePrint("")
    nativePrint("View it with: type " .. RESULT_PATH)

    local syncLoaded, ReportSync = pcall(require, "src.report_sync")
    if syncLoaded and ReportSync.isConfigured() then
        nativePrint("Syncing comparison report to GitHub...")
        local synced, syncResult = ReportSync.autoUpload("comparison", RESULT_PATH)
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

local benchmark = {}

function benchmark.newRandomInt(seed)
    local state = math.floor(tonumber(seed) or 1) % 2147483647
    if state <= 0 then state = 1 end

    return function(maximum)
        state = (state * 48271) % 2147483647
        return (state % maximum) + 1
    end
end

function benchmark.copy(list)
    local out = {}
    for i, value in ipairs(list) do
        out[i] = value
    end
    return out
end

function benchmark.shuffle(list, randomInt)
    local out = benchmark.copy(list)
    for i = #out, 2, -1 do
        local j = randomInt(i)
        out[i], out[j] = out[j], out[i]
    end
    return out
end

function benchmark.mean(values)
    if #values == 0 then return 0 end

    local total = 0
    for _, value in ipairs(values) do
        total = total + value
    end
    return total / #values
end

function benchmark.sampleStdDev(values, avg)
    if #values < 2 then return 0 end

    local total = 0
    for _, value in ipairs(values) do
        local delta = value - avg
        total = total + delta * delta
    end
    return math.sqrt(total / (#values - 1))
end

local T95 = {
    [1] = 12.706, [2] = 4.303, [3] = 3.182, [4] = 2.776,
    [5] = 2.571, [6] = 2.447, [7] = 2.365, [8] = 2.306,
    [9] = 2.262, [10] = 2.228, [11] = 2.201, [12] = 2.179,
    [13] = 2.160, [14] = 2.145, [15] = 2.131, [16] = 2.120,
    [17] = 2.110, [18] = 2.101, [19] = 2.093, [20] = 2.086,
    [21] = 2.080, [22] = 2.074, [23] = 2.069, [24] = 2.064,
    [25] = 2.060, [26] = 2.056, [27] = 2.052, [28] = 2.048,
    [29] = 2.045, [30] = 2.042,
}

function benchmark.critical95(sampleCount)
    local df = math.max(1, sampleCount - 1)
    if df <= 30 then return T95[df] end

    -- Cornish-Fisher expansion of the two-sided 95% Student-t quantile around
    -- z=.975. For df>=31 this is effectively exact at the precision printed by
    -- our reports (error is below ~0.000002 at df=31 and shrinks thereafter).
    local z = 1.959963984540054
    local v = df
    return z
        + (z^3 + z) / (4 * v)
        + (5 * z^5 + 16 * z^3 + 3 * z) / (96 * v^2)
        + (3 * z^7 + 19 * z^5 + 17 * z^3 - 15 * z) / (384 * v^3)
end

return benchmark

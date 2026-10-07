local util = {}

function util.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function util.distance(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end

function util.deepcopy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do
        out[util.deepcopy(k)] = util.deepcopy(v)
    end
    return out
end

function util.formatTime(seconds)
    seconds = math.max(0, math.ceil(seconds))
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    return string.format("%d:%02d", m, s)
end

function util.truncate(text, maxLen)
    text = tostring(text or "")
    if #text <= maxLen then return text end
    if maxLen <= 1 then return text:sub(1, maxLen) end
    return text:sub(1, maxLen - 1) .. "~"
end

return util
